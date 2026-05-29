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

## If You Come From FoxPro

FoxPro's heart was not only tables; it was work areas, current order, `SEEK`,
and cursor-style walking:

```foxpro
SELECT customers
SET ORDER TO name
SEEK "Marvin"
SCAN WHILE Name = "Marvin"
    * work with the current row
ENDSCAN
```

k-lani keeps the same mechanical idea, but makes the hidden work-area state
explicit on the wire:

| FoxPro idea | k-lani equivalent |
| :--- | :--- |
| `SELECT customers` | `OpenTable("customers")` returns a numeric table handle for this session |
| `SET ORDER TO name` | choose the indexed field explicitly with `SeekByField`, `QueryIntersect`, `Scan`, `Fetch`, or `Stream` |
| `SEEK "Marvin"` | `SeekByField(handle, "name", encode_fixed_string("Marvin"), field_mask)` |
| `SCAN WHILE Name = "Marvin"` | start a filtered `Scan`/`Stream` and keep asking for pages until the cursor ends |
| current row pointer | record id plus returned row bytes; updates use `Lock` -> `Replace`/`Delete` to commit, or `Unlock` to cancel |
| selected fields in a browse/grid | `field_mask` projection so the server can skip decoding fields you did not ask for |

There is no server command called `SetOrder` today on purpose. In FoxPro,
`SET ORDER TO name` mutates the current work-area state: the next `SEEK` or
`SCAN` depends on that hidden session state. k-lani's wire protocol keeps that
choice inside each command instead. That makes requests replayable, easier to
audit, easier to route through clients, and harder to accidentally run against
the wrong order.

An SDK can still expose FoxPro-flavored sugar safely. It would just remember a
client-side `current_order = "name"` and translate `seek("Marvin")` into
`SeekByField(handle, "name", ...)`. The engine stays bare-metal and explicit;
the convenience layer can feel FoxPro-like.

## Cursor Model

k-lani has cursor concepts, but they are split by purpose instead of being one
mutable global record pointer.

### `Scan` / `ScanNext`: page cursor token

`Scan` takes a table handle, a binary filter, a `page_size`, and an optional
`limit`. The server evaluates the filter, returns the first page, and returns a
`cursor_token` only when more rows are waiting. `ScanNext(cursor_token)` returns
the next page for the same session. When the final page is returned, the token
is gone and `cursor_token` is `None`.

That is the closest wire-level equivalent to:

```foxpro
SCAN WHILE Name = "Marvin"
    * page through matching rows
ENDSCAN
```

The important details are:

- `ScanNext` does not start a new query. It only continues an existing `Scan`.
- The token is bound to the session that opened it.
- A bad, expired, or cross-session token returns `InvalidCursor`.
- `Scan` is useful for simple page-by-page reads, but it may materialize the
  matching records before paging them back.

### `Fetch`: stateless offset/limit page

`Fetch` takes a query shape plus `limit` and `offset`. It prepares the matching
row numbers for that request and returns exactly that page. Use it when a UI
grid wants page 1, page 2, page 3 without keeping a server cursor open.

### `Stream` / `StreamNext` / `StreamClose`: long-lived query cursor

`Stream` prepares a query once and returns a numeric `cursor_id`. `StreamNext`
then materializes the next page from that prepared row list. `StreamClose`
releases it. This is the better fit for a FoxPro-like browse cursor or a long
client iteration because the server keeps the prepared row ids and projection
state until the stream ends or idles out.

### `RegisterCursor` / `InvokeCursorFilter`: Wasm row filter

This pair is unfortunately named from a FoxPro perspective. It is not the table
navigation cursor. `RegisterCursor` registers a Wasm filter function and returns
a `cursor_id`; `InvokeCursorFilter` asks that Wasm function whether one encoded
row is accepted. Think "registered executable row filter", not `SCAN` state.

## Why The Cursor Matters

FoxPro was fast because a program could keep several tables open at once, set a
current order for each work area, jump to an indexed key with `SEEK`, and then
walk only the matching range with `SCAN WHILE`. A report cursor was often just a
temporary work area filled by procedural code: `CREATE CURSOR`, `APPEND BLANK`,
`REPLACE`, then `BROWSE` or print.

k-lani keeps that spirit, but it does not hide the active table and active order
inside process-global state. The client opens table handles explicitly, chooses
the indexed field per command, and continues large reads with cursor tokens or
stream ids. That is why the wire protocol has `SeekByField`, `Scan`,
`ScanNext`, `Stream`, and `StreamNext` instead of a server-side SQL dialect.

