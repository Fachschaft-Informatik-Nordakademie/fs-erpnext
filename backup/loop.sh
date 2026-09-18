#!/bin/bash
# Wartet bis zur konfigurierten Uhrzeit und stoesst dann einen Lauf an.
# Kein Host-Cron, kein systemd-Timer - der Zeitplan lebt im Stack.
set -u
HOUR="${BACKUP_HOUR:-3}"
MIN="${BACKUP_MINUTE:-15}"

echo "[loop] Backup-Dienst gestartet. Taeglicher Lauf um ${HOUR}:$(printf '%02d' "$MIN") ${TZ}."

if [ "${BACKUP_RUN_ON_START:-0}" = "1" ]; then
  echo "[loop] BACKUP_RUN_ON_START=1 -> sofortiger Erstlauf"
  /usr/local/bin/run-backup.sh || echo "[loop] Erstlauf fehlgeschlagen (siehe oben)"
fi

while true; do
  now=$(date +%s)
  today=$(date -d "today ${HOUR}:${MIN}" +%s 2>/dev/null)
  if [ "$today" -le "$now" ]; then
    next=$(date -d "tomorrow ${HOUR}:${MIN}" +%s)
  else
    next=$today
  fi
  sleep_for=$(( next - now ))
  echo "[loop] naechster Lauf: $(date -d "@$next" '+%Y-%m-%d %H:%M:%S %Z') (in ${sleep_for}s)"
  sleep "$sleep_for"
  /usr/local/bin/run-backup.sh || echo "[loop] Lauf fehlgeschlagen (siehe oben)"
done
