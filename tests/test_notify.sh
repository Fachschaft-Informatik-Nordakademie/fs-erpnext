#!/bin/bash
# Tests fuer backup/notify.sh mit einem gefaelschten curl (nichts verlaesst den Rechner).
#   bash tests/test_notify.sh
set -u
HERE=$(cd "$(dirname "$0")/.." && pwd)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin"
# Fake curl: protokolliert URL + Body; Antwortcode aus $FAKE_CODE_<n> bzw. FAKE_CODE (Default 200)
cat > "$T/bin/curl" <<'SH'
#!/bin/bash
n=$(( $(cat "$CALLS" 2>/dev/null | wc -l) + 1 ))
url="${@: -1}"; body=""
while [ $# -gt 0 ]; do [ "$1" = "-d" ] && body="$2"; shift; done
printf '%s\t%s\n' "$url" "$(printf '%s' "$body" | tr '\n' ' ')" >> "$CALLS"
v="FAKE_CODE_$n"; echo -n "${!v:-${FAKE_CODE:-200}}"
SH
chmod +x "$T/bin/curl"
export PATH="$T/bin:$PATH" CALLS="$T/calls" SITE=erp.example.org HOSTNAME=c1
fails=0
check() { if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; fails=$((fails+1)); fi; }
run() { rm -f "$CALLS"; ( log() { :; }; source "$HERE/backup/notify.sh"; notify "$@" ); }

# 1. Fehlschlag geht an den Alerts-Manager (critical, firing), nicht direkt an Discord
export BACKUP_ALERT_URL=http://am/relay/alert/s BACKUP_WEBHOOK_URL=https://discord/webhook
unset BACKUP_ALERT_SOURCE BACKUP_ALERT_KEY
run 0 mariadb-dump
check "failure -> manager only" '[ "$(wc -l < "$CALLS")" = 1 ] && grep -q "^http://am/relay/alert/s" "$CALLS"'
check "failure payload" 'grep -q "\"state\": \"firing\"" "$CALLS" && grep -q "\"level\": \"critical\"" "$CALLS" && grep -q "mariadb-dump" "$CALLS"'
check "default source/key" 'grep -q "\"source\": \"erpnext\"" "$CALLS" && grep -q "\"key\": \"backup\"" "$CALLS"'

# 2. Erfolg meldet resolved (entfernt die offene Discord-Nachricht)
run 1 ""
check "success -> resolved" 'grep -q "\"state\": \"resolved\"" "$CALLS" && [ "$(wc -l < "$CALLS")" = 1 ]'

# 3. Gleicher Key wie der infrastructure-scripts-Job: eine Nachricht statt zwei
export BACKUP_ALERT_SOURCE=infrastructure-scripts BACKUP_ALERT_KEY=job:erpnext-backup
run 0 restic
check "configurable key" 'grep -q "\"source\": \"infrastructure-scripts\"" "$CALLS" && grep -q "\"key\": \"job:erpnext-backup\"" "$CALLS"'

# 4. Fail open: Manager nicht erreichbar -> direkter Discord-Webhook
export FAKE_CODE_1=000
run 0 restic
check "manager down -> discord fallback" '[ "$(wc -l < "$CALLS")" = 2 ] && sed -n 2p "$CALLS" | grep -q "^https://discord/webhook"'
unset FAKE_CODE_1

# 5. Ohne Manager-URL: altes Verhalten (direkt Discord bei Fehlschlag, nichts bei Erfolg)
unset BACKUP_ALERT_URL
run 0 restic
check "legacy webhook on failure" 'grep -q "^https://discord/webhook" "$CALLS" && grep -q "@here" "$CALLS"'
run 1 ""
check "legacy: nothing on success" '[ ! -s "$CALLS" ]'

# 6. Anfuehrungszeichen im Schritt zerstoeren das JSON nicht
export BACKUP_ALERT_URL=http://am/relay/alert/s
run 0 'step "x" \y'
check "json escaping" 'cut -f2 "$CALLS" | python3 -c "import json,sys; json.loads(sys.stdin.read())"'

[ "$fails" = 0 ] && echo "all passed" || { echo "$fails failed"; exit 1; }