### Is Wasm possible in the public demo today?

Partly, yes. The published server binary contains the Wasm command surface:
`RegisterCursor` compiles/registers a Wasm module, and `InvokeCursorFilter`
calls a module export named `filter_row(ptr, len) -> i32` for encoded row bytes.
Those commands require a privileged session; the public browser pages do not
currently expose a Wasm demo button.

What exists today:

- server-side Wasm row filtering through `RegisterCursor` and
  `InvokeCursorFilter`
- a workspace Wasm executor for copied-memory filter/aggregate PoCs
- a newer zero-copy Wasm UDF crate boundary for host-pointer scan work

What is not packaged as a one-command public workflow yet:

- a polished command that builds a multi-table report cursor in one request
- a public UI page that uploads a Wasm module and displays such a report cursor

That distinction matters. The low-level pieces are real; the ergonomic report
cursor workflow is the missing next public example.

## FoxPro-Style Report Cursor Example

The English table name for the old "invoice positions" idea is usually
`invoice_lines` or `invoice_line_items`. This example uses `invoice_lines`.

Imagine an old FoxPro/Northwind-style report: show customers and their invoice
revenue, starting with `Alfreds Futterkiste`.

### Base tables

`customers.yaml`:

```yaml
table: customers
version: 1
owner_field: customer_no
fields:
  - name: customer_no
    type: fixed_string
    length: 8
    required: true
    index: unique
  - name: name
    type: fixed_string
    length: 80
    required: true
    index: non_unique
  - name: city
    type: fixed_string
    length: 40
    index: non_unique
```

`invoices.yaml`:

```yaml
table: invoices
version: 1
owner_field: invoice_id
fields:
  - name: invoice_id
    type: uint32
    required: true
    index: unique
  - name: customer_no
    type: fixed_string
    length: 8
    required: true
    index: non_unique
  - name: invoice_date
    type: date
  - name: status
    type: uint8
    index: non_unique
```

`invoice_lines.yaml`:

```yaml
table: invoice_lines
version: 1
owner_field: invoice_id
fields:
  - name: invoice_id
    type: uint32
    required: true
    index: non_unique
  - name: line_no
    type: uint16
  - name: product_name
    type: fixed_string
    length: 80
  - name: quantity
    type: uint32
  - name: unit_price_cents
    type: int64
```

Create and seed the customer table in embedded Rust:

```rust
use k_lani_core::error::Result;
use k_lani_core::table::{SecondaryIndexSpec, Table};
use k_lani_core::types::field::{FieldType, FieldValue};
use std::path::Path;

fn fixed(text: &str) -> FieldValue {
  FieldValue::FixedString(text.as_bytes().to_vec())
}

fn create_and_seed_customers(dir: &Path) -> Result<Table> {
  std::fs::create_dir_all(dir)?;

  let fields = [
    FieldType::FixedString(8),
    FieldType::FixedString(80),
    FieldType::FixedString(40),
  ];
  let indexes = [
    SecondaryIndexSpec { field_idx: 0, unique: true },
    SecondaryIndexSpec { field_idx: 1, unique: false },
    SecondaryIndexSpec { field_idx: 2, unique: false },
  ];

  let mut customers = Table::create(dir, "customers", &fields, 1)?;
  customers.rebuild_secondary_indexes(&indexes)?;

  for row in [
    ("ALFKI", "Alfreds Futterkiste", "Berlin"),
    ("ANATR", "Ana Trujillo Emparedados y helados", "Mexico City"),
    ("BONAP", "Bon app", "Marseille"),
    ("FRANK", "Frankenversand", "Muenchen"),
    ("QUEEN", "Queen Cozinha", "Sao Paulo"),
  ] {
    customers.append(&[fixed(row.0), fixed(row.1), fixed(row.2)])?;
  }

  Ok(customers)
}
```

The `invoices` and `invoice_lines` tables use the same pattern: define the
field widths, rebuild the declared secondary indexes, then append values in
schema order.

Seed data:

| Table | Rows |
| :--- | :--- |
| `customers` | `ALFKI Alfreds Futterkiste Berlin`, `ANATR Ana Trujillo Emparedados y helados Mexico City`, `BONAP Bon app Marseille`, `FRANK Frankenversand Muenchen`, `QUEEN Queen Cozinha Sao Paulo` |
| `invoices` | `1001 ALFKI paid`, `1002 ALFKI open`, `1003 ANATR paid`, `1004 BONAP paid`, `1005 FRANK paid` |
| `invoice_lines` | `1001 Chai 10 x 1800`, `1001 Chang 5 x 1900`, `1002 Ikura 2 x 3100`, `1003 Queso 3 x 2100`, `1003 Cajun Seasoning 4 x 2200`, `1004 Chef Anton Gumbo 1 x 5500`, `1005 Tofu 8 x 1200`, `1005 Manjimup Apples 2 x 9900` |

The report cursor we want back is not a stored table. It is a materialized
result cursor with this row shape:

| customer_no | name | invoice_count | revenue_cents |
| :--- | :--- | ---: | ---: |
| `ALFKI` | Alfreds Futterkiste | 2 | 33700 |
| `FRANK` | Frankenversand | 1 | 29400 |
| `ANATR` | Ana Trujillo Emparedados y helados | 1 | 15100 |
| `BONAP` | Bon app | 1 | 5500 |
| `QUEEN` | Queen Cozinha | 0 | 0 |

### How old FoxPro code actually looked

This is the procedural shape old FoxPro developers recognize. It opens three
tables in separate work areas, chooses the controlling index for each one, walks
the parent table, seeks into child ranges, and fills a temporary result cursor.

```foxpro
USE customers IN 0 ALIAS customers
USE invoices IN 0 ALIAS invoices
USE invoice_lines IN 0 ALIAS lines

SELECT customers
SET ORDER TO customer_no

SELECT invoices
SET ORDER TO customer_no

SELECT lines
SET ORDER TO invoice_id

CREATE CURSOR customer_revenue ;
    (customer_no C(8), name C(80), invoice_count I, revenue_cents N(12,0))

SELECT customers
SCAN
    lcCustomerNo = customers.customer_no
    lcName = customers.name
    lnInvoiceCount = 0
    lnRevenueCents = 0

    SELECT invoices
    SEEK lcCustomerNo
    SCAN WHILE invoices.customer_no = lcCustomerNo
        lnInvoiceCount = lnInvoiceCount + 1
        lnInvoiceId = invoices.invoice_id

        SELECT lines
        SEEK lnInvoiceId
        SCAN WHILE lines.invoice_id = lnInvoiceId
            lnRevenueCents = lnRevenueCents + ;
                (lines.quantity * lines.unit_price_cents)
        ENDSCAN

        SELECT invoices
    ENDSCAN

    SELECT customer_revenue
    APPEND BLANK
    REPLACE customer_no WITH lcCustomerNo, ;
            name WITH lcName, ;
            invoice_count WITH lnInvoiceCount, ;
            revenue_cents WITH lnRevenueCents

    SELECT customers
ENDSCAN

SELECT customer_revenue
INDEX ON revenue_cents TAG revenue_cents DESCENDING
SET ORDER TO revenue_cents
BROWSE
```

The cursor is a table-shaped work area. It has fields, rows, a current record,
and an order for display. The important part is not a query string; it is the
mechanical loop: select a work area, seek to a key, scan the matching run, append
a row to the result cursor, return to the parent work area.

### The same shape in k-lani primitives

k-lani makes each hidden FoxPro state transition explicit:

| FoxPro step | k-lani primitive |
| :--- | :--- |
| `USE customers IN 0 ALIAS customers` | `OpenTable("customers")` returns a session-bound handle |
| `SET ORDER TO customer_no` | each seek names the indexed field, for example `SeekByField(handle, "customer_no", ...)` |
| `SEEK lcCustomerNo` | indexed lookup using the encoded key bytes |
| `SCAN WHILE invoices.customer_no = lcCustomerNo` | consume returned matching rows, or use `Scan`/`ScanNext` for paged filters |
| `CREATE CURSOR customer_revenue (...)` | client or server allocates a result row shape for the report |
| `APPEND BLANK` + `REPLACE ...` | build one result row and push it into the result page/cursor buffer |
| `BROWSE` | client renders pages returned by `ScanNext` or `StreamNext` |

The explicit engine flow is:

1. `OpenTable("customers")`, `OpenTable("invoices")`, and
   `OpenTable("invoice_lines")` for the current session.
2. Read customers with `Stream` when the client wants a long browse cursor, or
   `Fetch` when it wants a stateless page.
