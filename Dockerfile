# Binary-only k-lani public demo image.
#
# Build this from publish/github-demo after copying release binaries into bin/:
#   docker build -t k-lani-demo:preview .

FROM debian:bookworm-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        bash \
        busybox-static \
        ca-certificates \
        coreutils \
        procps \
        tini \
    && rm -rf /var/lib/apt/lists/* \
    && groupadd --system --gid 10001 k-lani \
    && useradd --system --uid 10001 --gid 10001 --home-dir /nonexistent --shell /usr/sbin/nologin k-lani \
    && mkdir -p /data /reports /demo /demo/hft-data \
    && chown -R 10001:10001 /data /reports /demo

WORKDIR /demo

COPY bin/ /usr/local/bin/
COPY site/ /demo/site/
COPY scripts/ /usr/local/share/k-lani-demo/scripts/

RUN chown -R 10001:10001 /demo/hft-data \
    && chown -R 10001:10001 /demo/site \
    && chmod 0555 /usr/local/share/k-lani-demo/scripts/*.sh \
    && find /usr/local/bin -type f -name 'k-lani*' -exec chmod 0555 {} + \
    && find /usr/local/bin -type f -name '*bench*' -exec chmod 0555 {} + \
    && find /usr/local/bin -type f -name 'trading_workstation' -exec chmod 0555 {} +

ENV K_LANI_DATA_DIR=/data \
    K_LANI_REPORT_DIR=/reports \
    K_LANI_ADDR=127.0.0.1:7700 \
    K_LANI_USERS=1000000 \
    K_LANI_WORKERS=1024 \
    K_LANI_TABLE=concert_seats \
    K_LANI_DEMO_MODE=ticket \
    K_LANI_PREVIEW_EXPIRES_ON=2026-08-29 \
    K_LANI_PREVIEW_MAX_TABLES=10 \
    K_LANI_LANDING_HTTP_ADDR=0.0.0.0:8082 \
    K_LANI_QUIC_ADDR=0.0.0.0:7701 \
    K_LANI_QUIC_URL=https://127.0.0.1:7701/webtransport \
    K_LANI_QUIC_PATH=/webtransport \
    K_LANI_HORDE_HTTP_ADDR=0.0.0.0:8081 \
    K_LANI_HFT_HTTP_ADDR=0.0.0.0:8080 \
    K_LANI_HFT_QUIC_ADDR=0.0.0.0:7701 \
    K_LANI_HFT_MAX_DATA_BYTES=10485760 \
    K_LANI_HFT_SEED_DIR=/demo/hft-data

VOLUME ["/data", "/reports"]
EXPOSE 7700
EXPOSE 8080
EXPOSE 8081
EXPOSE 8082
EXPOSE 7701/udp

USER 10001:10001
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/share/k-lani-demo/scripts/demo-entrypoint.sh"]