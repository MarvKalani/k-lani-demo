# Getting Started With k-lani

This guide is the short path from "what do I create first?" to "how do I
write, read, and debug a table?" It uses an English `customers` table instead
of the older internal demo names.

The public preview repository is a runtime and benchmark bundle. It can run the
Docker demo locally, but it does not yet publish the full Rust workspace, NuGet
package, or npm package as source. The code below documents the current engine
and protocol surface used by the full workspace so application code can be
designed against the real model instead of against marketing snippets.

## Run the Preview First

```bash
git clone https://github.com/MarvKalani/k-lani-demo.git
cd k-lani-demo
docker compose up -d --build
```

Then open:

- `http://localhost:8082` for the landing page
- `http://localhost:8081` for the ticket horde dashboard
- `http://localhost:8080` for the HFT workstation

Stop the preview with:

```bash
docker compose down -v
```

## The Minimum Mental Model

- A table is a self-describing `.mkx` file plus WAL and index sidecars.
- Table names must be non-empty ASCII names up to 128 bytes using only
  letters, digits, `_`, and `-`.
- Fields are stored in a fixed order. `Append` and the embedded Rust API send
  values in that exact schema order.
- Writes are WAL-first. A committed write is recoverable before the mapped data
  file is updated.
- Updates are lock based: lock the record for your session, change values,
  commit, and release.
- Indexed equality is explicit. If you query an unindexed field as an index,
  k-lani returns `FieldNotIndexed` instead of silently pretending it is cheap.

## Create a Table Schema

For the server path, keep a YAML sidecar named after the table, for example
`customers.yaml` next to `customers.mkx` in the data directory.

```yaml
table: customers
version: 1
owner_field: customer_no
fields:
  - name: customer_no
    type: fixed_string
    length: 12
    required: true
    index: unique
    label: "Customer number"
  - name: name
    type: fixed_string
    length: 80
    required: true
    searchable: true
  - name: city
    type: fixed_string
    length: 40
    index: non_unique
  - name: balance_cents
    type: int64
  - name: status
    type: uint8
    index: non_unique
  - name: notes
    type: blob_ref
```

`index: unique` is for a key such as `customer_no`. `index: non_unique` or
`index: secondary` is for equality lookups such as `city = 'London'` or
`status = 1`.

In embedded Rust, table creation uses the engine field list directly. The YAML
schema is the human-readable sidecar used by the server/schema tooling.

```rust
use k_lani_core::error::Result;
use k_lani_core::table::{SecondaryIndexSpec, Table};
use k_lani_core::types::field::{FieldType, FieldValue};
use std::path::Path;

fn open_or_create_customers(dir: &Path) -> Result<Table> {
    std::fs::create_dir_all(dir)?;

    let indexes = [
        SecondaryIndexSpec { field_idx: 0, unique: true },  // customer_no
        SecondaryIndexSpec { field_idx: 2, unique: false }, // city
        SecondaryIndexSpec { field_idx: 4, unique: false }, // status
    ];

    if dir.join("customers.mkx").exists() {
        return Table::open_with_secondary_indexes(dir, "customers", &indexes);
    }

    let fields = [
        FieldType::FixedString(12),
        FieldType::FixedString(80),
        FieldType::FixedString(40),
        FieldType::Int64,
        FieldType::UInt8,
        FieldType::BlobRef,
    ];

    let mut table = Table::create(dir, "customers", &fields, 1)?;
    table.rebuild_secondary_indexes(&indexes)?;
    Ok(table)
}

fn main() -> Result<()> {
    let mut table = open_or_create_customers(Path::new("./data"))?;

    let (id, checksum) = table.append(&[
        FieldValue::FixedString(b"CUST-000001".to_vec()),
        FieldValue::FixedString(b"Ada Lovelace".to_vec()),
        FieldValue::FixedString(b"London".to_vec()),
        FieldValue::Int64(125_00),
        FieldValue::UInt8(1),
        FieldValue::Blob(b"first contact note".to_vec()),
    ])?;

    let active_customers = table.seek_by_field(4, &FieldValue::UInt8(1))?;
    println!("inserted {id:?} checksum={checksum} active={}", active_customers.len());
    Ok(())
}
```

`FieldValue::Blob(...)` can be supplied when the declared field is `BlobRef`;
the engine writes the blob and stores the reference in the row.

