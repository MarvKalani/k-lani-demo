#!/usr/bin/env bash
set -euo pipefail

: "${K_LANI_DEMO_MODE:=ticket}"

case "$K_LANI_DEMO_MODE" in
    landing)
        exec /usr/local/share/k-lani-demo/scripts/run-landing-demo.sh "$@"
        ;;
    ticket)
        exec /usr/local/share/k-lani-demo/scripts/run-ticket-demo.sh "$@"
        ;;
    quic-ticket)
        exec /usr/local/share/k-lani-demo/scripts/run-quic-ticket-demo.sh "$@"
        ;;
    horde)
        exec /usr/local/share/k-lani-demo/scripts/run-horde-demo.sh "$@"
        ;;
    hft)
        exec /usr/local/share/k-lani-demo/scripts/run-hft-demo.sh "$@"
        ;;
    *)
        echo "[k-lani-demo] ERROR: unknown K_LANI_DEMO_MODE=$K_LANI_DEMO_MODE" >&2
        echo "[k-lani-demo] valid modes: landing, ticket, quic-ticket, horde, hft" >&2
        exit 1
        ;;
esac