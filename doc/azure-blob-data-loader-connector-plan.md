# Plan — Azure Blob Data Loader (Connector-Based, v1)

A design + build plan for an `ai:DataLoader` that ingests documents from **Azure Blob Storage**, built on top of the existing **`ballerinax/azure_storage_service.blobs`** connector instead of a hand-built REST/XML/auth layer.

> This is the **connector-only** variant. It supersedes the hand-built acquisition design in [azure-blob-data-loader-plan.md](azure-blob-data-loader-plan.md) for v1. That document is retained as the reference for the from-scratch approach (and for a future AAD path).

> **Target package:** `ballerinax/ai.azure.storage.blob`
> **Reuses unchanged:** the whole text-extraction layer from `ballerinax/ai.microsoft.sharepoint` — `buildDocument` / `classify` / the native Apache **Tika** `TextExtractor`.
> **Delegates entirely:** the acquisition layer (auth, listing, download, pagination) to `ballerinax/azure_storage_service.blobs`.

---

## 1. Goal & Scope

Build a `TextDataLoader` that:

- Retrieves blobs from one or more Azure Blob **containers** and returns them as `ai:TextDocument` values.
- Implements `*ai:DataLoader`, so it drops into any Ballerina AI / RAG ingestion pipeline exactly like the SharePoint loader.
- Decodes inherently textual blobs directly and extracts **PDF** text via Apache Tika; skips (with a warning) non-text blobs, and errors on an explicitly-named unsupported blob.
- Returns a single `ai:Document` when exactly one blob resolves, an `ai:Document[]` otherwise.

**Non-goals (v1):** Azure AD / OAuth2 auth (see §9 — future), writing/uploading blobs, Office-format extraction (PDF only, same as SharePoint), blob snapshots/versions, page/append blob semantics beyond reading current content.

---

## 2. The connector — what it gives us for free

**Module:** `import ballerinax/azure_storage_service.blobs;` (v4.3.4)

The connector **is** the acquisition layer. It handles auth signing, request construction, XML parsing, and binary download so we don't have to.

| Need | Connector API | Returns |
|---|---|---|
| Auth | `ConnectionConfig { accountName, accessKeyOrSAS, authorizationMethod }` | — |
| List blobs (paged) | `listBlobs(containerName, maxResults?, marker?, prefix?)` | `ListBlobResult { blobList: Blob[], nextMarker: string, responseHeaders }` |
| List containers (paged) | `listContainers(maxResults?, marker?, prefix?)` | `ListContainerResult { containerList: Container[], nextMarker, responseHeaders }` |
| Download blob | `getBlob(containerName, blobName, byteRange?)` | `BlobResult { blobContent: byte[], properties, responseHeaders }` |
| Blob exists / props | `getBlobProperties(containerName, blobName)` | `ResponseHeaders \| Error` |

Key record shapes:

```ballerina
public type Blob record { string Name; map<json> Properties; string Snapshot?; ... };
public type BlobResult record {| byte[] blobContent; ResponseHeaders responseHeaders; Properties properties; |};
public type ListBlobResult record {| Blob[] blobList; string nextMarker; ResponseHeaders responseHeaders; |};
```

Notes / gotchas:
- **`Blob.Properties` is `map<json>`**, not a typed record. Read `Content-Type`, `Content-Length`, `Creation-Time`, `Last-Modified` by key.
- **`getBlob().blobContent` is already `byte[]`** — no `getBinaryPayload()` content-negotiation pitfall (unlike the SharePoint raw-HTTP path).
- **No `delimiter` parameter** on `listBlobs` — recursion into virtual folders is controlled client-side (§6).
- **Pagination** is exposed via `nextMarker` (empty string on last page) — loop, re-calling with `marker`.

---

## 3. Authentication (v1)

Two mechanisms, both native to the connector — **no signing or header code on our side**:

1. **SAS token** — a scoped, time-limited pre-signed query-string token. Set `authorizationMethod: SAS`, pass the token as `accessKeyOrSAS`.
2. **Shared Key (Access Key)** — the account master key; the connector performs HMAC-SHA256 signing internally. Set `authorizationMethod: ACCESS_KEY`, pass the key as `accessKeyOrSAS`.

> **Azure AD / OAuth2 is intentionally out of scope for v1** — the connector does not support Bearer auth. See §9 for how it would be added later without disturbing this design.

---

## 4. What we reuse from the SharePoint module (do NOT rebuild)

The text-conversion half is service-agnostic and copies over verbatim:

