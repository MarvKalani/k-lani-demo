# k-lani embedded/core comparative benchmark

- source_report: `crates/k-lani-bench/results/2026-04-29T13:49:46.527Z.md`
- benchmark_family: embedded/core
- benchmark_class: embedded stores
- profile: release
- row_count: 1000000
- lookup_count: 100000

## batched_insert_one_tx

| system | customer_story | batch_rows | total_wall_secs | rows_per_second |
| --- | --- | --- | --- | --- |
| k-lani | monthly invoice run / ETL import, indexed rows, one transaction | 50000 | 0.05 | 1020468.23 |
| sqlite | monthly invoice run / ETL import, indexed rows, one transaction | 50000 | 0.03 | 1571303.82 |
| heed | monthly invoice run / ETL import, indexed rows, one transaction | 50000 | 0.02 | 2298690.35 |
| redb | monthly invoice run / ETL import, indexed rows, one transaction | 50000 | 0.10 | 511933.62 |

## sustained_small_tx_1000_per_sec

| system | customer_story | duration_secs | writer_count | outcome | target_tx_per_sec | achieved_tx_per_sec | p95_commit_ns |
| --- | --- | --- | --- | --- | --- | --- | --- |
| k-lani | order intake during business hours, 1-5 rows per commit | 60 | 4 | saturated | 1000.00 | 547.33 | 10612789.00 |
| sqlite | order intake during business hours, 1-5 rows per commit | 60 | 4 | saturated | 1000.00 | 192.05 | 24689628.00 |
| heed | order intake during business hours, 1-5 rows per commit | 60 | 4 | saturated | 1000.00 | 330.73 | 20668050.00 |
| redb | order intake during business hours, 1-5 rows per commit | 60 | 4 | saturated | 1000.00 | 663.60 | 10609215.00 |

## peak_concurrent_writers

| system | customer_story | duration_secs | writer_count | aggregate_tx_per_sec | per_writer_p95_ns |
| --- | --- | --- | --- | --- | --- |
| k-lani | concurrent in-process writers contending on one embedded store | 60 | 32 | 3794.78 | 10933734.00 |
| sqlite | concurrent in-process writers contending on one embedded store | 60 | 32 | 190.02 | 216098076.00 |
| heed | concurrent in-process writers contending on one embedded store | 60 | 32 | 360.04 | 148730085.00 |
| redb | concurrent in-process writers contending on one embedded store | 60 | 32 | 686.84 | 75758479.00 |

## point_lookup_random

| system | customer_story | p50_ns | p95_ns | p99_ns |
| --- | --- | --- | --- | --- |
| k-lani | open one customer record by primary id | 310.00 | 430.00 | 520.00 |
| sqlite | open one customer record by primary id | 3820.00 | 4000.00 | 4550.00 |
| heed | open one customer record by primary id | 320.00 | 550.00 | 1760.00 |
| redb | open one customer record by primary id | 590.00 | 840.00 | 970.00 |

## range_scan_indexed_1pct

| system | customer_story | matching_rows | rows_per_second |
| --- | --- | --- | --- |
| k-lani | browse one indexed range page | 9820.00 | 38555314.31 |
| sqlite | browse one indexed range page | 9820.00 | 7115503.76 |
| heed | browse one indexed range page | 9820.00 | 91162272.56 |
| redb | browse one indexed range page | 9820.00 | 25570985.52 |

## eq_lookup_indexed_field

| system | customer_story | p50_ns | p95_ns | p99_ns |
| --- | --- | --- | --- | --- |
| k-lani | list all rows for one indexed field value | 60659.00 | 65720.00 | 76829.00 |
| sqlite | list all rows for one indexed field value | 198399.00 | 206549.00 | 211640.00 |
| heed | list all rows for one indexed field value | 43140.00 | 48040.00 | 51580.00 |
| redb | list all rows for one indexed field value | 181700.00 | 189269.00 | 194080.00 |

## and_two_indexed_predicates

| system | customer_story | p50_ns | p95_ns | p99_ns |
| --- | --- | --- | --- | --- |
| k-lani | filter by two indexed predicates together | 44160.00 | 47690.00 | 51990.00 |
| sqlite | filter by two indexed predicates together | 3068499.00 | 3178778.00 | 3414998.00 |
| heed | filter by two indexed predicates together | 181777.00 | 192016.00 | 197176.00 |
| redb | filter by two indexed predicates together | 460441.00 | 472911.00 | 480500.00 |