3. For each customer row, call
   `SeekByField(invoices_handle, "customer_no", customer_no_bytes, field_mask)`.
4. For each invoice id, call
   `SeekByField(lines_handle, "invoice_id", invoice_id_bytes, field_mask)`.
5. Calculate `invoice_count` and `revenue_cents` from the returned child rows.
6. Append `(customer_no, name, invoice_count, revenue_cents)` to a report page.
7. Return the report page to the client, or keep a server-side stream cursor if
   the report is long enough to page.

That is intentionally close to FoxPro's real work-area loop. The difference is
that k-lani can move the loop to a server-side command or SDK helper later
without changing the storage model: the server already owns table handles,
indexed seeks, projections, limits, locks, and cursor paging.

### What a k-lani cursor is in the code today

There are three separate cursor shapes in the workspace:

| Cursor | Where it lives | What it stores | What it is for |
| :--- | :--- | :--- | :--- |
| `ScanCursor` | server engine | materialized matching records, next offset, page size, owning session | `Scan` followed by `ScanNext` page tokens |
| `StreamCursor` | server engine | prepared row numbers, projection mask, next offset, owning session | long-running `Stream` / `StreamNext` browse-style reads |
| `TimeTravelCursor` | core debug module | table path, schema, current slot, snapshot cutoff, optional projection | read-only debug walking over append slots |

`ScanCursor` is closest to a short FoxPro `SCAN WHILE` result page. The server
does the filter work, stores the matching records, and hands back a token for
the next page.

`StreamCursor` is closer to a browse cursor. The server keeps the row numbers
and projection state, and each `StreamNext` materializes the next page. This is
the best fit for long UI grids or a future server-built report cursor.

`TimeTravelCursor` is not a general application cursor. It is a debug reader
over table slots. It snapshots the append boundary when opened, can step
forward/backward by slot, can project fields, and can stage an in-memory update
overlay, but it is not MVCC and it is not the TCP `ScanNext` token.

`RegisterCursor` / `InvokeCursorFilter` are different again: they register and
call a Wasm row filter named `filter_row(ptr, len) -> i32`. That is useful for
sandboxed row predicates, but it is not the FoxPro navigation cursor and it is
not currently a shipped report reducer command.

The practical rule: when documenting current behavior, say `ScanCursor`,
`StreamCursor`, or `TimeTravelCursor` and describe the rows they hold. Do not
pretend there is a hidden SQL planner or a published fluent report API.

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
    index: non_unique
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
        SecondaryIndexSpec { field_idx: 1, unique: false }, // name
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

k-lani queries are intentionally explicit. In a general SQL database, an
ad-hoc query normally goes through a parser, analyzer/rewrite step, planner,
optimizer, and executor. PostgreSQL is very good at that, and prepared
statements can cache parts of the work, but internally the executor still ends
up doing the familiar storage operations: sequential scans, index scans,
bitmap intersections, projections, cursors, locks, and updates.

k-lani starts one layer lower. The client sends the already-shaped operation:
`SeekByField`, `QueryIntersect`, `Scan`, `Fetch`, `Stream`, `Lock`, `Replace`.
There is no SQL interpreter in the hot path that has to rediscover intent from
text. That is what "bare metal" means here: PostgreSQL may ultimately do a
similar physical operation internally; k-lani asks the caller to name that
operation directly.

| SQL thought | k-lani shape |
| :--- | :--- |
| `SELECT * FROM customers WHERE id = ?` | `Seek` by UUIDv7 record id |
| `SELECT * FROM customers WHERE customer_no = ?` | `SeekByField` on the indexed `customer_no` field |
| `SELECT customer_no, name FROM customers WHERE status = 1 LIMIT 64` | `SeekByField` or predicate seek with a projection/field mask |
| `SELECT * FROM seats WHERE is_booked = 0 AND rank = 3 LIMIT 64` | indexed equality on `is_booked`, indexed equality on `rank`, intersect candidate ids, then seek projected rows |
| `UPDATE customers SET status = 0 WHERE id = ?` | `Lock` -> `SetField`/`Replace` -> WAL commit and lock release |

Why this is optimizable:

- No SQL parser has to infer intent from a string.
- Field names resolve to fixed field indexes.
- Fixed-width values give predictable row layout and cheap comparisons.
- Index usage is explicit; missing indexes fail loudly.
- Projection masks let the engine skip decoding fields that are neither
  filtered nor returned.