## Update a Record

Updates require a session-bound lock. The same session may relock the record;
another session receives `AlreadyLocked`.

```rust
use k_lani_core::error::Result;
use k_lani_core::lock::SessionId;
use k_lani_core::table::Table;
use k_lani_core::types::field::FieldValue;

fn mark_customer_inactive(table: &mut Table, id: k_lani_core::uuid::UuidV7) -> Result<u64> {
    let session = SessionId(42);
    table.lock_record(&id, session)?;
    table.set_field(&id, 4, FieldValue::UInt8(0), session)?;
    table.commit(&id, session)
}
```

If you decide not to persist the change, call `unlock_record` instead of
`commit`; that discards the pending mutation for that session.

## Supported Field Types

| YAML type | Rust `FieldType` | Runtime value | Use it for |
| :--- | :--- | :--- | :--- |
| `bool` | `Bool` | `FieldValue::Bool` | Flags |
| `uint8` | `UInt8` | `FieldValue::UInt8` | Small status/rank values |
| `uint16` | `UInt16` | `FieldValue::UInt16` | Compact counters |
| `uint32` | `UInt32` | `FieldValue::UInt32` | IDs, buckets, quantities |
| `uint64` | `UInt64` | `FieldValue::UInt64` | Large counters |
| `int8` | `Int8` | `FieldValue::Int8` | Signed compact values |
| `int16` | `Int16` | `FieldValue::Int16` | Signed compact counters |
| `int32` | `Int32` | `FieldValue::Int32` | Signed IDs or counters |
| `int64` | `Int64` | `FieldValue::Int64` | Money in minor units, timestamps |
| `float32` | `Float32` | `FieldValue::Float32` | Compact numeric signals |
| `float64` | `Float64` | `FieldValue::Float64` | Higher precision values |
| `fixed_string` + `length` | `FixedString(length)` | `FieldValue::FixedString(Vec<u8>)` | Bounded text and keys |
| `date` | `Date` | `FieldValue::Date` | Calendar day values |
| `datetime` or `date_time` | `DateTime` | `FieldValue::DateTime` | Millisecond time values |
| `uuid_v7` | `UuidV7` | `FieldValue::UuidV7` | Time-sortable identifiers |
| `accounting_numeric` + `scale` | `AccountingNumeric` | `FieldValue::AccountingNumeric` | Fixed-scale accounting values |
| `blob_ref` or `blob` | `BlobRef` | `FieldValue::BlobRef` or `FieldValue::Blob` | Externalized payloads |
| `vector_f32` + `dimensions` | `VectorF32(dimensions)` | `FieldValue::VectorF32` | Embeddings or numeric vectors |
| `packed_text6` + `length` + `alphabet` | `PackedText6` | `FieldValue::FixedString` | Tiny fixed alphabet text |

Important width rules:

- `fixed_string` fails with `FieldOverflow` when the bytes exceed `length`.
- `vector_f32` fails with `FieldOverflow` when the vector dimension does not
  match the schema.
- Sending the wrong `FieldValue` variant for the declared field also fails with
  `FieldOverflow`.
- Too few bytes on the wire fail as `Truncated`.

## Query Shapes

k-lani queries are intentionally explicit. That makes them easier to optimize
than free-form SQL text because the engine receives typed values, known field
slots, known indexes, and a bounded result shape.

| SQL thought | k-lani shape |
| :--- | :--- |
| `SELECT * FROM customers WHERE id = ?` | `Seek` by UUIDv7 record id |
| `SELECT * FROM customers WHERE customer_no = ?` | `SeekByField` on the indexed `customer_no` field |
| `SELECT customer_no, name FROM customers WHERE status = 1 LIMIT 64` | `SeekByField` or predicate seek with a projection/field mask |
| `SELECT * FROM seats WHERE is_booked = 0 AND rank = 3 LIMIT 64` | indexed equality on `is_booked`, indexed equality on `rank`, intersect candidate ids, then seek projected rows |
| `UPDATE customers SET status = 0 WHERE id = ?` | `Lock` -> `SetField`/`Replace` -> WAL commit -> unlock |

Why this is optimizable:

- No SQL parser has to infer intent from a string.
- Field names resolve to fixed field indexes.
- Fixed-width values give predictable row layout and cheap comparisons.
- Index usage is explicit; missing indexes fail loudly.
- Projection masks let the engine skip decoding fields that are neither
  filtered nor returned.