| Reusable asset | File | Notes |
|---|---|---|
| `buildDocument(content, name, mime, size, created, modified)` | `utils.bal` | Byte-array → `ai:TextDocument`. **No change.** |
| `classify` + `DocumentKind` enum | `utils.bal` | PLAIN_TEXT / EXTRACTABLE (PDF) / UNSUPPORTED_OFFICE / UNSUPPORTED. **No change.** |
| `TEXT_*`, `EXTRACTABLE_*`, `OFFICE_*` constant lists | `utils.bal` | **No change.** |
| `extractText` external fn + `TextExtractor.java` (Tika PDFParser) | `utils.bal` / native | **No change.** In-memory bytes; no temp file. |
| Helpers: `getExtension`, `matchesExtensionFilter`, `toUtc`, `dedupeStrings`, `isUnsupportedOfficeDocument` | `utils.bal` | Copy as-is. |
| Native-image config + Tika/PDFBox platform deps in `Ballerina.toml` | native + toml | Copy the `[[platform.java21.dependency]]` block wholesale. |

**Dropped SharePoint/Graph specifics:** `normalizeSiteId`, `@odata.nextLink` pagination, `collectWebPartText`/`htmlToText`/site-pages, `encodeDrivePath`, `originOf`, `relativeUrl`, and the raw `http:Client` sites/pages plumbing — all replaced by the connector.

---

## 5. Public API (`types.bal`)

```ballerina
# Authentication + connection configuration for Azure Blob Storage.
public type ConnectionConfig record {|
    # Storage account name.
    string accountName;
    # Access key (Shared Key) or SAS token, per `authorizationMethod`.
    string accessKeyOrSAS;
    # Whether `accessKeyOrSAS` is an account access key or a SAS token.
    AuthorizationMethod authorizationMethod;
    # Standard HTTP options forwarded to the connector (timeout, httpVersion, retryConfig, ...).
|};

public enum AuthorizationMethod {
    ACCESS_KEY,
    SAS
}

# One container to read from (a container IS the drive; no site->library chain).
public type Source record {|
    # Container name, or "*" for every container in the account.
    string container;
    # Blob-name prefixes / virtual-folder paths (e.g. "/reports"). Default whole container.
    string[] paths = ["/"];
    # Traverse virtual sub-folders (list without a folder boundary). Default false.
    boolean recursive = false;
    # Case-insensitive extension allowlist for prefix listings. Default all.
    string[]? includeExtensions = ();
|};

# Internal normalized listing entry (decoupled from connector's `Blob`).
type BlobEntry record {|
    string name;
    string? contentType;
    decimal? contentLength;
    string? creationTime;
    string? lastModified;
|};
```

`ConnectionConfig` maps directly onto the connector's own config — we re-expose it (rather than accept the connector type raw) to keep our public surface stable and AI-loader-idiomatic, and to leave room to add an AAD variant later without a breaking change.

---

## 6. Architecture — single backend

```
load() / loadPrefix()   ──►   blobs:Client   (ballerinax/azure_storage_service.blobs)
        │                        listBlobs · getBlob · listContainers · getBlobProperties
        ▼
   buildDocument / classify / Tika TextExtractor    ← copied verbatim from SharePoint
```

No `BlobBackend` interface, no `RestBackend`, no XML helpers — the connector returns typed records and `byte[]` directly.

### Recursion (no `delimiter`)
- **`recursive: true`** → `listBlobs(container, prefix=<path>)` and keep every returned blob (Azure lists all depths under a prefix by default).
- **`recursive: false`** → same call, then a **client-side filter**: keep a blob only if `blob.Name` with the prefix stripped contains no further `/` (i.e. it lives directly under the prefix, not in a sub-"folder").

### Pagination
`listBlobs` / `listContainers` loop while `nextMarker != ""`, re-calling with `marker: nextMarker`, accumulating results.

---

## 7. `load()` algorithm

```
for each Source src:
    containers = resolveContainers(src.container)      // [name] or all (paged listContainers) when "*"
    tolerateMissing = src.container == "*"
    for each container:
        for each rawPath in src.paths:
            prefix = normalizeBlobPath(rawPath)         // "" for root, else "reports/x"
            docs = loadPrefix(client, container, prefix, src.recursive,
                              src.includeExtensions, tolerateMissing)
            documents.push(...docs)
return documents.length() == 1 ? documents[0] : documents
```

`loadPrefix`:
1. **Explicit-blob check** — if `prefix` doesn't end in `/` and `getBlobProperties(container, prefix)` returns 200, it's an explicitly-named file → `toDocument`; if unsupported → **error** (format-specific message for Office).
2. Otherwise treat as a **prefix (folder)** → paged `listBlobs(container, prefix)` → for each blob: apply the recursion filter (§6) and `matchesExtensionFilter`, then `toDocument`, and **skip with a warning** on unsupported/Office (never error inside a listing).
3. `tolerateMissing` + a 404 / empty listing → return `[]` (the `"*"` case).

`toDocument(client, container, blobName, entryProps)`:
- `BlobResult r = check client->getBlob(container, blobName, ());`
- Read `Content-Type` / `Content-Length` / `Creation-Time` / `Last-Modified` from the `map<json>` properties (list entry or `r.properties`).
- `buildDocument(r.blobContent, blobName, contentType, contentLength, creationTime, lastModified)`.

