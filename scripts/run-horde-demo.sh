#!/usr/bin/env bash
set -euo pipefail

: "${K_LANI_HORDE_HTTP_ADDR:=0.0.0.0:8081}"
: "${K_LANI_REPORT_DIR:=/reports}"
: "${K_LANI_SITE_DIR:=/demo/site}"

INDEX_HTML="$K_LANI_REPORT_DIR/index.html"

/usr/local/share/k-lani-demo/scripts/run-ticket-demo.sh

if [[ ! -f "$K_LANI_REPORT_DIR/horde-dashboard.html" ]]; then
    echo "[k-lani-horde-demo] ERROR: missing horde-dashboard.html" >&2
    exit 1
fi

cp "$K_LANI_REPORT_DIR/horde-dashboard.html" "$INDEX_HTML"
cp "$K_LANI_SITE_DIR/impressum.html" "$K_LANI_REPORT_DIR/impressum.html"
cp "$K_LANI_SITE_DIR/datenschutz.html" "$K_LANI_REPORT_DIR/datenschutz.html"

echo "[k-lani-horde-demo] dashboard: http://127.0.0.1:${K_LANI_HORDE_HTTP_ADDR##*:}/horde-dashboard.html"
exec /bin/busybox httpd -f -p "$K_LANI_HORDE_HTTP_ADDR" -h "$K_LANI_REPORT_DIR"