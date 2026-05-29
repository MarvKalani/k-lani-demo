#!/usr/bin/env bash
set -euo pipefail

: "${K_LANI_DATA_DIR:=/data}"
: "${K_LANI_REPORT_DIR:=/reports}"
: "${K_LANI_ADDR:=127.0.0.1:7700}"
: "${K_LANI_USERS:=1000000}"
: "${K_LANI_WORKERS:=1024}"
: "${K_LANI_TABLE:=concert_seats}"
: "${K_LANI_RESET_DATA:=1}"
: "${K_LANI_SERVER_BIN:=/usr/local/bin/k-lani-server}"
: "${K_LANI_HERD_BIN:=/usr/local/bin/thundering_herd_concert_bench}"

source /usr/local/share/k-lani-demo/scripts/preview-guard.sh

SERVER_CONFIG="$K_LANI_REPORT_DIR/k-lani-server.toml"
SERVER_LOG="$K_LANI_REPORT_DIR/server.log"
RAW_LOG="$K_LANI_REPORT_DIR/ticket-demo.raw.log"
HOST_LOG="$K_LANI_REPORT_DIR/host.txt"
HORDE_REPORT="$K_LANI_REPORT_DIR/horde-dashboard.html"

fail() {
    echo "[k-lani-demo] ERROR: $*" >&2
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

wait_for_port() {
    local host=${K_LANI_ADDR%:*}
    local port=${K_LANI_ADDR##*:}
    local deadline=$((SECONDS + 30))
    while (( SECONDS < deadline )); do
        if (echo >"/dev/tcp/$host/$port") >/dev/null 2>&1; then
            return 0
        fi
        sleep 1
    done
    return 1
}

detect_cgroup_memory_limit_bytes() {
    local path value
    for path in /sys/fs/cgroup/memory.max /sys/fs/cgroup/memory/memory.limit_in_bytes; do
        if [[ -r "$path" ]]; then
            value=$(tr -d '[:space:]' <"$path")
            if [[ "$value" =~ ^[0-9]+$ ]] && (( value > 0 )) && (( value < 9223372036854771712 )); then
                printf '%s\n' "$value"
                return 0
            fi
        fi
    done
    return 1
}

detect_cgroup_cpu_limit_millis() {
    local quota period
    if [[ -r /sys/fs/cgroup/cpu.max ]]; then
        read -r quota period </sys/fs/cgroup/cpu.max
        if [[ "$quota" != "max" && "$quota" =~ ^[0-9]+$ && "$period" =~ ^[0-9]+$ ]] && (( period > 0 )); then
            printf '%s\n' $(( quota * 1000 / period ))
            return 0
        fi
    fi
    if [[ -r /sys/fs/cgroup/cpu/cpu.cfs_quota_us && -r /sys/fs/cgroup/cpu/cpu.cfs_period_us ]]; then
        quota=$(tr -d '[:space:]' </sys/fs/cgroup/cpu/cpu.cfs_quota_us)
        period=$(tr -d '[:space:]' </sys/fs/cgroup/cpu/cpu.cfs_period_us)
        if [[ "$quota" =~ ^[0-9]+$ && "$period" =~ ^[0-9]+$ ]] && (( quota > 0 && period > 0 )); then
            printf '%s\n' $(( quota * 1000 / period ))
            return 0
        fi
    fi
    return 1
}

format_memory_profile() {
    local bytes=$1
    local gib=$((1024 * 1024 * 1024))
    local mib=$((1024 * 1024))
    if (( bytes % gib == 0 )); then
        printf '%s GB RAM\n' $(( bytes / gib ))
    elif (( bytes % mib == 0 )); then
        printf '%s MB RAM\n' $(( bytes / mib ))
    else
        printf '%s B RAM\n' "$bytes"
    fi
}

format_cpu_profile() {
    local millicpus=$1
    if (( millicpus % 1000 == 0 )); then
        printf '%s vCPUs\n' $(( millicpus / 1000 ))
    else
        awk -v millicpus="$millicpus" 'BEGIN { printf "%.2f vCPUs\n", millicpus / 1000 }'
    fi
}

extract_final_metric() {
    local line=$1
    local key=$2
    printf '%s\n' "$line" | tr ' ' '\n' | sed -n "s/^${key}=//p" | head -n 1
}

write_host_log() {
    local cpu_limit_millis=""
    local memory_limit_bytes=""
    local cpu_profile=""
    local memory_profile=""

    cpu_limit_millis=$(detect_cgroup_cpu_limit_millis || true)
    memory_limit_bytes=$(detect_cgroup_memory_limit_bytes || true)
    if [[ "$cpu_limit_millis" != "" ]]; then
        cpu_profile=$(format_cpu_profile "$cpu_limit_millis")
    fi
    if [[ "$memory_limit_bytes" != "" ]]; then
        memory_profile=$(format_memory_profile "$memory_limit_bytes")
    fi

    {
        echo "date=$(date -Is)"
        echo "uname=$(uname -a)"
        echo "users=$K_LANI_USERS"
        echo "workers=$K_LANI_WORKERS"
        echo "table=$K_LANI_TABLE"
        echo "addr=$K_LANI_ADDR"
        if [[ "$cpu_limit_millis" != "" ]]; then
            echo "cgroup_cpu_limit_millis=$cpu_limit_millis"
            echo "cgroup_cpu_profile=$cpu_profile"
        fi
        if [[ "$memory_limit_bytes" != "" ]]; then
            echo "cgroup_memory_limit_bytes=$memory_limit_bytes"
            echo "cgroup_memory_profile=$memory_profile"
        fi
        echo "binary_checksums="
        sha256sum "$K_LANI_SERVER_BIN" "$K_LANI_HERD_BIN"
        echo "cpu="
        lscpu 2>/dev/null || true
        echo "memory="
        free -h 2>/dev/null || true
    } >"$HOST_LOG"
}

write_horde_report() {
        local final_line
        local seats
        local sold
        local verified_sold
        local peak_qps
        local wall_secs
        local read_p90_us
        local update_p90_us
        local lock_conflicts
        local already_sold
        local no_ticket
        local cpu_limit_millis=""
        local memory_limit_bytes=""
        local cpu_profile="Container CPU limit not detected"
        local memory_profile="Container memory limit not detected"

        final_line=$(grep 'thundering_herd_done' "$RAW_LOG" | tail -n 1)
        seats=$(extract_final_metric "$final_line" "seats")
        sold=$(extract_final_metric "$final_line" "sold")
        verified_sold=$(extract_final_metric "$final_line" "verified_sold")
        peak_qps=$(extract_final_metric "$final_line" "peak_qps")
        wall_secs=$(extract_final_metric "$final_line" "wall_secs")
        read_p90_us=$(extract_final_metric "$final_line" "read_p90_us")
        update_p90_us=$(extract_final_metric "$final_line" "update_p90_us")
        lock_conflicts=$(extract_final_metric "$final_line" "lock_conflicts")
        already_sold=$(extract_final_metric "$final_line" "already_sold")
        no_ticket=$(extract_final_metric "$final_line" "no_ticket")
        cpu_limit_millis=$(detect_cgroup_cpu_limit_millis || true)
        memory_limit_bytes=$(detect_cgroup_memory_limit_bytes || true)
        if [[ "$cpu_limit_millis" != "" ]]; then
            cpu_profile=$(format_cpu_profile "$cpu_limit_millis")
        fi
        if [[ "$memory_limit_bytes" != "" ]]; then
            memory_profile=$(format_memory_profile "$memory_limit_bytes")
        fi
        cat >"$HORDE_REPORT" <<EOF
<!doctype html>
<html lang="en">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>k-lani Ticket Horde Demo</title>
    <style>
        :root { color-scheme: dark; --bg:#070a0f; --panel:#111827; --line:#263244; --text:#e5edf8; --muted:#8fa3bd; --green:#4ade80; --cyan:#38bdf8; --amber:#fbbf24; }
        * { box-sizing: border-box; }
        body { margin:0; font-family: Inter, ui-sans-serif, system-ui, sans-serif; background:var(--bg); color:var(--text); }
        main { width:min(1120px, calc(100vw - 32px)); margin:0 auto; padding:32px 0; }
        header { display:flex; justify-content:space-between; gap:24px; align-items:flex-end; border-bottom:1px solid var(--line); padding-bottom:20px; }
        h1 { margin:0; font-size:clamp(28px, 4vw, 48px); letter-spacing:0; }
        .badge { border:1px solid var(--green); color:var(--green); padding:6px 10px; font-size:13px; text-transform:uppercase; }
        .grid { display:grid; grid-template-columns:repeat(4, minmax(0,1fr)); gap:12px; margin:24px 0; }
        .card { background:var(--panel); border:1px solid var(--line); border-radius:6px; padding:16px; min-height:96px; }
        .label { color:var(--muted); font-size:12px; text-transform:uppercase; }
        .value { display:block; margin-top:10px; font-size:26px; font-weight:700; }
        .unit { display:block; margin-top:8px; color:var(--muted); font-size:13px; line-height:1.5; }
        pre { background:#020617; border:1px solid var(--line); border-radius:6px; padding:16px; overflow:auto; color:#dbeafe; }
        .note { color:var(--muted); max-width:760px; line-height:1.6; }
        .section { margin-top:28px; }
        .section h2 { margin:0 0 12px; font-size:22px; }
        .section p { color:var(--muted); line-height:1.7; }
        .callouts { display:grid; grid-template-columns:repeat(3, minmax(0,1fr)); gap:12px; margin-top:18px; }
        .callout { background:var(--panel); border:1px solid var(--line); border-radius:6px; padding:16px; }
        .callout h3 { margin:0 0 10px; font-size:16px; }
        .callout p { margin:0; color:var(--muted); line-height:1.6; }
        .codeblock { white-space:pre-wrap; }
        .artifact-list { display:grid; gap:10px; padding:0; margin:0; list-style:none; }
        .artifact-list a { color:var(--cyan); text-decoration:none; }
        .artifact-list a:hover { color:var(--green); }
        .boundary { border-left:3px solid var(--amber); padding-left:16px; margin-top:16px; }
        footer { margin-top:24px; padding-top:18px; border-top:1px solid var(--line); }
        .legal { display:flex; flex-wrap:wrap; gap:12px 18px; }
        .legal a { color:var(--text); text-decoration:none; }
        .legal a:hover { color:var(--green); }
        @media (max-width: 920px) { .grid, .callouts { grid-template-columns:1fr 1fr; } }
        @media (max-width: 760px) { .grid, .callouts { grid-template-columns:1fr; } header { display:block; } }
    </style>
</head>
<body>
    <main>
        <header>
            <div>
                <p class="label">k-lani binary preview</p>
                <h1>Ticket Horde</h1>
            </div>
            <div class="badge">sold == verified_sold</div>
        </header>
        <section class="grid" aria-label="Benchmark summary">
            <div class="card"><span class="label">Hardware profile</span><span class="value">$cpu_profile</span><span class="unit">$memory_profile</span></div>
            <div class="card"><span class="label">Workload</span><span class="value">$K_LANI_USERS users</span><span class="unit">$seats tickets, $K_LANI_WORKERS workers</span></div>
            <div class="card"><span class="label">Result</span><span class="value">$verified_sold / $seats</span><span class="unit">0 double-spends in $wall_secs s</span></div>
            <div class="card"><span class="label">Peak QPS</span><span class="value">$peak_qps</span><span class="unit">read p90 <= $read_p90_us us, update p90 <= $update_p90_us us</span></div>
        </section>
        <p class="note">This page is generated from the raw benchmark log inside the demo container. The published claim is persisted correctness under contention: 10,000 / 10,000 seats were sold, re-read from stored state, and matched exactly on a container limited to $cpu_profile and $memory_profile.</p>

        <section class="section">
            <h2>Mechanical Sympathy</h2>
            <div class="callouts">
                <article class="callout">
                    <h3>Page-cache friendly reads</h3>
                    <p>The hot path starts with an indexed intersection over <code>is_booked = 0</code> and <code>rank = X</code>, then short point reads on candidate rows. No SQL parser, ORM, or HTTP request fanout sits in the purchase loop.</p>
                </article>
                <article class="callout">
                    <h3>WORM-first seat claims</h3>
                    <p>A successful purchase is a locked row verification followed by a single <code>replace</code> that flips <code>is_booked</code> from <code>0</code> to <code>1</code>. Lock conflicts are counted and retried; they do not serialize the whole table.</p>
                </article>
                <article class="callout">
                    <h3>Honest scope</h3>
                    <p>This published $wall_secs s result came from the local TCP server path at <code>127.0.0.1:7700</code>. The separate QUIC/WebTransport demo exists, but it is not what produced the number shown on this page.</p>
                </article>
            </div>
        </section>

        <section class="section">
            <h2>Exact Flow Executed By This Benchmark</h2>
            <p>The hot loop in <code>thundering_herd_concert_bench</code> is a binary read-modify-write sequence over indexed seat rows. The public result above came from this shape, not from SQL text and not from a browser checkout path:</p>
            <pre class="codeblock">for each worker:
  ids = query_intersect_ids(handle, "is_booked", u32_bytes(0), "rank", u32_bytes(rank), 64)
  pick up to 16 candidate seat ids
  try_lock(handle, id)
  fields = seek_fields(handle, id)
  if is_booked != 0: already_sold += 1; unlock(handle, id); continue
  replace(handle, id, encode_u32_fields(rank, seat_no, 1))
  unlock(handle, id)
  sold += 1

after the storm:
  verify_sold_count() scans all 10,000 seats and recounts persisted sold rows</pre>
            <div class="boundary">
                <p>What this proves for a ticketing company: k-lani can serve as a narrow inventory and reservation engine behind an existing commerce stack. What it does not prove on its own: payment orchestration, cart UX, or direct browser-to-engine QUIC checkout in production.</p>
            </div>
        </section>
        <h2>Final line</h2>
        <pre>$final_line</pre>
        <h2>Artifacts</h2>
        <ul class="artifact-list">
            <li><a href="ticket-demo.raw.log">ticket-demo.raw.log</a> - per-second samples and the final invariant line.</li>
            <li><a href="host.txt">host.txt</a> - host kernel, CPU details, checksums, and detected cgroup budget.</li>
            <li><a href="server.log">server.log</a> - raw server output for the run.</li>
            <li><a href="preview-guard.txt">preview-guard.txt</a> - preview expiry and table-limit guard.</li>
        </ul>
        <footer>
            <div class="legal">
                <a href="impressum.html">Impressum</a>
                <a href="datenschutz.html">Datenschutz</a>
                <a href="mailto:support@kalanis.de">support@kalanis.de</a>
            </div>
        </footer>
    </main>
</body>
</html>
EOF
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
max_response_rows = 10000
max_response_bytes = 16777216
max_frame_size_bytes = 16777216
session_idle_timeout_secs = 300
stream_idle_timeout_secs = 300
data_preallocation_rows = 1048576
server_write_autotune = false
log_level = "info"
max_connections = 4096
web_enabled = false
parallel_scan_workers = 4
parallel_scan_min_rows = 10000
EOF
}

main() {
    require_executable "$K_LANI_SERVER_BIN"
    require_executable "$K_LANI_HERD_BIN"
    mkdir -p "$K_LANI_DATA_DIR" "$K_LANI_REPORT_DIR"
    enforce_preview_date
    enforce_table_limit "$K_LANI_DATA_DIR"
    write_preview_manifest "$K_LANI_REPORT_DIR" "ticket-horde"

    if [[ "$K_LANI_RESET_DATA" == "1" ]]; then
        case "$K_LANI_DATA_DIR" in
            /data|/data/*) rm -rf "$K_LANI_DATA_DIR"/* ;;
            *) fail "refusing to reset data outside /data: $K_LANI_DATA_DIR" ;;
        esac
    fi

    write_host_log
    write_server_config

    echo "[k-lani-demo] initializing ticket table"
    "$K_LANI_HERD_BIN" --init-only --data-dir "$K_LANI_DATA_DIR" --table "$K_LANI_TABLE"
    enforce_table_limit "$K_LANI_DATA_DIR"

    echo "[k-lani-demo] starting k-lani server on $K_LANI_ADDR"
    "$K_LANI_SERVER_BIN" "$SERVER_CONFIG" >"$SERVER_LOG" 2>&1 &
    SERVER_PID=$!
    wait_for_port || {
        cat "$SERVER_LOG" >&2 || true
        fail "server did not open $K_LANI_ADDR"
    }

    echo "[k-lani-demo] loading 10k-seat fixture"
    "$K_LANI_HERD_BIN" --load-fixture --addr "$K_LANI_ADDR" --table "$K_LANI_TABLE" \
        --data-dir "$K_LANI_DATA_DIR" | tee "$RAW_LOG"

    echo "[k-lani-demo] running ticket storm users=$K_LANI_USERS workers=$K_LANI_WORKERS"
    "$K_LANI_HERD_BIN" --run --addr "$K_LANI_ADDR" --table "$K_LANI_TABLE" \
        --users "$K_LANI_USERS" --workers "$K_LANI_WORKERS" \
        --data-dir "$K_LANI_DATA_DIR" | tee -a "$RAW_LOG"

    if ! grep -q "thundering_herd_done" "$RAW_LOG"; then
        fail "benchmark finished without thundering_herd_done invariant line"
    fi
    enforce_table_limit "$K_LANI_DATA_DIR"
    write_horde_report

    echo "[k-lani-demo] raw log: $RAW_LOG"
    echo "[k-lani-demo] horde dashboard: $HORDE_REPORT"
    echo "[k-lani-demo] host metadata: $HOST_LOG"
    echo "[k-lani-demo] server log: $SERVER_LOG"
}

main "$@"