#!/bin/bash
# Ein Backup-Lauf: Datenbank-Dump + Dateien -> restic-Repo auf rammstein
# (und optional in ein zweites, offsite gelegenes Repo).
set -uo pipefail

SITE="${SITE_NAME:?SITE_NAME fehlt}"
mkdir -p /work
# Fester Pfad statt mktemp: restic identifiziert Snapshots ueber den Pfad.
# Ein wechselnder Temp-Pfad kostet die Parent-Snapshot-Dedup und macht
# Restore-Pfade bei jedem Lauf anders.
WORK="/work"
STATUS=0
FAILED_STEP=""

log()  { echo "[$(date '+%F %T')] $*"; }
fail() { STATUS=1; FAILED_STEP="$1"; log "FEHLER in Schritt: $1"; }

cleanup() { rm -rf "${WORK:?}"/*; }
trap cleanup EXIT

# --------------------------------------------------------------- SSH-Schluessel
setup_ssh() {
  mkdir -p /root/.ssh && chmod 700 /root/.ssh
  if [ -n "${BACKUP_SSH_KEY_B64:-}" ]; then
    echo "$BACKUP_SSH_KEY_B64" | base64 -d > /root/.ssh/id_ed25519
    chmod 600 /root/.ssh/id_ed25519
  fi
  cat > /root/.ssh/config <<CFG
Host backup-target
    HostName ${BACKUP_SSH_HOST:-10.0.0.100}
    User ${BACKUP_SSH_USER:-root}
    IdentityFile /root/.ssh/id_ed25519
    StrictHostKeyChecking accept-new
    UserKnownHostsFile /root/.ssh/known_hosts
CFG
  chmod 600 /root/.ssh/config
}

# ------------------------------------------------------------ Datenbank sichern
dump_db() {
  local cfg="/sites/${SITE}/site_config.json"
  [ -f "$cfg" ] || { fail "site_config.json nicht gefunden ($cfg)"; return 1; }
  local db_name
  db_name=$(grep -o '"db_name"[^,]*' "$cfg" | cut -d'"' -f4)
  [ -n "$db_name" ] || { fail "db_name nicht lesbar"; return 1; }
  log "Dumpe Datenbank ${db_name} ..."
  mariadb-dump \
      --host="${DB_HOST:-db}" --user=root --password="${DB_ROOT_PASSWORD}" \
      --single-transaction --quick --routines --events \
      --default-character-set=utf8mb4 \
      --databases "$db_name" \
    | gzip -6 > "${WORK}/${SITE}-database.sql.gz"
  # PIPESTATUS[0] = mariadb-dump, nicht gzip
  if [ "${PIPESTATUS[0]}" -ne 0 ]; then fail "mariadb-dump"; return 1; fi
  log "Dump fertig: $(du -h "${WORK}/${SITE}-database.sql.gz" | cut -f1)"
}

# ------------------------------------------- site_config sichern (Encryption Key!)
dump_config() {
  cp "/sites/${SITE}/site_config.json" "${WORK}/site_config.json" || { fail "site_config kopieren"; return 1; }
  [ -f /sites/common_site_config.json ] && cp /sites/common_site_config.json "${WORK}/common_site_config.json"
  return 0
}

# ------------------------------------------------------------- restic-Repo-Lauf
run_restic() {
  local repo="$1" label="$2"
  export RESTIC_REPOSITORY="$repo"
  export RESTIC_PASSWORD="${RESTIC_PASSWORD}"

  if ! restic cat config >/dev/null 2>&1; then
    log "[$label] Repo existiert noch nicht - initialisiere"
    restic init || { fail "restic init ($label)"; return 1; }
  fi

  log "[$label] sichere Dump + Dateien ..."
  restic backup \
      --host "erpnext-${SITE}" \
      --tag erpnext --tag "$label" \
      "$WORK" \
      "/sites/${SITE}/private/files" \
      "/sites/${SITE}/public/files" \
    || { fail "restic backup ($label)"; return 1; }

  log "[$label] raeume alte Snapshots auf ..."
  restic forget --prune \
      --keep-daily   "${KEEP_DAILY:-14}" \
      --keep-weekly  "${KEEP_WEEKLY:-8}" \
      --keep-monthly "${KEEP_MONTHLY:-12}" \
    || { fail "restic forget ($label)"; return 1; }

  restic check --read-data-subset=2% >/dev/null 2>&1 \
    || log "[$label] Hinweis: restic check meldete Auffaelligkeiten (nicht fatal)"

  log "[$label] fertig. Snapshots: $(restic snapshots --compact 2>/dev/null | tail -2 | head -1)"
}

# ----------------------------------------------------------------- Benachrichtigung
notify() {
  local ok="$1" text="$2"
  # Uptime-Kuma-Push oder beliebiger Webhook: nur bei Erfolg pingen,
  # damit Kuma ein ausgebliebenes Backup selbst als Ausfall erkennt.
  if [ -n "${BACKUP_PUSH_URL:-}" ] && [ "$ok" = "1" ]; then
    local pcode
    pcode=$(curl -sS -m 20 -o /dev/null -w '%{http_code}' "${BACKUP_PUSH_URL}" 2>/dev/null || echo 000)
    case "$pcode" in
      2*) log "Push-Ping gesendet (HTTP $pcode)" ;;
      *)  log "Push-Ping nicht zustellbar (HTTP $pcode)" ;;
    esac
  fi

  if [ -n "${BACKUP_WEBHOOK_URL:-}" ] && [ "$ok" = "0" ]; then
    local payload
    payload=$(printf '{"content":"**ERPNext-Backup fehlgeschlagen** (%s)\\nSchritt: %s\\nHost: %s\\nZeit: %s"}' \
              "$SITE" "$text" "$(hostname)" "$(date '+%F %T %Z')")
    local code
    code=$(curl -sS -m 20 -o /dev/null -w '%{http_code}' \
           -H 'Content-Type: application/json' -d "$payload" "${BACKUP_WEBHOOK_URL}" 2>/dev/null || echo 000)
    case "$code" in
      2*) log "Fehler-Webhook gesendet (HTTP $code)" ;;
      *)  log "Fehler-Webhook nicht zustellbar (HTTP $code)" ;;
    esac
  fi
}

# ------------------------------------------------------------------------ Ablauf
log "=== Backup-Lauf fuer ${SITE} startet ==="
setup_ssh
dump_db
dump_config

if [ "$STATUS" -eq 0 ]; then
  : "${RESTIC_REPOSITORY_PRIMARY:?RESTIC_REPOSITORY_PRIMARY fehlt}"
  run_restic "${RESTIC_REPOSITORY_PRIMARY}" "rammstein"

  if [ -n "${RESTIC_REPOSITORY_OFFSITE:-}" ]; then
    run_restic "${RESTIC_REPOSITORY_OFFSITE}" "offsite"
  else
    log "Offsite-Repo nicht konfiguriert (RESTIC_REPOSITORY_OFFSITE leer) - uebersprungen"
  fi
fi

if [ "$STATUS" -eq 0 ]; then
  log "=== Backup-Lauf erfolgreich ==="
  echo "ok $(date '+%F %T')" > /tmp/last-backup-status
  notify 1 ""
else
  log "=== Backup-Lauf FEHLGESCHLAGEN (${FAILED_STEP}) ==="
  echo "fail $(date '+%F %T') ${FAILED_STEP}" > /tmp/last-backup-status
  notify 0 "${FAILED_STEP}"
fi
exit "$STATUS"
