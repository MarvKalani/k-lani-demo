# k-lani client/server comparative benchmark

- benchmark_family: client/server
- benchmark_class: server-class systems over local client protocols
- profile: smoke
- row_count: 100
- lookup_count: 1000

## batched_insert_one_tx

| system | customer_story | batch_rows | total_wall_secs | rows_per_second |
| --- | --- | --- | --- | --- |
| k-lani | monthly invoice run / ETL import, indexed rows, one transaction | 100 | 0.02 | 4475.82 |
| harbour-proxy | monthly invoice run / ETL import, indexed rows, one transaction | 100 | 0.01 | 19905.41 |
| postgres | monthly invoice run / ETL import, indexed rows, one transaction | 100 | 0.01 | 18319.39 |
| mariadb | monthly invoice run / ETL import, indexed rows, one transaction | 100 | 0.00 | 20295.26 |
| firebird | monthly invoice run / ETL import, indexed rows, one transaction | 100 | 0.07 | 1506.19 |

## sustained_small_tx_1000_per_sec

| system | customer_story | duration_secs | writer_count | outcome | target_tx_per_sec | achieved_tx_per_sec | p95_commit_us | avg_batch_size_per_flush |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| k-lani | order intake during business hours, 1-5 rows per commit | 2 | 4 | saturated | 1000.00 | 705.76 | 5549.69 | 0.00 |
| harbour-proxy | order intake during business hours, 1-5 rows per commit | 2 | 4 | saturated | 1000.00 | 158.97 | 7962.70 | 1.00 |
| postgres | order intake during business hours, 1-5 rows per commit | 2 | 4 | saturated | 1000.00 | 996.79 | 4222.94 | 0.00 |
| mariadb | order intake during business hours, 1-5 rows per commit | 2 | 4 | saturated | 1000.00 | 876.63 | 10458.27 | 0.00 |
| firebird | order intake during business hours, 1-5 rows per commit | 2 | 4 | saturated | 1000.00 | 145.66 | 28277.55 | 0.00 |

## peak_concurrent_writers

| system | customer_story | duration_secs | writer_count | aggregate_tx_per_sec | per_writer_p95_us | avg_batch_size_per_flush |
| --- | --- | --- | --- | --- | --- | --- |
| k-lani | request spike with concurrent clerks saving at once | 2 | 4 | 697.51 | 5572.10 | 0.00 |
| harbour-proxy | request spike with concurrent clerks saving at once | 2 | 4 | 198.39 | 2011107.44 | 1.00 |
| postgres | request spike with concurrent clerks saving at once | 2 | 4 | 1410.49 | 5300.96 | 0.00 |
| mariadb | request spike with concurrent clerks saving at once | 2 | 4 | 1067.35 | 6891.93 | 0.00 |
| firebird | request spike with concurrent clerks saving at once | 2 | 4 | 173.25 | 22286.65 | 0.00 |

## point_lookup_random_100k

| system | customer_story | p50_us | p95_us | p99_us |
| --- | --- | --- | --- | --- |
| k-lani | open one customer record by primary id | 32.26 | 42.09 | 56.23 |
| harbour-proxy | open one customer record by primary id | 5.42 | 6.87 | 7.56 |
| postgres | open one customer record by primary id | 128.06 | 174.08 | 204.21 |
| mariadb | open one customer record by primary id | 46.12 | 70.76 | 99.87 |
| firebird | open one customer record by primary id | 42512.82 | 44100.42 | 44755.13 |

## range_scan_indexed_1pct

| system | customer_story | matching_rows | rows_per_second |
| --- | --- | --- | --- |
| k-lani | browse one indexed range page | 1.00 | 7418.95 |
| harbour-proxy | browse one indexed range page | 1.00 | 1250000.00 |
| postgres | browse one indexed range page | 1.00 | 2066.72 |
| mariadb | browse one indexed range page | 1.00 | 3019.32 |
| firebird | browse one indexed range page | 1.00 | 11.87 |

## eq_lookup_indexed_field_100k

| system | customer_story | p50_us | p95_us | p99_us |
| --- | --- | --- | --- | --- |
| k-lani | list all rows for one indexed field value | 32.89 | 40.13 | 57.40 |
| harbour-proxy | list all rows for one indexed field value | 0.03 | 0.10 | 0.19 |
| postgres | list all rows for one indexed field value | 140.59 | 192.64 | 292.54 |
| mariadb | list all rows for one indexed field value | 54.29 | 79.27 | 114.94 |
| firebird | list all rows for one indexed field value | 42729.07 | 44627.16 | 44986.52 |

## and_two_indexed_predicates_100k

| system | customer_story | p50_us | p95_us | p99_us |
| --- | --- | --- | --- | --- |
| k-lani | filter by two indexed predicates together | 32.01 | 43.46 | 53.86 |
| harbour-proxy | filter by two indexed predicates together | 0.03 | 0.10 | 0.21 |
| postgres | filter by two indexed predicates together | 141.43 | 202.12 | 253.93 |
| mariadb | filter by two indexed predicates together | 80.46 | 137.19 | 633.57 |
| firebird | filter by two indexed predicates together | 42530.21 | 44175.13 | 45025.57 |

## operational_dimensions

| system | binary_size_bytes | resident_ram_bytes | bootstrap_secs | backup_story | restore_story | config_surface | disk_footprint_bytes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| k-lani | 1678992 | unavailable | 0.2089 | cargo run -p k-lani-server --bin mkfx-dump -- --data-dir <dir> --file backup.mkdump | cargo run -p k-lani-server --bin mkfx-restore -- --data-dir <dir> --file backup.mkdump | 16 | 11419584 |
| harbour-proxy | unavailable | unavailable | 0.0001 | cp rows.dbf rows.dbf.bak | cp rows.dbf.bak rows.dbf | 1 | 25600 |
| postgres | unavailable | unavailable | external | pg_dump --format=custom --file backup.dump "$K_LANI_PG_DSN" | pg_restore --clean --if-exists --dbname "$K_LANI_PG_DSN" backup.dump | unavailable | unavailable |
| mariadb | unavailable | unavailable | external | mariadb-dump --databases <db> > backup.sql | mariadb < backup.sql | unavailable | unavailable |
| firebird | unavailable | unavailable | external | gbak -b -user SYSDBA -pas masterkey <db> backup.fbk | gbak -c -user SYSDBA -pas masterkey backup.fbk <db> | unavailable | unavailable |