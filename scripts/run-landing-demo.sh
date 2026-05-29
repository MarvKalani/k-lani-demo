#!/usr/bin/env bash
set -euo pipefail

: "${K_LANI_LANDING_HTTP_ADDR:=0.0.0.0:8082}"
: "${K_LANI_REPORT_DIR:=/reports}"

source /usr/local/share/k-lani-demo/scripts/preview-guard.sh

main() {
    mkdir -p "$K_LANI_REPORT_DIR"
    enforce_preview_date
    write_preview_manifest "$K_LANI_REPORT_DIR" "landing"

    echo "[k-lani-landing] browser: http://127.0.0.1:${K_LANI_LANDING_HTTP_ADDR##*:}/"
    exec /bin/busybox httpd -f -p "$K_LANI_LANDING_HTTP_ADDR" -h /demo/site
}

main "$@"