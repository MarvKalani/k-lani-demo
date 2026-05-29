# k-lani embedded/core comparative benchmark

- source_report: `crates/k-lani-bench/results/2026-05-21T06:12:32.735Z.md`
- benchmark_family: embedded/core
- benchmark_class: embedded stores
- profile: dev
- row_count: 5000
- lookup_count: 10000

## batched_insert_one_tx

| system | customer_story | batch_rows | total_wall_secs | rows_per_second |
| --- | --- | --- | --- | --- |
| k-lani | monthly invoice run / ETL import, indexed rows, one transaction | 5000 | 0.01 | 364031.34 |
| sqlite | monthly invoice run / ETL import, indexed rows, one transaction | 5000 | 0.01 | 486711.32 |
| heed | monthly invoice run / ETL import, indexed rows, one transaction | 5000 | 0.01 | 454019.74 |
| redb | monthly invoice run / ETL import, indexed rows, one transaction | 5000 | 0.01 | 349203.49 |

## sustained_small_tx_1000_per_sec

| system | customer_story | duration_secs | writer_count | outcome | target_tx_per_sec | achieved_tx_per_sec | p95_commit_ns |
| --- | --- | --- | --- | --- | --- | --- | --- |
| k-lani | order intake during business hours, 1-5 rows per commit | 10 | 4 | saturated | 1000.00 | 499.51 | 11102724.00 |
| sqlite | order intake during business hours, 1-5 rows per commit | 10 | 4 | saturated | 1000.00 | 192.47 | 24731535.00 |
| heed | order intake during business hours, 1-5 rows per commit | 10 | 4 | saturated | 1000.00 | 304.78 | 21265935.00 |
| redb | order intake during business hours, 1-5 rows per commit | 10 | 4 | saturated | 1000.00 | 563.74 | 12743245.00 |

## peak_concurrent_writers

| system | customer_story | duration_secs | writer_count | aggregate_tx_per_sec | per_writer_p95_ns |
| --- | --- | --- | --- | --- | --- |
| k-lani | concurrent in-process writers contending on one embedded store | 10 | 32 | 3648.82 | 11745213.00 |
| sqlite | concurrent in-process writers contending on one embedded store | 10 | 32 | 183.27 | 219341362.00 |
| heed | concurrent in-process writers contending on one embedded store | 10 | 32 | 327.23 | 147245092.00 |
| redb | concurrent in-process writers contending on one embedded store | 10 | 32 | 541.01 | 85913105.00 |

## point_lookup_random

| system | customer_story | p50_ns | p95_ns | p99_ns |
| --- | --- | --- | --- | --- |
| k-lani | open one customer record by primary id | 270.00 | 469.00 | 709.00 |
| sqlite | open one customer record by primary id | 3030.00 | 4079.00 | 4659.00 |
| heed | open one customer record by primary id | 180.00 | 210.00 | 270.00 |
| redb | open one customer record by primary id | 359.00 | 460.00 | 600.00 |

## range_scan_indexed_1pct

| system | customer_story | matching_rows | rows_per_second |
| --- | --- | --- | --- |
| k-lani | browse one indexed range page | 57.00 | 1112890.00 |
| sqlite | browse one indexed range page | 57.00 | 1261676.04 |
| heed | browse one indexed range page | 57.00 | 9882108.18 |
| redb | browse one indexed range page | 57.00 | 8785450.06 |

## eq_lookup_indexed_field

| system | customer_story | p50_ns | p95_ns | p99_ns |
| --- | --- | --- | --- | --- |
| k-lani | list all rows for one indexed field value | 240.00 | 280.00 | 490.00 |
| sqlite | list all rows for one indexed field value | 4498.00 | 6708.00 | 7918.00 |
| heed | list all rows for one indexed field value | 470.00 | 599.00 | 830.00 |
| redb | list all rows for one indexed field value | 1509.00 | 2050.00 | 2399.00 |

## and_two_indexed_predicates

| system | customer_story | p50_ns | p95_ns | p99_ns |
| --- | --- | --- | --- | --- |
| k-lani | filter by two indexed predicates together | 420.00 | 810.00 | 1060.00 |
| sqlite | filter by two indexed predicates together | 7308.00 | 9977.00 | 12207.00 |
| heed | filter by two indexed predicates together | 1440.00 | 2080.00 | 2719.00 |
| redb | filter by two indexed predicates together | 3520.00 | 4889.00 | 5989.00 |