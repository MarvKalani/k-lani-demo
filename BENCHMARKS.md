# Benchmark Reproduction

This preview repository ships the exact runtime scripts and published report
artifacts for the public ticketing benchmark. It also records the exact command
lines used for the comparative release reports.

## 1. What this preview repo can reproduce directly

The following benchmark modes are fully reproducible from this binary-only
preview repository:

- the TCP `Thundering Herd` ticket benchmark served by the `horde` container
- the one-shot native QUIC ticket benchmark served by `run-quic-ticket-demo.sh`
- the TCP `Holiday Rush` travel-room booking smoke served by `run-holiday-demo.sh`

The following assets are already inside this repo and are part of the released
benchmark boundary:

- `docker-compose.yml`
- `scripts/demo-entrypoint.sh`
- `scripts/run-ticket-demo.sh`
- `scripts/run-horde-demo.sh`
- `scripts/run-quic-ticket-demo.sh`
- `scripts/run-holiday-demo.sh`
- `reports/client-server-comparative-release-2026-05-29.md`
- `reports/embedded-core-comparative-release-2026-04-29.md`
- `reports/holiday-rush-smoke-2026-05-30.md`
- `reports/benchmark-host-2026-05-29.md`

## 2. Exact Thundering Herd setup

The published horde run is the local TCP path, not the QUIC path.

Exact container defaults from `docker-compose.yml`:

- `K_LANI_USERS=100000`
- `K_LANI_WORKERS=128`
- `K_LANI_TABLE=concert_seats`
- `K_LANI_HORDE_MEM_LIMIT=4g`
- `K_LANI_HORDE_CPUS=2.0`
- `K_LANI_ADDR=127.0.0.1:7700`

The `horde` service starts `scripts/run-horde-demo.sh`, which calls
`scripts/run-ticket-demo.sh`. That script:

1. writes a local server config into `/reports/k-lani-server.toml`
2. starts `k-lani-server`
3. runs `thundering_herd_concert_bench`
4. verifies sold seats from persisted state
5. writes `horde-dashboard.html`, `ticket-demo.raw.log`, `host.txt`, and
   `server.log`

To reproduce the published TCP run locally with the same shape:

```bash
git clone https://github.com/MarvKalani/k-lani-demo.git
cd k-lani-demo
K_LANI_USERS=100000 \
K_LANI_WORKERS=128 \
K_LANI_HORDE_MEM_LIMIT=4g \
K_LANI_HORDE_CPUS=2.0 \
docker compose up -d --build horde
docker compose logs -f horde
```

Optional validation commands:

```bash
docker compose config horde
curl http://127.0.0.1:8081/horde-dashboard.html
docker compose exec horde ls -1 /reports
docker compose exec horde cat /reports/ticket-demo.raw.log
docker compose exec horde cat /reports/host.txt
```

What this benchmark actually tests:

- indexed lookup of candidate seat ids by `is_booked=0` and `rank=X`
- per-row lock acquisition
- point read of the persisted row
- atomic `replace` from `is_booked=0` to `is_booked=1`
- post-run verification that sold rows persisted and no double-spend appeared

What it does not test:

- browser checkout latency
- payment flows
- public internet round-trips
- QUIC/WebTransport, unless you explicitly run the QUIC mode below

## 3. Optional QUIC ticket run

The preview repo also ships the separate native QUIC ticket runner:

```bash
docker build -t k-lani-demo:preview .
docker run --rm \
  -e K_LANI_DEMO_MODE=quic-ticket \
  -e K_LANI_USERS=100000 \
  -e K_LANI_WORKERS=128 \
  -p 7701:7701/udp \
  k-lani-demo:preview
```

That run uses `scripts/run-quic-ticket-demo.sh` and writes its own raw log and
host metadata into `/reports`. It is intentionally not the source of the public
`demo.k-lani.com` number.

## 4. Optional Holiday Rush travel-room run

The preview repo also ships the Holiday Rush travel-room booking smoke. It is a
tight inventory scenario: 1,000 booking sessions compete for exactly 1,000 room
rows and the benchmark recounts persisted booked rows after the run.

```bash
docker build -t k-lani-demo:preview .
docker run --rm \
  -e K_LANI_DEMO_MODE=holiday \
  -e K_LANI_HOLIDAY_HOTELS=20 \
  -e K_LANI_HOLIDAY_ROOMS_PER_HOTEL=50 \
  -e K_LANI_HOLIDAY_SESSIONS=1000 \
  -e K_LANI_HOLIDAY_WORKERS=16 \
  k-lani-demo:preview
```

Expected invariant shape:

```text
holiday_rush_done sessions=1000 rooms=1000 booked=1000 verified_booked=1000 ... failed_sessions=0 ...
```

The contention counters and wall time are scheduler-dependent; the fixed
invariant is `booked=1000`, `verified_booked=1000`, and `failed_sessions=0`.

The tracked smoke report is `reports/holiday-rush-smoke-2026-05-30.md`.

## 5. Exact comparative benchmark commands

The comparative reports in `reports/` were generated from the full source
workspace, not from this binary-only preview boundary. The commands below are
the exact reproduction commands used against the source workspace.

Embedded/core release comparison:

```bash
K_LANI_BENCH_PROFILE=release cargo +stable bench -p k-lani-bench --bench comparative
```

Client/server release comparison on the published `2026-05-29` host:

```bash
export PATH="$HOME/.cargo/bin:$PATH"
CARGO_CMD='cargo +stable' ./benchmark.sh --profile release --rows 100000 --lookups 100000 --reuse-k-lani-image
```

That server run starts fresh local comparison containers for Postgres and
MariaDB, skips Firebird at the `100000` row cutoff, and writes the source
report to:

- `crates/k-lani-bench-server/results/2026-05-29T18:03:23.541Z.md`

The exact host for that published report is described in:

- `reports/benchmark-host-2026-05-29.md`

## 6. Important boundary

This preview repository is intentionally binary-only. That is enough to make the
ticket-horde benchmark reproducible, because the runtime binaries and entrypoint
scripts are shipped here.

It is not enough to rerun the embedded/client-server comparative harnesses from
this repo alone, because the benchmark source crates are not redistributed in
this preview boundary. The release therefore contains:

- the exact published command lines
- the exact published configuration
- the exact runtime limits
- the raw comparative reports
- the host environment report

If full third-party rerunnability of the comparative harness from GitHub alone
is required, the benchmark source crates and their dependent Rust workspace code
must also be published, not only the preview binaries.