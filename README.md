# k-lani: Left-Right WORM Database Engine (Preview)

k-lani is a specialized embedded and client/server database engine written in
Rust. It combines Left-Right snapshots, memory-mapped files, and a WORM-first
write path to keep the read path lock-free while concurrent writers fight over a
small hot inventory surface.

This repository contains the Docker-based live demo, the minimal redistributed
runtime binaries needed to run it, and the comparative benchmark reports that
back the public claims.

Live preview:

- [k-lani.com](https://k-lani.com) - landing page and benchmark story
- [demo.k-lani.com](https://demo.k-lani.com) - live ticket horde dashboard
- [hft.k-lani.com](https://hft.k-lani.com) - experimental HFT workstation

New to the engine model? Start with [GETTING_STARTED.md](GETTING_STARTED.md)
for the first table, field types, write/query flow, language entry points, and
common error handling.

Legal and contribution context:

- [LICENSE.md](LICENSE.md) - Business Source License 1.1 terms for the
  redistributed preview binaries and k-lani work.
- [SYMBIOSIS.md](SYMBIOSIS.md) - social contribution pact for agents, toolchains,
  and humans; it does not replace the license.

## 1. The Thundering Herd Benchmark

Traditional locking databases struggle when a small inventory surface receives a
huge burst of simultaneous purchase attempts. k-lani's ticket demo exercises
that exact failure mode.

Scenario:

- 100,000 users compete for 10,000 tickets
- 128 concurrent workers
- the horde container is capped at 2 vCPUs and 4 GB RAM

Reference result:

- time to sold out: 5.326 seconds
- correctly sold and re-verified: 10,000 / 10,000 tickets
- double-spends: 0
- peak combined read and update throughput: 10,633 ops/s

The live horde page proves persisted inventory contention handling on the TCP
server path. The repo also ships a native QUIC ticket path, but the public
`demo.k-lani.com` benchmark page is the TCP reference run.

## 2. Comparative Benchmarks

The point of k-lani is not to replace a general-purpose multi-terabyte
relational cluster. The point is to win on small hot data surfaces with extreme
write contention and very low read latency.

### Embedded write concurrency

When multiple writers fight over the same embedded table, classical locking
engines collapse into contention. The bundled embedded release report covers
`1,000,000` rows and `100,000` lookups, and shows:

| System | Scenario | Writers | TX/s | Per-writer p95 |
| :--- | :--- | ---: | ---: | ---: |
| k-lani | sustained concurrent point updates | 32 | 3794.78 | 10.93 ms |
| SQLite | sustained concurrent point updates | 32 | 190.02 | 216.10 ms |
| heed | sustained concurrent point updates | 32 | 360.04 | 148.73 ms |
| redb | sustained concurrent point updates | 32 | 686.84 | 75.76 ms |

The same release report records `310 ns` p50 primary-key lookups for k-lani on
the `1,000,000`-row dataset, versus `3820 ns` for SQLite.

### Client/server release report on this machine

The bundled client/server release report was generated on this host with
`100,000` rows and `100,000` random lookups. In that run, the k-lani server
path delivers:

- batched insert throughput: `413,292.85` rows/s, versus `20,986.64` for
  Postgres and `23,208.65` for MariaDB
- p50 point lookup latency: `31.27 us`, versus `128.56 us` for Postgres and
  `46.08 us` for MariaDB
- p50 indexed equality lookup: `53.95 us`, versus `343.10 us` for Postgres and
  `186.56 us` for MariaDB
- p50 two-index predicate lookup: `36.67 us`, versus `182.45 us` for Postgres
  and `170.51 us` for MariaDB
- compiled server binary footprint: `1,679,624` bytes, about `1.6 MB`

The same report also shows why the public claim is scoped: PostgreSQL is
stronger in the long `60s` server-side write saturation runs. k-lani is being
presented here for small hot sets, low-latency lookups, tight binary footprint,
and contention-heavy inventory surfaces rather than as a blanket replacement
for general-purpose OLTP stacks.

### Benchmark environment and bundled reports

These public numbers were measured on:

- Ubuntu `24.04.4 LTS` with Linux `6.17.0-29-generic`
- AMD Ryzen 5 7600X with `12` logical CPUs
- `31 GiB` RAM
- NVMe-backed `1.8 TB` system volume at `/` and `1.8 TB` workspace volume at
  `/d`
- Docker `29.5.2`

Bundled evidence in this repo:

- `reports/client-server-comparative-release-2026-05-29.md`
- `reports/embedded-core-comparative-release-2026-04-29.md`
- `reports/benchmark-host-2026-05-29.md`
- `reports/SHA256SUMS.txt`

For the exact local commands, container limits, runtime scripts, and the
published benchmark scope, see [BENCHMARKS.md](BENCHMARKS.md).

## 3. Run the Demo Locally

Requirements:

- Docker
- Docker Compose
- enough Docker memory for the default horde cap of 4 GB
- free local ports `8080`, `8081`, `8082`, and `7701/udp`
- network access on the first build to pull `debian:bookworm-slim`

Quickstart:

```bash
git clone https://github.com/MarvKalani/k-lani-demo.git
cd k-lani-demo
docker compose up -d --build
```

Watch the horde benchmark complete:

```bash
docker compose logs -f horde
```

Then open:

- `http://localhost:8082` for the landing page
- `http://localhost:8081` for the horde dashboard
- `http://localhost:8080` for the HFT workstation

The horde service runs with the published 2 vCPU / 4 GB limit. The HFT service
is deliberately capped to 10 MB of demo data so the preview host cannot grow an
unbounded market-feed state.

Stop everything and remove local volumes:

```bash
docker compose down -v
```

### Optional: run the one-shot QUIC ticket benchmark

The compose stack brings up the long-running landing, horde, and HFT services.
For the one-shot native QUIC ticket benchmark, build the image once and then run
it directly:

```bash
docker run --rm \
  -e K_LANI_DEMO_MODE=quic-ticket \
  -e K_LANI_USERS=100000 \
  -e K_LANI_WORKERS=128 \
  -p 7701:7701/udp \
  k-lani-demo:preview
```

## 4. What Is In This Repo

- `GETTING_STARTED.md` explains the first-table workflow, supported field
  types, language entry points, SQL-to-k-lani query shapes, and common errors.
- `LICENSE.md` contains the full legal license for the redistributed preview
  bundle and k-lani work.
- `SYMBIOSIS.md` contains the non-legal contribution pact for agents and humans.
- `bin/` contains only the four runtime binaries needed for the public demo
  modes.
- `docker-compose.yml` starts the local landing, horde, and HFT preview stack.
- `reports/` contains the comparative benchmark reports and `SHA256SUMS.txt`.
- `site/` contains the landing page plus legal pages and is required at runtime:
  the landing container serves it directly, and the horde container copies the
  legal pages from it into the generated dashboard output.
- `scripts/` contains the preview entrypoints used by the image.

What is not in this repo:

- the private Rust workspace
- extra internal executables or build artifacts
- seeded HFT demo payloads
- pitch drafts or maintainer-only handoff notes

## 5. Notes and Limits

- The HFT workstation is experimental and intentionally capped to 10 MB of demo
  data.
- The public repo ships only the minimal runtime binary set, not the whole
  private build output.
- Public benchmark claims should be read together with the committed reports and
  the checksum manifest.
- The Symbiosis Pact is social context only; the license remains the legal
  authority.