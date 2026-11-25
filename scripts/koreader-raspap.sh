#!/bin/sh

KOREADER_DIR="${KOREADER_DIR:-/mnt/us/koreader}"
if [ ! -x "$KOREADER_DIR/koreader.sh" ]; then
    printf '%s\n' "KOReader launcher not found or not executable: $KOREADER_DIR/koreader.sh" >&2
    exit 1
fi
if [ ! -f "$KOREADER_DIR/plugins/raspapmanager.koplugin/main.lua" ]; then
    printf '%s\n' "Install and enable raspapmanager.koplugin in $KOREADER_DIR/plugins first." >&2
    exit 1
fi

RASPAP_STATUS_ON_START=1
export KOREADER_DIR RASPAP_STATUS_ON_START
exec "$KOREADER_DIR/koreader.sh" "$@"
