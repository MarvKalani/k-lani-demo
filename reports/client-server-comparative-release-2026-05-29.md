# k-lani client/server comparative benchmark

- source_report: `crates/k-lani-bench-server/results/2026-05-29T18:03:23.541Z.md`
- benchmark_family: client/server
- benchmark_class: server-class systems over local client protocols
- profile: release
- row_count: 100000
- lookup_count: 100000

## skipped_systems

| system | reason |
| --- | --- |
| firebird | firebird_cutoff_100k |

## batched_insert_one_tx

| system | customer_story | batch_rows | total_wall_secs | rows_per_second |
| --- | --- | --- | --- | --- |
| k-lani | monthly invoice run / ETL import, indexed rows, one transaction | 50000 | 0.12 | 413292.85 |
| harbour-proxy | monthly invoice run / ETL import, indexed rows, one transaction | 50000 | 0.05 | 938755.83 |
| postgres | monthly invoice run / ETL import, indexed rows, one transaction | 50000 | 2.38 | 20986.64 |
| mariadb | monthly invoice run / ETL import, indexed rows, one transaction | 50000 | 2.15 | 23208.65 |

## sustained_small_tx_1000_per_sec

| system | customer_story | duration_secs | writer_count | outcome | target_tx_per_sec | achieved_tx_per_sec | p95_commit_us | avg_batch_size_per_flush |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| k-lani | order intake during business hours, 1-5 rows per commit | 60 | 4 | saturated | 1000.00 | 732.53 | 5612.73 | 0.00 |
| harbour-proxy | order intake during business hours, 1-5 rows per commit | 60 | 4 | saturated | 1000.00 | 177.24 | 7070.65 | 1.00 |
| postgres | order intake during business hours, 1-5 rows per commit | 60 | 4 | target_met | 1000.00 | 999.90 | 5250.44 | 0.00 |
| mariadb | order intake during business hours, 1-5 rows per commit | 60 | 4 | saturated | 1000.00 | 806.57 | 9939.26 | 0.00 |

## peak_concurrent_writers

| system | customer_story | duration_secs | writer_count | aggregate_tx_per_sec | per_writer_p95_us | avg_batch_size_per_flush |
| --- | --- | --- | --- | --- | --- | --- |
| k-lani | request spike with concurrent clerks saving at once | 60 | 32 | 3174.03 | 11684.06 | 0.00 |
| harbour-proxy | request spike with concurrent clerks saving at once | 60 | 32 | 185.24 | 60129374.26 | 1.00 |
| postgres | request spike with concurrent clerks saving at once | 60 | 32 | 10224.85 | 5286.28 | 0.00 |
| mariadb | request spike with concurrent clerks saving at once | 60 | 32 | 3727.95 | 14049.66 | 0.00 |

## point_lookup_random_100k

| system | customer_story | p50_us | p95_us | p99_us |
| --- | --- | --- | --- | --- |
| k-lani | open one customer record by primary id | 31.27 | 37.73 | 46.89 |
| harbour-proxy | open one customer record by primary id | 5.58 | 6.00 | 8.09 |
| postgres | open one customer record by primary id | 128.56 | 166.00 | 247.49 |
| mariadb | open one customer record by primary id | 46.08 | 59.62 | 87.66 |

## range_scan_indexed_1pct

| system | customer_story | matching_rows | rows_per_second |
| --- | --- | --- | --- |
| k-lani | browse one indexed range page | 1032.00 | 3765214.09 |
| harbour-proxy | browse one indexed range page | 1032.00 | 67406923.58 |
| postgres | browse one indexed range page | 1032.00 | 917485.84 |
| mariadb | browse one indexed range page | 1032.00 | 1669751.61 |

## eq_lookup_indexed_field_100k

| system | customer_story | p50_us | p95_us | p99_us |
| --- | --- | --- | --- | --- |
| k-lani | list all rows for one indexed field value | 53.95 | 69.58 | 100.57 |
| harbour-proxy | list all rows for one indexed field value | 0.09 | 0.12 | 0.15 |
| postgres | list all rows for one indexed field value | 343.10 | 448.54 | 511.38 |
| mariadb | list all rows for one indexed field value | 186.56 | 241.31 | 321.58 |

## and_two_indexed_predicates_100k

| system | customer_story | p50_us | p95_us | p99_us |
| --- | --- | --- | --- | --- |
| k-lani | filter by two indexed predicates together | 36.67 | 47.09 | 60.12 |
| harbour-proxy | filter by two indexed predicates together | 0.06 | 0.19 | 0.28 |
| postgres | filter by two indexed predicates together | 182.45 | 234.48 | 323.28 |
| mariadb | filter by two indexed predicates together | 170.51 | 233.08 | 311.75 |

## operational_dimensions

| system | binary_size_bytes | resident_ram_bytes | bootstrap_secs | backup_story | restore_story | config_surface | disk_footprint_bytes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| k-lani | 1679624 | unavailable | 0.2457 | cargo run -p k-lani-server --bin mkfx-dump -- --data-dir <dir> --file backup.mkdump | cargo run -p k-lani-server --bin mkfx-restore -- --data-dir <dir> --file backup.mkdump | 16 | 81584083 |
| harbour-proxy | unavailable | unavailable | 0.0001 | cp rows.dbf rows.dbf.bak | cp rows.dbf.bak rows.dbf | 1 | 25600000 |
| postgres | unavailable | unavailable | external | pg_dump --format=custom --file backup.dump "$K_LANI_PG_DSN" | pg_restore --clean --if-exists --dbname "$K_LANI_PG_DSN" backup.dump | unavailable | unavailable |
| mariadb | unavailable | unavailable | external | mariadb-dump --databases <db> > backup.sql | mariadb < backup.sql | unavailable | unavailable |