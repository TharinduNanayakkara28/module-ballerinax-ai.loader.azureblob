# Phase 3 — The Loader

**Status:** ✅ Implemented, compiles, pure logic unit-tested (46/46 tests passing)
**Caveat:** live `load()` orchestration is not yet integration-tested — that needs a test
seam decided at the start of Phase 4 (see §6).
**Goal:** Implement `TextDataLoader` (`*ai:DataLoader`) and the acquisition logic over the
`ballerinax/azure_storage_service.blobs` connector: container resolution, prefix listing
with `NextMarker` pagination, client-side recursion filtering, blob download, the
explicit-blob-vs-prefix disambiguation, and single-vs-array return.

---

## 1. `TextDataLoader` (`ballerina/blob_data_loader.bal`)

```ballerina
public isolated class TextDataLoader {
    *ai:DataLoader;
    private final blobs:BlobClient blobClient;      // constructed via newBlobClient (Phase 2)
    private final readonly & Source[] sources;

    public isolated function init(ConnectionConfig, Source[]) returns ai:Error?;
    public isolated function load() returns ai:Document[]|ai:Document|ai:Error;
}
```
`BlobClient` is a `public isolated client class`, so it lives safely as a `final` field of
the isolated loader. `init` rejects an empty `sources` list and builds the client (wrapping
failures as `ai:Error`).

### `load()` algorithm
```
for each Source src:
    containers = resolveContainers(src.container)     // [name] or all (paged) when "*"
    tolerateMissing = src.container == "*"
    for each container, for each rawPath:
        documents += loadPrefix(container, rawPath, recursive, includeExtensions, tolerateMissing)
return documents.length()==1 ? documents[0] : documents
```

### Private methods
| Method | Responsibility |
|---|---|
| `resolveContainers(container)` | `"*"` → paged `listContainers` → de-duped names; else `[container]`. |
| `loadPrefix(container, rawPath, …)` | Disambiguates explicit-blob vs folder prefix (below). |
| `listPrefix(container, prefix, …)` | Lists a prefix, applies recursion + extension filters, builds documents, skips/logs unsupported. |
| `listAllBlobs(container, prefix)` | `listBlobs` loop following `nextMarker` until `""`. |
| `toDocument(container, entry)` | `getBlob` → `buildDocument`; metadata from the listing entry, falling back to the download. |

### Free helpers (same file)
- `toBlobEntry(blobs:Blob) → BlobEntry` — reads `Content-Type` / `Content-Length` /
  `Creation-Time` / `Last-Modified` out of the blob's untyped `Properties` map.
- `isNotFoundError(error) → boolean` — `blobs:ServerError` with `httpStatus == 404` or an
  `errorCode` containing `NotFound`, else a message-text fallback.

---

## 2. Key behaviours & decisions

### Explicit-blob vs folder-prefix disambiguation (`loadPrefix`)
- `rawPath` normalizes to a blob prefix via `normalizeBlobPath` (drops leading `/`, keeps a
  trailing `/`, maps root to `""`).
