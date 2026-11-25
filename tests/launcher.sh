#!/bin/sh
set -eu

test_dir="$(mktemp -d)"
app="$test_dir/KOReader with spaces"
plugin="$app/plugins/raspapmanager.koplugin"
cleanup() {
    rm -f "$test_dir/output" "$app/koreader.sh" "$plugin/main.lua"
    rmdir "$plugin" "$app/plugins" "$app" "$test_dir"
}
mkdir -p "$plugin"
trap cleanup EXIT

if KOREADER_DIR="$app" sh scripts/koreader-raspap.sh >"$test_dir/output" 2>&1; then
    printf '%s\n' "FAIL missing launcher accepted" >&2
    exit 1
fi
grep -q 'KOReader launcher not found' "$test_dir/output"

cat >"$app/koreader.sh" <<'LAUNCHER'
#!/bin/sh
printf '%s\n' "startup=$RASPAP_STATUS_ON_START" "directory=$KOREADER_DIR"
printf 'arg=<%s>\n' "$@"
exit "${LAUNCH_EXIT:-0}"
LAUNCHER
chmod +x "$app/koreader.sh"
if KOREADER_DIR="$app" sh scripts/koreader-raspap.sh >"$test_dir/output" 2>&1; then
    printf '%s\n' "FAIL missing plugin accepted" >&2
    exit 1
fi
grep -q 'Install and enable' "$test_dir/output"

: >"$plugin/main.lua"
RASPAP_STATUS_ON_START=0 KOREADER_DIR="$app" \
    sh scripts/koreader-raspap.sh --kual "folder with spaces" >"$test_dir/output"
grep -qx 'startup=1' "$test_dir/output"
grep -qxF "directory=$app" "$test_dir/output"
grep -qxF 'arg=<--kual>' "$test_dir/output"
grep -qxF 'arg=<folder with spaces>' "$test_dir/output"

status=0
LAUNCH_EXIT=7 KOREADER_DIR="$app" sh scripts/koreader-raspap.sh >"$test_dir/output" || status=$?
[ "$status" -eq 7 ]
printf '%s\n' "PASS launcher validation, environment, argument forwarding and exit status"
