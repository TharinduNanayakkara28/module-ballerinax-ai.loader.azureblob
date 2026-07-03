# Phase 2 — Public API & Client Wiring

**Status:** ✅ Complete & verified (31/31 tests passing)
**Goal:** Define the loader's public API (`ConnectionConfig`, `AuthorizationMethod`,
`Source`) and the internal `BlobEntry`, and wire construction of the underlying
`ballerinax/azure_storage_service.blobs` connector client from that config. This is the
first phase that imports the connector.

---

## 1. Connector resolution (first real import)

Importing `ballerinax/azure_storage_service.blobs` pulled the connector and its transitive
deps from Ballerina Central on first build:

- `ballerinax/azure_storage_service:4.3.4`
- `ballerinax/client.config:1.0.1` (the base `ConnectionConfig` the connector extends)
- `ballerina/xmldata:2.9.2` (the connector parses List-Blobs XML internally)

> This resolves the Phase 0 open item. `bal pull` had been inconclusive, but the real
> dependency-resolution path (via `bal build`) works. `Dependencies.toml` is now
> auto-populated with these entries.

Confirmed connector facts (read from the resolved bala, not docs):
- Client class is **`blobs:BlobClient`**; `init(ConnectionConfig) returns Error?`.
- `blobs:ConnectionConfig` = `*client.config:ConnectionConfig` + `never auth?` +
  `accessKeyOrSAS` + `accountName` + `authorizationMethod` + `httpVersion` (default `HTTP_1_1`).
- `blobs:AuthorizationMethod` enum = `ACCESS_KEY` (`"accessKey"`), `SAS` (`"SAS"`).
- Endpoint is derived: `https://{accountName}.blob.core.windows.net` — **no override field**.

---

## 2. Public API (`ballerina/types.bal`)

### `AuthorizationMethod` enum
`ACCESS_KEY` | `SAS`. Our own enum (not the connector's), so our public surface stays
decoupled and AAD can be added later without changing it.

### `ConnectionConfig` (closed record)
| Field | Type | Default |
|---|---|---|
| `accountName` | `string` | — (required) |
| `accessKeyOrSAS` | `string` (password) | — (required) |
| `authorizationMethod` | `AuthorizationMethod` | — (required) |
| `httpVersion` | `http:HttpVersion` | `HTTP_1_1` (matches the connector) |
| `http2Settings` | `http:ClientHttp2Settings` | optional |
| `timeout` | `decimal` | `30` |
| `forwarded` | `string` | `"disable"` |
| `poolConfig` | `http:PoolConfiguration` | optional |
| `cache` | `http:CacheConfig` | optional |
| `compression` | `http:Compression` | `COMPRESSION_AUTO` |
| `circuitBreaker` | `http:CircuitBreakerConfig` | optional |
| `retryConfig` | `http:RetryConfig` | optional |
| `responseLimits` | `http:ResponseLimitConfigs` | optional |
| `secureSocket` | `http:ClientSecureSocket` | optional |
| `proxy` | `http:ProxyConfig` | optional |
| `validation` | `boolean` | `true` |

### `Source` (closed record)
| Field | Type | Default | Meaning |
|---|---|---|---|
| `container` | `string` | — | Container name, or `"*"` for all containers (missing paths tolerated). |
| `paths` | `string[]` | `["/"]` | Blob-name prefixes; `["/"]` = whole container, `[]` = none. |
| `recursive` | `boolean` | `false` | Traverse virtual sub-folders under a prefix. |
| `includeExtensions` | `string[]?` | `()` | Case-insensitive extension allowlist; `()` = all. |

### `BlobEntry` (module-private)
`{ name, contentType?, contentLength?, creationTime?, lastModified? }` — a normalized
listing entry that decouples the loader from the connector's `Blob` (whose `Properties`
are an untyped `map<json>`). Populated by the Phase 3 listing code.

---

## 3. Client wiring (`ballerina/client.bal`)

Three module-private helpers:

