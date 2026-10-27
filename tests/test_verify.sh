#!/bin/bash
# Tests für verify_snapshot aus backup/run-backup.sh mit einem gefälschten restic.
#   bash tests/test_verify.sh
set -u
HERE=$(cd "$(dirname "$0")/.." && pwd)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin"
# Fake restic: Größe des Dumps aus $FAKE_SIZE (leer = kein Dump), Trailer aus $FAKE_TRAILER, check-Exit aus $FAKE_CHECK
cat > "$T/bin/restic" <<'SH'
#!/bin/bash
case "$1" in
  ls)    [ -n "${FAKE_SIZE:-}" ] && echo "-rw-r--r--     0     0 ${FAKE_SIZE} 2026-10-27 03:15:02 /work/erp.example.org-database.sql" ;;
  dump)  printf 'INSERT ...;\n%s\n' "${FAKE_TRAILER:-}" ;;
  check) exit "${FAKE_CHECK:-0}" ;;
esac
SH
chmod +x "$T/bin/restic"
export PATH="$T/bin:$PATH"
eval "$(sed -n '/^verify_snapshot()/,/^}/p' "$HERE/backup/run-backup.sh")"
log() { :; }
fail() { FAILED_STEP="$1"; }
SITE=erp.example.org WORK=/work
fails=0
check() { if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; fails=$((fails+1)); fi; }
run() { FAILED_STEP=""; verify_snapshot test; }

FAKE_SIZE=5000000 FAKE_TRAILER='-- Dump completed on 2026-10-27  3:15:01' run
check "complete dump passes" '[ $? -eq 0 ] && [ -z "$FAILED_STEP" ]'

FAKE_SIZE= run
check "missing dump fails" '[ "$FAILED_STEP" = "Prüfung (test): kein Datenbank-Dump im neuesten Snapshot" ]'

FAKE_SIZE=1000 FAKE_TRAILER='-- Dump completed' run
check "tiny dump fails" '[[ "$FAILED_STEP" == *"zu klein"* ]]'

FAKE_SIZE=5000000 FAKE_TRAILER='' run
check "truncated dump fails" '[[ "$FAILED_STEP" == *"unvollständig"* ]]'

FAKE_SIZE=5000000 FAKE_TRAILER='-- Dump completed' FAKE_CHECK=1 run
check "repo check failure fails" '[[ "$FAILED_STEP" == *"restic check"* ]]'

[ "$fails" -eq 0 ] && echo "all passed" || { echo "$fails failed"; exit 1; }