- Large result sets can be rejected or paged instead of accidentally materialized.

## Server Command Reference

The TCP/WebTransport protocol is a binary command protocol. Clients do not send
SQL text; they send one of these commands with typed bytes.

### Session and table commands

| Command | What it does | FoxPro analogy |
| :--- | :--- | :--- |
| `Handshake` | Opens the wire session, checks protocol version/auth, and returns the session id. | Start a connection/session |
| `OpenTable` | Opens a named table and returns a handle used by later commands. | `SELECT customers` / open work area |
| `CloseTable` | Releases a handle for this session. | close work area |
| `GetSchema` | Returns table metadata: field names, type tags, lengths, required flags, indexes, labels. | `AFIELDS()` / structure introspection |
| `Disconnect` | Releases the session's handles and server-side session state. | close connection |

### Point read and indexed query commands

| Command | What it does | Use it when |
| :--- | :--- | :--- |
| `Seek` | Reads one row by UUIDv7 record id. Returns `NotFound` when the row is missing or deleted. | You already have the record id. |
| `SeekByField` | Uses one indexed schema field and one encoded value. Returns rows projected by `field_mask`. | FoxPro `SET ORDER TO name` + `SEEK "Marvin"`. |
| `SeekByPredicate` | Evaluates a binary predicate against indexed/filterable fields and returns projected rows. | You have a structured `WHERE` condition, not just one key. |
| `QueryIntersect` | Intersects two indexed equality lookups with a hard result limit. | Hot-path `WHERE a = ? AND b = ? LIMIT n`. |
| `Explain` | Returns the planned strategy, indices used, estimated rows/bytes, and rejected alternatives for a query shape. | Ask "which order/index would this use?" before running it. |

### Cursor and paging commands

| Command | What it does | Use it when |
| :--- | :--- | :--- |
| `Scan` | Runs a filter, returns the first page, and may return a session-bound `cursor_token`. | You want a simple `SCAN WHILE ...` style page cursor. |
| `ScanNext` | Continues a previous `Scan` using its token. Returns `InvalidCursor` for bad, expired, or wrong-session tokens. | You are inside the loop and need the next page. |
| `Fetch` | Runs a query shape with `limit` and `offset`, without keeping a server cursor. | Stateless UI pagination. |
| `Stream` | Prepares a query shape once and returns a `cursor_id`. | Long browse/iteration cursor. |
| `StreamNext` | Returns the next page for a `Stream` cursor and advances its offset. | Continue a long browse cursor. |
| `StreamClose` | Releases a `Stream` cursor early. | Close the browse cursor. |

### Write commands

| Command | What it does | Use it when |
| :--- | :--- | :--- |
| `Append` | Appends one row, generates a UUIDv7 id, writes WAL first, returns id and checksum. | `APPEND BLANK` plus filled fields in one durable call. |
| `Lock` | Acquires the record lock for this session. | Begin an edit on the current row. |
| `Replace` | Replaces all fields for a locked row, validates schema/index mutations, commits through WAL, releases the lock, and returns checksum. | FoxPro `REPLACE ...` on a locked/current row. |
| `Unlock` | Releases the lock without committing additional changes. | Cancel/release edit state. |
| `Delete` | Soft-deletes a locked row, updates indexes, commits through WAL, and releases the lock. | `DELETE` on the current row. |
| `BatchCommit` | Commits multiple inserts/replaces/deletes as one batch and can coalesce same-table writes. | Bulk update/import path. |
| `Checkpoint` | Flushes table/index state so recovery has less WAL to replay. | Maintenance/durability housekeeping. |

### Advanced extension and notification commands

| Command | What it does | Use it when |
| :--- | :--- | :--- |
| `RegisterCursor` | Compiles/registers a Wasm row filter exporting `filter_row(ptr, len) -> i32` and returns a filter id. | You need a custom row predicate loaded into the server. |
| `InvokeCursorFilter` | Invokes a registered Wasm row filter for one encoded row and returns accepted/rejected. | You are applying that custom filter. |
| `Subscribe` | Subscribes this session to write notifications for a table handle. | UI/live client wants change notices. |
| `Unsubscribe` | Stops table notifications for this session. | Close live update channel. |
| `RegisterUdp` | Registers a UDP port for push notifications after table writes. | Low-latency side-channel notification. |
| `SystemGetStats` | Returns workload counters such as appends, replaces, seeks, full scans, and range scans. | Dashboard/operations view. |

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