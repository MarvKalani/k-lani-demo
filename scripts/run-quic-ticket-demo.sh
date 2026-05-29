#!/usr/bin/env bash
set -euo pipefail

: "${K_LANI_DATA_DIR:=/data}"
: "${K_LANI_REPORT_DIR:=/reports}"
: "${K_LANI_QUIC_ADDR:=0.0.0.0:7701}"
: "${K_LANI_QUIC_URL:=https://127.0.0.1:7701/webtransport}"
: "${K_LANI_QUIC_PATH:=/webtransport}"
: "${K_LANI_USERS:=1000000}"
: "${K_LANI_WORKERS:=1024}"
: "${K_LANI_TABLE:=concert_seats}"
: "${K_LANI_RESET_DATA:=1}"
: "${K_LANI_QUIC_SERVER_BIN:=/usr/local/bin/k-lani-quic-server}"
: "${K_LANI_HERD_BIN:=/usr/local/bin/thundering_herd_concert_bench}"

source /usr/local/share/k-lani-demo/scripts/preview-guard.sh

SERVER_LOG="$K_LANI_REPORT_DIR/quic-server.log"
RAW_LOG="$K_LANI_REPORT_DIR/quic-ticket-demo.raw.log"
HOST_LOG="$K_LANI_REPORT_DIR/quic-host.txt"

fail() {
    echo "[k-lani-quic-demo] ERROR: $*" >&2
    exit 1
}

require_executable() {
    local path=$1
    [[ -x "$path" ]] || fail "required executable is missing: $path"
}

cleanup() {
    if [[ "${SERVER_PID:-}" != "" ]] && kill -0 "$SERVER_PID" 2>/dev/null; then
        kill "$SERVER_PID" 2>/dev/null || true
        wait "$SERVER_PID" 2>/dev/null || true
    fi
}
trap cleanup EXIT

wait_for_quic_ready() {
    local deadline=$((SECONDS + 30))
    while (( SECONDS < deadline )); do
        if grep -q "k_lani_quic_server_ready" "$SERVER_LOG" 2>/dev/null; then
            return 0
        fi
        sleep 1
    done
    return 1
}

write_host_log() {
    {
        echo "date=$(date -Is)"
        echo "uname=$(uname -a)"
        echo "transport=quic"
        echo "quic_addr=$K_LANI_QUIC_ADDR"
        echo "quic_url=$K_LANI_QUIC_URL"
        echo "users=$K_LANI_USERS"
        echo "workers=$K_LANI_WORKERS"
        echo "table=$K_LANI_TABLE"
        echo "binary_checksums="
        sha256sum "$K_LANI_QUIC_SERVER_BIN" "$K_LANI_HERD_BIN"
        echo "cpu="
        lscpu 2>/dev/null || true
        echo "memory="
        free -h 2>/dev/null || true
    } >"$HOST_LOG"
}

main() {
    require_executable "$K_LANI_QUIC_SERVER_BIN"
    require_executable "$K_LANI_HERD_BIN"
    mkdir -p "$K_LANI_DATA_DIR" "$K_LANI_REPORT_DIR"
    enforce_preview_date
    enforce_table_limit "$K_LANI_DATA_DIR"
    write_preview_manifest "$K_LANI_REPORT_DIR" "quic-ticket-horde"

    if [[ "$K_LANI_RESET_DATA" == "1" ]]; then
        case "$K_LANI_DATA_DIR" in
            /data|/data/*) rm -rf "$K_LANI_DATA_DIR"/* ;;
            *) fail "refusing to reset data outside /data: $K_LANI_DATA_DIR" ;;
        esac
    fi

    write_host_log

    echo "[k-lani-quic-demo] initializing ticket table"
    "$K_LANI_HERD_BIN" --init-only --data-dir "$K_LANI_DATA_DIR" --table "$K_LANI_TABLE"
    enforce_table_limit "$K_LANI_DATA_DIR"

    echo "[k-lani-quic-demo] starting native QUIC server on $K_LANI_QUIC_ADDR path=$K_LANI_QUIC_PATH"
    K_LANI_QUIC_DATA_DIR="$K_LANI_DATA_DIR" \
        K_LANI_QUIC_BIND="$K_LANI_QUIC_ADDR" \
        K_LANI_QUIC_PATH="$K_LANI_QUIC_PATH" \
        "$K_LANI_QUIC_SERVER_BIN" >"$SERVER_LOG" 2>&1 &
    SERVER_PID=$!
    wait_for_quic_ready || {
        cat "$SERVER_LOG" >&2 || true
        fail "QUIC server did not become ready on $K_LANI_QUIC_ADDR"
    }

    echo "[k-lani-quic-demo] loading 10k-seat fixture over QUIC"
    "$K_LANI_HERD_BIN" --load-fixture --transport quic --quic-url "$K_LANI_QUIC_URL" \
        --table "$K_LANI_TABLE" --data-dir "$K_LANI_DATA_DIR" | tee "$RAW_LOG"

    echo "[k-lani-quic-demo] running ticket storm over QUIC users=$K_LANI_USERS workers=$K_LANI_WORKERS"
    "$K_LANI_HERD_BIN" --run --transport quic --quic-url "$K_LANI_QUIC_URL" \
        --table "$K_LANI_TABLE" --users "$K_LANI_USERS" --workers "$K_LANI_WORKERS" \
        --data-dir "$K_LANI_DATA_DIR" | tee -a "$RAW_LOG"

    if ! grep -q "thundering_herd_done" "$RAW_LOG"; then
        fail "benchmark finished without thundering_herd_done invariant line"
    fi
    enforce_table_limit "$K_LANI_DATA_DIR"

    echo "[k-lani-quic-demo] raw log: $RAW_LOG"
    echo "[k-lani-quic-demo] host metadata: $HOST_LOG"
    echo "[k-lani-quic-demo] server log: $SERVER_LOG"
}

main "$@"