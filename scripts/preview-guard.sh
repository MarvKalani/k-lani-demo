#!/usr/bin/env bash

: "${K_LANI_PREVIEW_GUARD:=1}"
: "${K_LANI_PREVIEW_EXPIRES_ON:=2026-08-29}"
: "${K_LANI_PREVIEW_MAX_TABLES:=10}"

preview_fail() {
    echo "[k-lani-preview] ERROR: $*" >&2
    exit 1
}

enforce_preview_date() {
    [[ "$K_LANI_PREVIEW_GUARD" == "1" ]] || return 0
    local expiry_epoch
    expiry_epoch=$(date -u -d "$K_LANI_PREVIEW_EXPIRES_ON 23:59:59" +%s 2>/dev/null) \
        || preview_fail "invalid K_LANI_PREVIEW_EXPIRES_ON=$K_LANI_PREVIEW_EXPIRES_ON"
    local now_epoch
    now_epoch=$(date -u +%s)
    if (( now_epoch > expiry_epoch )); then
        preview_fail "preview expired on $K_LANI_PREVIEW_EXPIRES_ON"
    fi
}

table_count() {
    local data_dir=$1
    if [[ ! -d "$data_dir" ]]; then
        echo 0
        return 0
    fi
    find "$data_dir" -type f -name '*.mkx' | wc -l | tr -d ' '
}

data_dir_bytes() {
    local data_dir=$1
    if [[ ! -d "$data_dir" ]]; then
        echo 0
        return 0
    fi
    find "$data_dir" -type f -printf '%s\n' | awk '{sum += $1} END {print sum + 0}'
}

enforce_table_limit() {
    [[ "$K_LANI_PREVIEW_GUARD" == "1" ]] || return 0
    local data_dir=$1
    local count
    count=$(table_count "$data_dir")
    if (( count > K_LANI_PREVIEW_MAX_TABLES )); then
        preview_fail "table limit exceeded: $count > $K_LANI_PREVIEW_MAX_TABLES"
    fi
}

enforce_data_limit() {
    [[ "$K_LANI_PREVIEW_GUARD" == "1" ]] || return 0
    local data_dir=$1
    local max_bytes=$2
    local label=${3:-data directory}

    [[ "$max_bytes" =~ ^[0-9]+$ ]] || preview_fail "invalid byte limit for $label: $max_bytes"

    local bytes
    bytes=$(data_dir_bytes "$data_dir")
    if (( bytes > max_bytes )); then
        preview_fail "$label size limit exceeded: $bytes > $max_bytes bytes"
    fi
}

write_preview_manifest() {
    local report_dir=$1
    local demo_name=$2
    mkdir -p "$report_dir"
    {
        echo "demo=$demo_name"
        echo "generated_at=$(date -Is)"
        echo "preview_guard=$K_LANI_PREVIEW_GUARD"
        echo "expires_on=$K_LANI_PREVIEW_EXPIRES_ON"
        echo "max_tables=$K_LANI_PREVIEW_MAX_TABLES"
        echo "note=This is a binary preview guard, not a substitute for a compiled license system."
    } >"$report_dir/preview-guard.txt"
}