- Large result sets can be rejected or paged instead of accidentally materialized.

The server command set includes `OpenTable`, `CloseTable`, `GetSchema`, `Seek`,
`SeekByField`, `SeekByPredicate`, `Lock`, `Unlock`, `Replace`, `Append`,
`Delete`, `Scan`, `ScanNext`, `BatchCommit`, `RegisterCursor`,
`InvokeCursorFilter`, and `Disconnect`.

## Common Errors and What To Do

| Error | Wire code | Meaning | Fix |
| :--- | :--- | :--- | :--- |
| `NotFound` | `0x0001` | Record/key does not exist or was deleted | Treat as normal miss, recreate, or refresh the id |
| `AlreadyLocked` | `0x0002` | Another session holds the row lock | Retry with backoff or surface a contention conflict |
| `NotLocked` | `0x0003` | You tried to update/delete/commit without owning the lock | Lock first and keep the same session id through commit |
| `ChecksumMismatch` | `0x0004` | Stored bytes failed checksum validation | Stop writes, preserve files, run recovery/verification |
| `Io` | `0x0005` | OS/file-system error | Check data directory, permissions, disk space, and mount health |
| `FieldOverflow` | `0x0006` | Value too wide, wrong value variant, or wrong vector dimension | Check schema order, string length, value type, and dimensions |
| `SchemaValidation` | `0x0007` | YAML/schema sidecar or required field validation failed | Fix `customers.yaml` and keep it beside the table files |
| `Protocol` | `0x0010` | Frame could not be decoded | Check client/server version and binary encoding |
| `AuthFailed` | `0x0020` | Authentication failed | Use the expected token/session configuration |
| `UnknownTable` | `0x0030` | Server cannot find or open the table | Create the table, mount the correct data dir, and verify the table name |
| `InvalidHandle` | `0x0031` | Client used a stale table handle | Reopen the table and retry with the new handle |
| `UnknownField` | `0x0032` | Field name/index is not in the schema | Fix spelling, schema version, or field order |
| `FieldNotIndexed` | `0x0033` | Indexed lookup requested for an unindexed field | Add `index: non_unique`/`unique`, rebuild indexes, or use a scan/predicate path |
| `ResultSetEstimateExceeded` | `0x0035` | Query would return too much data | Add a predicate, use an index, lower the limit, or page/stream results |

## Rust, C#, and TypeScript Entry Points

Rust is the native embedded path. Use it when your application owns the process
that stores the table, or when you want to run `k-lani-server` yourself against
a data directory.

C# currently talks to `k-lani-server` over the TCP protocol. The source
workspace contains a complete .NET 8 demo client with an
`IMkLaniRecordCodec<TRecord>` pattern: your model is a normal C# record/class,
and your codec encodes/decodes fields in schema order. For the `customers`
schema above, your codec would map:

- `customer_no` -> `string` encoded as `fixed_string(12)`
- `name` -> `string` encoded as `fixed_string(80)`
- `city` -> `string` encoded as `fixed_string(40)`
- `balance_cents` -> `long` encoded as `int64`
- `status` -> `byte` encoded as `uint8`
- `notes` -> `byte[]` or blob reference handling, depending on the client layer

TypeScript currently uses the browser/WebTransport edge through the
`k-lani-client` WASM package. There is no REST compatibility layer in the hot
path today. Browser code opens a WebTransport session, sends the binary
handshake frame, and then uses the same explicit command shapes: open table,
get schema, append, seek, lock/replace/unlock, and scan/paginate.

## Practical First Checklist

1. Pick a narrow hot table, not your whole application domain.
2. Name it with only `[A-Za-z0-9_-]`, for example `customers` or `seats`.
3. Write a YAML schema with fixed widths and explicit indexes.
4. Keep values in schema order in every client codec.
5. Index the fields you will use for equality lookups.
6. Treat `AlreadyLocked` and `NotFound` as normal application states.
7. Treat `FieldOverflow`, `UnknownField`, and `FieldNotIndexed` as schema/client
   bugs to fix before load testing.
8. Keep query limits explicit and page/stream large reads.

The point is not to translate arbitrary SQL text into another dialect. The
point is to express the exact storage operation you want so the engine can keep
the hot path small, typed, and predictable.