# k-lani benchmark host environment

| dimension | value |
| --- | --- |
| benchmark_command | `./benchmark.sh --profile release --rows 100000 --lookups 100000 --reuse-k-lani-image` |
| client_server_source_report | `crates/k-lani-bench-server/results/2026-05-29T18:03:23.541Z.md` |
| embedded_source_report | `crates/k-lani-bench/results/2026-04-29T13:49:46.527Z.md` |
| os | Ubuntu 24.04.4 LTS |
| kernel | Linux 6.17.0-29-generic |
| cpu_model | AMD Ryzen 5 7600X 6-Core Processor |
| logical_cpus | 12 |
| memory_total | 31 GiB |
| system_volume | 1.8 TB NVMe mounted at `/` |
| workspace_volume | 1.8 TB NVMe mounted at `/d` |
| docker_version | Docker 29.5.2, build 79eb04c |
| comparison_systems | fresh local Postgres 16 and MariaDB 11 containers started by `benchmark.sh` |