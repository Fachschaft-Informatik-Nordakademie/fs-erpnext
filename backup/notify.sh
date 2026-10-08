#!/bin/bash
# Benachrichtigung eines Backup-Laufs (wird von run-backup.sh gesourct; braucht log(), SITE, HOSTNAME).
#
#   BACKUP_PUSH_URL     nur bei Erfolg gepingt (Uptime-Kuma-Push): bleibt er aus, schlaegt Kuma selbst Alarm.
#   BACKUP_ALERT_URL    Alerts-Manager (infrastructure-scripts, POST /relay/alert/<secret>): Fehlschlag = offener
#                       Alert (critical, @here), Erfolg = resolved (die Discord-Nachricht verschwindet).
#                       BACKUP_ALERT_SOURCE/BACKUP_ALERT_KEY (Default erpnext/backup): wird der Lauf von
#                       infrastructure-scripts geplant, dessen Job-Key nehmen (infrastructure-scripts /
#                       job:erpnext-backup), dann ergeben Sidecar und Job EINE Nachricht mit einem Ping.
#   BACKUP_WEBHOOK_URL  direkter Discord-Webhook: nur ohne BACKUP_ALERT_URL oder wenn der Alerts-Manager nicht
#                       erreichbar ist (fail open: ein Backup-Fehler darf nie verloren gehen).

json_str() {   # JSON-String-Inhalt (ohne Anfuehrungszeichen) fuer beliebigen Text
  local s="$1"
  s=${s//\\/\\\\}; s=${s//\"/\\\"}; s=${s//$'\n'/\\n}; s=${s//$'\r'/}; s=${s//$'\t'/ }
  printf '%s' "$s"
}

post_json() {  # post_json <url> <json> -> HTTP-Code (000 = nicht erreichbar)
  curl -sS -m 20 -o /dev/null -w '%{http_code}' -H 'Content-Type: application/json' -d "$2" "$1" 2>/dev/null || echo 000
}

notify_discord() {
  local text now payload code
  text=$(json_str "$1"); now=$(date '+%d.%m.%Y %H:%M:%S %Z')
  # Laut und unuebersehbar: @here-Ping plus roter Embed. Ein stilles Backup-Problem
  # faellt sonst erst auf, wenn man das Backup braucht - und dann ist es zu spaet.
  payload=$(cat <<JSON
{
  "content": "@here 🚨🚨 **BACKUP FEHLGESCHLAGEN** 🚨🚨",
  "allowed_mentions": { "parse": ["everyone"] },
  "embeds": [{
    "title": "🔴 ERPNext-Backup ist NICHT durchgelaufen",
    "description": "Die Vereinsbuchhaltung wurde **nicht gesichert**. Solange das nicht behoben ist, gibt es keine aktuelle Sicherung der Buchhaltung und der Belege.",
    "color": 15158332,
    "fields": [
      { "name": "Fehlgeschlagener Schritt", "value": "\`${text}\`", "inline": true },
      { "name": "Site", "value": "$(json_str "$SITE")", "inline": true },
      { "name": "Zeitpunkt", "value": "${now}", "inline": false },
      { "name": "Was jetzt zu tun ist", "value": "Logs ansehen: Coolify → erpnext-fs-informatik → Service \`backup\`. Nach dem Fix laesst sich ein Lauf sofort nachholen: \`docker exec <backup-container> /usr/local/bin/run-backup.sh\`" }
    ],
    "footer": { "text": "Backup-Dienst · $(json_str "$SITE") · Container $(json_str "${HOSTNAME:-}")" }
  }]
}
JSON
)
  code=$(post_json "$BACKUP_WEBHOOK_URL" "$payload")
  case "$code" in
    2*) log "Fehler-Webhook gesendet (HTTP $code)" ;;
    *)  log "Fehler-Webhook nicht zustellbar (HTTP $code)" ;;
  esac
}

notify_manager() {   # notify_manager <ok> <step> -> 0 wenn angenommen
  local ok="$1" state body code now
  now=$(date '+%d.%m.%Y %H:%M:%S %Z')
  if [ "$ok" = "1" ]; then
    state=resolved; body="Backup-Lauf erfolgreich (${now})."
  else
    state=firing
    body="Die Vereinsbuchhaltung wurde NICHT gesichert.
Fehlgeschlagener Schritt: $2
Site: ${SITE}
Zeitpunkt: ${now}
Container: ${HOSTNAME:-}
Logs: Coolify -> erpnext-fs-informatik -> Service backup. Lauf nachholen: docker exec <backup-container> /usr/local/bin/run-backup.sh"
  fi
  code=$(post_json "$BACKUP_ALERT_URL" "$(cat <<JSON
{"source": "$(json_str "${BACKUP_ALERT_SOURCE:-erpnext}")", "key": "$(json_str "${BACKUP_ALERT_KEY:-backup}")",
 "title": "ERPNext-Backup ist NICHT durchgelaufen ($(json_str "$SITE"))", "body": "$(json_str "$body")",
 "level": "critical", "state": "${state}"}
JSON
)")
  case "$code" in
    2*) log "Alerts-Manager: ${state} gemeldet (HTTP $code)"; return 0 ;;
    *)  log "Alerts-Manager nicht erreichbar (HTTP $code)"; return 1 ;;
  esac
}

notify() {   # notify <ok 1|0> <fehlgeschlagener Schritt>
  local ok="$1" text="$2"
  if [ -n "${BACKUP_PUSH_URL:-}" ] && [ "$ok" = "1" ]; then
    local pcode
    pcode=$(curl -sS -m 20 -o /dev/null -w '%{http_code}' "${BACKUP_PUSH_URL}" 2>/dev/null || echo 000)
    case "$pcode" in
      2*) log "Push-Ping gesendet (HTTP $pcode)" ;;
      *)  log "Push-Ping nicht zustellbar (HTTP $pcode)" ;;
    esac
  fi
  if [ -n "${BACKUP_ALERT_URL:-}" ] && notify_manager "$ok" "$text"; then
    return 0
  fi
  if [ -n "${BACKUP_WEBHOOK_URL:-}" ] && [ "$ok" = "0" ]; then
    notify_discord "$text"
  fi
}
