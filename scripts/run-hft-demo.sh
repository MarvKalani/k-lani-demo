#!/usr/bin/env bash
set -euo pipefail

: "${K_LANI_HFT_BIN:=/usr/local/bin/trading_workstation}"
: "${K_LANI_HFT_SEED_DIR:=/demo/hft-data}"
: "${K_LANI_HFT_DATA_DIR:=/data/hft}"
: "${K_LANI_HFT_HTTP_ADDR:=0.0.0.0:8080}"
: "${K_LANI_HFT_QUIC_ADDR:=0.0.0.0:7701}"
: "${K_LANI_TICK_INTERVAL_MS:=1}"
: "${K_LANI_RESET_DATA:=1}"
: "${K_LANI_HFT_USE_SEED:=0}"
: "${K_LANI_HFT_MAX_DATA_BYTES:=10485760}"
: "${K_LANI_REPORT_DIR:=/reports}"

source /usr/local/share/k-lani-demo/scripts/preview-guard.sh

fail() {
    echo "[k-lani-hft-demo] ERROR: $*" >&2
    exit 1
}

require_executable() {
    local path=$1
    [[ -x "$path" ]] || fail "required executable is missing: $path"
}

seed_hft_data() {
    mkdir -p "$K_LANI_HFT_DATA_DIR"
    if [[ "$K_LANI_RESET_DATA" == "1" ]]; then
        case "$K_LANI_HFT_DATA_DIR" in
            /data|/data/*) rm -rf "$K_LANI_HFT_DATA_DIR"/* ;;
            *) fail "refusing to reset data outside /data: $K_LANI_HFT_DATA_DIR" ;;
        esac
    fi
    if [[ "$K_LANI_HFT_USE_SEED" != "1" ]]; then
        echo "[k-lani-hft-demo] seed import disabled; starting with fresh live data"
        return 0
    fi
    if [[ -f "$K_LANI_HFT_SEED_DIR/hft_ticks.mkx" ]]; then
        enforce_data_limit "$K_LANI_HFT_SEED_DIR" "$K_LANI_HFT_MAX_DATA_BYTES" "hft seed data"
        cp "$K_LANI_HFT_SEED_DIR"/*.mkx "$K_LANI_HFT_DATA_DIR"/
        cp "$K_LANI_HFT_SEED_DIR"/*.mkpid "$K_LANI_HFT_DATA_DIR"/
    else
        echo "[k-lani-hft-demo] no seed tables found in $K_LANI_HFT_SEED_DIR; starting with generated data"
    fi
}

main() {
    require_executable "$K_LANI_HFT_BIN"
    enforce_preview_date
    seed_hft_data
    enforce_table_limit "$K_LANI_HFT_DATA_DIR"
    enforce_data_limit "$K_LANI_HFT_DATA_DIR" "$K_LANI_HFT_MAX_DATA_BYTES" "hft runtime data"
    write_preview_manifest "$K_LANI_REPORT_DIR" "hft-workstation"
    printf 'max_hft_data_bytes=%s\n' "$K_LANI_HFT_MAX_DATA_BYTES" >>"$K_LANI_REPORT_DIR/preview-guard.txt"

    export K_LANI_DATA_DIR="$K_LANI_HFT_DATA_DIR"
    export K_LANI_ADAPTER_HTTP_ADDR="$K_LANI_HFT_HTTP_ADDR"
    export K_LANI_ADAPTER_QUIC_ADDR="$K_LANI_HFT_QUIC_ADDR"
    export K_LANI_TICK_INTERVAL_MS

    echo "[k-lani-hft-demo] starting web workstation"
    echo "[k-lani-hft-demo] browser: http://127.0.0.1:${K_LANI_HFT_HTTP_ADDR##*:}/"
    echo "[k-lani-hft-demo] quic:    udp/${K_LANI_HFT_QUIC_ADDR##*:}"
    echo "[k-lani-hft-demo] data cap: ${K_LANI_HFT_MAX_DATA_BYTES} bytes"
    exec "$K_LANI_HFT_BIN"
}

main "$@"