---

## 8. File / component plan

```
module-ballerinax-ai.loader.azureblob/          (repo dir; package is ai.azure.storage.blob)
├── ballerina/
│   ├── blob_data_loader.bal   ← new TextDataLoader class
│   ├── types.bal              ← ConnectionConfig, AuthorizationMethod, Source, BlobEntry
│   ├── utils.bal              ← reused text layer + resolveContainers/listing/recursion helpers
│   ├── Ballerina.toml         ← Tika/PDFBox platform deps + azure_storage_service.blobs dependency
│   └── tests/
│       ├── mock_service.bal   ← (optional) or test against connector with a mock/live account
│       ├── fixtures.bal
│       └── loader_test.bal
├── native/                    ← copy TextExtractor.java + native-image config, package-renamed
│   └── src/main/java/io/ballerina/lib/ai/azure/storage/blob/TextExtractor.java
├── build.gradle / settings.gradle / gradle.properties  ← copy, rename artifacts
└── README.md
```

Package renames: `ai.microsoft.sharepoint` → `ai.azure.storage.blob`; Java package `io.ballerina.lib.ai.microsoft.sharepoint` → `io.ballerina.lib.ai.azure.storage.blob`; native jar artifactId; native-image config directory name.

---

## 9. Future: adding Azure AD (post-v1)

When AAD is needed, the connector can't carry it (SAS/Shared Key only). Add it **behind an internal `BlobBackend` interface** so `load()` stays transport-agnostic:
- `ConnectorBackend` — wraps `blobs:Client` (this v1 code).
- `RestBackend` — raw `http:Client` with `Authorization: Bearer` + `x-ms-version`, XML `List Blobs` parsing, `NextMarker` pagination (the design already captured in the original hand-built plan).

Both normalize into `BlobEntry` / `byte[]`, so nothing above the interface changes. This is why §5 wraps the connector config rather than exposing it raw.

---

## 10. Testing plan

- Fixtures: a text blob, a PDF (Tika path), an Office blob (skip/error path), a binary (skip), nested prefixes for recursion, a `"*"` container case.
- Cases: root load, prefix load, recursive vs non-recursive (client-side filter), extension filter, explicit-blob-always-loaded, explicit-unsupported → error, folder-unsupported → skip+warn, single-doc vs array return, `nextMarker` pagination (multi-page listing), `"*"` container with `tolerateMissing`, SAS vs ACCESS_KEY auth wiring.
- Approach: mock the Blob REST endpoints the connector calls (XML + bytes), or run against a test storage account. Model fixtures on the SharePoint `tests/` layout.

---

## 11. Usage example (target API)

```ballerina
import ballerina/ai;
import ballerinax/ai.azure.storage.blob;

final blob:TextDataLoader loader = check new (
    {
        accountName: "contosostorage",
        accessKeyOrSAS: "sv=2022-11-02&ss=b&srt=co&sp=rl&sig=...",
        authorizationMethod: blob:SAS
    },
    [
        {
            container: "documents",
            paths: ["/policies/leave-policy.pdf", "/onboarding"],
            recursive: true,
            includeExtensions: ["pdf"]
        },
        {
            container: "specs",
            paths: ["/api-design.md"]
        }
    ]
);

public function main() returns error? {
    ai:Document[]|ai:Document docs = check loader.load();
    // chunk -> embed -> index ...
}
```

---

## 12. Build phases / checklist

- [ ] **Phase 0 — Scaffold.** Copy repo structure; rename package/org/Java package/artifacts; copy `TextExtractor.java` + native-image config + Tika platform deps; add `ballerinax/azure_storage_service.blobs` to `Ballerina.toml`; empty package builds on GraalVM.
- [ ] **Phase 1 — Text layer.** Copy `buildDocument`/`classify`/constants/`extractText`; unit-test PDF + text extraction from raw bytes.
- [ ] **Phase 2 — Types.** `ConnectionConfig`, `AuthorizationMethod`, `Source`, `BlobEntry`; client init from config.
- [ ] **Phase 3 — Loader.** `resolveContainers`, paged `listBlobs`, client-side recursion filter, `toDocument`, `loadPrefix`, `load()`; explicit-blob-vs-prefix; `tolerateMissing`; single/array return.
- [ ] **Phase 4 — Tests.** Fixtures + all cases in §10.
- [ ] **Phase 5 — Docs.** `README.md` + module docs (auth table, container/prefix model, filtering, examples).

---

## 13. Open decisions

1. **Repo:** use this repo (`module-ballerinax-ai.loader.azureblob`) — package name `ai.azure.storage.blob`. *(Confirmed.)*
2. **v1 auth:** SAS + Shared Key via the connector; AAD deferred. *(Confirmed.)*
3. **Connection-string convenience?** Optionally parse `AccountName`/`AccountKey`/`SharedAccessSignature` out of a single connection string into `ConnectionConfig`. *(Nice-to-have; defer.)*
