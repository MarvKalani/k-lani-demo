#!/usr/bin/env bash
set -euo pipefail

: "${K_LANI_SERVER_BIN:=/usr/local/bin/k-lani-server}"
: "${K_LANI_HOLIDAY_BIN:=/usr/local/bin/real_world_booking_bench}"
: "${K_LANI_ADDR:=127.0.0.1:7700}"
: "${K_LANI_DATA_DIR:=/data}"
: "${K_LANI_REPORT_DIR:=/reports}"
: "${K_LANI_TABLE:=holiday_rooms}"
: "${K_LANI_HOLIDAY_HOTELS:=20}"
: "${K_LANI_HOLIDAY_ROOMS_PER_HOTEL:=50}"
: "${K_LANI_HOLIDAY_SESSIONS:=1000}"
: "${K_LANI_HOLIDAY_WORKERS:=16}"
: "${K_LANI_HOLIDAY_PRICE_CEILING:=1000}"

SERVER_CONFIG="$K_LANI_REPORT_DIR/k-lani-holiday-server.toml"
SERVER_LOG="$K_LANI_REPORT_DIR/holiday-server.log"
RAW_LOG="$K_LANI_REPORT_DIR/holiday-rush.raw.log"

fail() {
    echo "[k-lani-holiday] ERROR: $*" >&2
    exit 1
}

require_executable() {
    local path=$1
    [[ -x "$path" ]] || fail "missing executable: $path"
}

write_server_config() {
    local bind=${K_LANI_ADDR%:*}
    local port=${K_LANI_ADDR##*:}
    cat >"$SERVER_CONFIG" <<EOF
bind_address = "$bind"
port = $port
data_dir = "$K_LANI_DATA_DIR"
auth_method = "none"
lock_timeout_secs = 300
wal_checkpoint_bytes = 0
server_write_coalesce_window_micros = 50
server_write_coalesce_max_ops = 256
server_write_coalesce_max_bytes = 65536
server_write_mailbox_capacity = 65536
max_response_rows = 5000
max_response_bytes = 16777216
max_frame_size_bytes = 16777216
session_idle_timeout_secs = 300
stream_idle_timeout_secs = 300
data_preallocation_rows = 4096
server_write_autotune = false
log_level = "info"
max_connections = 256
web_enabled = false
parallel_scan_workers = 4
parallel_scan_min_rows = 1000
EOF
}

wait_for_port() {
    local index
    for index in $(seq 1 200); do
        if (: </dev/tcp/${K_LANI_ADDR%:*}/${K_LANI_ADDR##*:}) 2>/dev/null; then
            return 0
        fi
        sleep 0.05
    done
    return 1
}

main() {
    require_executable "$K_LANI_SERVER_BIN"
    require_executable "$K_LANI_HOLIDAY_BIN"
    mkdir -p "$K_LANI_DATA_DIR" "$K_LANI_REPORT_DIR"
    : >"$RAW_LOG"
    write_server_config

    echo "[k-lani-holiday] initializing Holiday Rush table"
    "$K_LANI_HOLIDAY_BIN" --init-only \
        --data-dir "$K_LANI_DATA_DIR" \
        --table "$K_LANI_TABLE" \
        --hotels "$K_LANI_HOLIDAY_HOTELS" \
        --rooms-per-hotel "$K_LANI_HOLIDAY_ROOMS_PER_HOTEL" | tee -a "$RAW_LOG"

    echo "[k-lani-holiday] starting k-lani server on $K_LANI_ADDR"
    "$K_LANI_SERVER_BIN" "$SERVER_CONFIG" >"$SERVER_LOG" 2>&1 &
    local server_pid=$!
    trap "kill $server_pid 2>/dev/null || true; wait $server_pid 2>/dev/null || true" EXIT
    wait_for_port || {
        cat "$SERVER_LOG" >&2 || true
        fail "server did not open $K_LANI_ADDR"
    }

    echo "[k-lani-holiday] loading room fixture"
    "$K_LANI_HOLIDAY_BIN" --load-fixture \
        --addr "$K_LANI_ADDR" \
        --data-dir "$K_LANI_DATA_DIR" \
        --table "$K_LANI_TABLE" \
        --hotels "$K_LANI_HOLIDAY_HOTELS" \
        --rooms-per-hotel "$K_LANI_HOLIDAY_ROOMS_PER_HOTEL" | tee -a "$RAW_LOG"

    echo "[k-lani-holiday] running sessions=$K_LANI_HOLIDAY_SESSIONS workers=$K_LANI_HOLIDAY_WORKERS"
    "$K_LANI_HOLIDAY_BIN" --run \
        --addr "$K_LANI_ADDR" \
        --data-dir "$K_LANI_DATA_DIR" \
        --table "$K_LANI_TABLE" \
        --hotels "$K_LANI_HOLIDAY_HOTELS" \
        --rooms-per-hotel "$K_LANI_HOLIDAY_ROOMS_PER_HOTEL" \
        --sessions "$K_LANI_HOLIDAY_SESSIONS" \
        --workers "$K_LANI_HOLIDAY_WORKERS" \
        --price-ceiling "$K_LANI_HOLIDAY_PRICE_CEILING" | tee -a "$RAW_LOG"

    grep -q "holiday_rush_done" "$RAW_LOG" || fail "benchmark finished without holiday_rush_done invariant line"
    echo "[k-lani-holiday] raw log: $RAW_LOG"
    echo "[k-lani-holiday] server log: $SERVER_LOG"
}

main "$@"