# Holiday Rush travel portal smoke

- run_date: `2026-05-30`
- benchmark_binary: `real_world_booking_bench`
- benchmark_class: travel inventory contention over the k-lani TCP server
- scope: local smoke proof, not a full travel-commerce stack benchmark

## Workload

The Holiday Rush workload creates a `holiday_rooms` table with indexed `hotel_id`, `price`, and `is_booked` fields. Each session searches for an unbooked room under the configured price ceiling, locks a candidate room, verifies the current row, replaces `is_booked=0` with `is_booked=1`, unlocks, and then the benchmark recounts persisted booked rows.

Smoke shape:

- `1,000` rooms: `20` hotels x `50` rooms
- `1,000` booking sessions
- `16` workers
- `price_ceiling=1000`
- TCP server path, auth disabled, local loopback

## Result

```text
holiday_init_ok table=holiday_rooms rooms=1000
holiday_fixture_loaded rooms=1000
holiday_rush_done sessions=1000 rooms=1000 booked=1000 verified_booked=1000 read_queries=1000 lock_conflicts=73 already_booked=98 failed_sessions=0 wall_secs=6.406
```

The important invariant is tight inventory correctness: `booked=1000` and `verified_booked=1000` with `failed_sessions=0`. The live counter and the persisted recount match exactly.

## Bug Fixed Before Publishing

An earlier local smoke failed at `919 / 1000` bookings. That was a real bug, not a probability issue. The root cause was the secondary-index key encoding for `UInt32` range scans: the old little-endian key order made the `price in [0, 1000)` predicate match only `919` of the `1,000` Holiday Rush rooms. The fix changed integer secondary keys to ordered bytes for range scans and invalidated persisted secondary-index cache files by bumping the `.mksid` version.

The benchmark loop also now re-queries after a stale 32-candidate window instead of failing a session while eligible rooms still exist.

## Reproduce From This Preview Bundle

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

The container writes the raw log to `/reports/holiday-rush.raw.log`.
The exact lock-conflict counters and wall time vary by host and scheduler; a
passing run must keep `booked=1000`, `verified_booked=1000`, and
`failed_sessions=0`.