- **Root (`""`) or trailing `/`** → unambiguously a folder → `listPrefix`.
- **No trailing `/`** → probe with `getBlob`:
  - **200** → an explicitly named blob → always loaded (bypasses the extension filter). If
    it isn't text-representable → **error** (format-specific for Office), matching SharePoint.
  - **404 + has an extension** (looks like a file) → missing file → **error** ("blob not
    found"), i.e. typo detection — **unless** `tolerateMissing` (`"*"`), then skipped.
  - **404 + no extension** (looks like a folder) → `listPrefix` with prefix `normalized + "/"`.
  - **other error** → surfaced.

  > Uses one `getBlob` (not a separate `getBlobProperties`) — if it's a real blob we want its
  > bytes anyway; if not, a 404 body is cheap.

### Recursion without a `delimiter`
The connector has no `delimiter`, so `listBlobs` always returns every depth under a prefix.
Non-recursive listings are narrowed **client-side** by `isDirectChild(name, prefix)` (keep a
blob only if the remainder after the prefix has no further `/`). Uniform for root and folder
prefixes.

### Pagination
`listBlobs` / `listContainers` loop while `nextMarker != ""`, re-issuing with `marker`.

### Skipped vs error
- Inside a **listing**, unsupported/Office/binary blobs are **skipped with a `log:printWarn`**
  (never fatal), plus zero-length `foo/` folder-marker blobs.
- An **explicitly named** unsupported blob is an **error**.

### Metadata & a known limitation
`fileName` is the **full blob name** (e.g. `reports/q1.pdf`) — the blob's identity, and the
Azure-idiomatic choice. `Content-Type`/`Content-Length` populate `mimeType`/`fileSize`.
**Timestamps:** Azure's List-Blobs `Creation-Time`/`Last-Modified` are **RFC 1123**, which
`time:utcFromString` (ISO 8601) rejects, so `createdAt`/`modifiedAt` are currently dropped
gracefully. The explicit-blob (`getBlob`) path has no timestamps either. Revisit with an
RFC 1123 parser if timestamp metadata becomes important.

---

## 3. Files touched

| File | Change |
|---|---|
| `ballerina/blob_data_loader.bal` | **New** — `TextDataLoader` + `toBlobEntry` + `isNotFoundError`. |
| `ballerina/utils.bal` | **Added** `dedupeStrings`, `normalizeBlobPath`, `isDirectChild`, `propString`, `propDecimal` (+ a note on the RFC 1123 timestamp drop). |
| `ballerina/tests/loader_test.bal` | **New** — 15 unit tests. |

---

## 4. Tests (`ballerina/tests/loader_test.bal`) — 15 new

| Area | Tests |
|---|---|
| `init` | empty sources → error; valid sources → constructs |
| `normalizeBlobPath` | root variants; leading-slash drop; trailing-slash keep; nested; trim |
| `isDirectChild` | root prefix (direct vs sub-folder); folder prefix (direct/nested/marker) |
| `dedupeStrings` | order-preserving de-dup; empty |
| `propString` / `propDecimal` | reads; empty/missing → `()`; string & numeric `Content-Length`; unparseable → `()` |
| `toBlobEntry` | full `Properties`; missing `Properties` tolerated |
| `isNotFoundError` | 404 `ServerError`; `*NotFound` errorCode; message-text; false for 403/other |

```
cd ballerina && bal test → 46 passing, 0 failing, 0 skipped
```

---

## 5. What is NOT yet covered

The **connector-calling orchestration** (`load` / `loadPrefix` / `listPrefix` /
`listAllBlobs` / `toDocument`) is exercised only for its pure branches. End-to-end behaviour
— pagination across pages, recursion across a real tree, `"*"` container fan-out,
explicit-blob download, skip/warn paths — is **not** integration-tested yet, because the
connector cannot be pointed at a mock (Phase 2 finding: endpoint is hard-derived from
`accountName`, no override).

---

## 6. `load()` integration testing — DECIDED: not covered

Since the connector can't target a local mock HTTP service (endpoint is hard-derived from
`accountName`), integration-testing `load()` would have required a backend seam, the Azurite
emulator (blocked — wrong endpoint), or a live account.

**Decision (user):** leave `load()` **untested** — ship on the pure-logic unit coverage
only. No `BlobStore` seam is introduced; the loader stays a direct connector caller.

**Implications:**
- The end-to-end orchestration (pagination across pages, recursion across a real tree,
  `"*"` fan-out, explicit-blob download, skip/warn paths) is **not** verified by automated
  tests. It rests on the connector behaving as its contract states plus the unit-tested
  pure logic.
- Phase 4's "mock service + full matrix" is therefore **descoped**. What remains of the
  original Phase 4/6 is documentation (README + module docs).
- If confidence in `load()` is needed later, the plan §9 `BlobStore` seam can be added
  without changing the public API.

---

## 7. Phase 3 checklist

- [x] `TextDataLoader` implementing `*ai:DataLoader`; `init` + `load`.
- [x] `resolveContainers` (incl. `"*"` + pagination + de-dup).
- [x] `listAllBlobs` with `NextMarker` pagination.
- [x] Client-side recursion filter (`isDirectChild`).
- [x] `toDocument` via `getBlob` + `buildDocument`.
- [x] `loadPrefix` explicit-blob-vs-prefix + `tolerateMissing` + typo detection.
- [x] Single-vs-array return.
- [x] Compiles; pure logic unit-tested (46/46).
- [~] Integration test of `load()` — **descoped by decision** (§6); not covered.

**Next:** Documentation — README + module docs (auth: SAS + Shared Key; container/prefix
model; recursion; extension filtering; usage examples). The mock-service/full-matrix work
originally in Phase 4 is dropped per the §6 decision.