- `toConnectorAuthMethod(AuthorizationMethod) → blobs:AuthorizationMethod` — enum bridge.
- `toConnectorConfig(ConnectionConfig) → blobs:ConnectionConfig` — forwards account identity,
  auth method, and every supported HTTP option. Required fields are set directly; optional
  ones (`http2Settings`, `poolConfig`, `cache`, `circuitBreaker`, `retryConfig`,
  `responseLimits`, `secureSocket`, `proxy`) are forwarded **only when set**, so the
  connector's own defaults apply otherwise.
- `newBlobClient(ConnectionConfig) → blobs:BlobClient|ai:Error` — constructs the connector
  client, wrapping any failure as an `ai:Error` ("Failed to initialize the Azure Blob
  Storage client: …").

---

## 4. Design decisions & deviations from the plan

| Topic | Decision | Why |
|---|---|---|
| Wrap vs. reuse connector config | **Wrap** (own `ConnectionConfig` + `AuthorizationMethod`) | Stable public surface; room for AAD later without a breaking change (plan §9). |
| `serviceUrl` / endpoint override | **Dropped** | The connector derives the endpoint from `accountName` and exposes no override. (The plan's §5 `serviceUrl?` was for the hand-built variant.) |
| `http1Settings` | **Dropped** | The connector's field uses `client.config`'s own type (incompatible with `http:`), **and** its `init` overwrites `http1Settings` with `{chunking: CHUNKING_NEVER}` — so forwarding it is both impossible and pointless. |
| `cookieConfig` / `socketConfig` / `laxDataBinding` | **Not included** | Present on the SharePoint config but absent from `client.config:1.0.1`, so the connector cannot accept them. |
| `TextDataLoader` class | **Not yet created** | Phase 2 is types + client construction; the class and `load()` are Phase 3. |

### ⚠️ Carry-forward for Phase 4 (testing)
Because the endpoint is hard-derived from `accountName` with no override, the connector
cannot be pointed at a local mock HTTP service the way the SharePoint loader's raw
`http:Client` could. Phase 4 testing of the acquisition path will therefore need either a
real/emulated storage account or a connector-level seam. To be decided when Phase 4 begins;
Phases 1–2 are fully unit-tested without it.

---

## 5. Tests (`ballerina/tests/types_test.bal`) — 10 new

| Area | Tests |
|---|---|
| `Source` | defaults (`["/"]`, `false`, `()`); explicit values |
| `ConnectionConfig` | defaults (`HTTP_1_1`, `30`, `"disable"`, `COMPRESSION_AUTO`, `validation`) |
| Auth mapping | `ACCESS_KEY`/`SAS` → connector enum |
| `toConnectorConfig` | identity+auth forwarded; optional options (timeout/retry/proxy/secureSocket) forwarded; unset options omitted |
| `newBlobClient` | constructs from SAS config; constructs from ACCESS_KEY config (offline — no network at init) |
| `BlobEntry` | shape + optional-field defaults |

```
cd ballerina && bal test → 31 passing, 0 failing, 0 skipped
```

---

## 6. Files touched

| File | Change |
|---|---|
| `ballerina/types.bal` | **New** — `AuthorizationMethod`, `ConnectionConfig`, `Source`, `BlobEntry`. |
| `ballerina/client.bal` | **New** — `toConnectorAuthMethod`, `toConnectorConfig`, `newBlobClient`. |
| `ballerina/tests/types_test.bal` | **New** — 10 tests. |
| `ballerina/Dependencies.toml` | **Auto-updated** by `bal` with the connector + transitive deps. |

---

## 7. Phase 2 checklist

- [x] Import the connector; confirm resolution from Central (closes the Phase 0/3 open item).
- [x] Define `ConnectionConfig`, `AuthorizationMethod`, `Source`, `BlobEntry`.
- [x] Map our config → connector config; construct `blobs:BlobClient` from it.
- [x] Unit-test defaults, mapping, and client construction (SAS + ACCESS_KEY).
- [x] `bal test` green (31/31).

**Next:** Phase 3 — the loader. `resolveContainers` (incl. `"*"` via `listContainers`),
paged `listBlobs` → `BlobEntry`, the client-side recursion filter, `toDocument` (via
`getBlob` + `buildDocument`), `loadPrefix` (explicit-blob vs prefix, `tolerateMissing`),
and the `TextDataLoader` class implementing `*ai:DataLoader` with `load()`.
