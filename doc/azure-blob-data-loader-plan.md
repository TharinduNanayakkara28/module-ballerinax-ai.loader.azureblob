# Plan — Ballerina Azure Blob Storage Data Loader

A design + build plan for an `ai:DataLoader` that ingests documents from **Azure Blob Storage**, modelled directly on the existing `ballerinax/ai.microsoft.sharepoint` `TextDataLoader`.

> **Target package:** `ballerinax/ai.azure.storage.blob` (new sibling module, same repo layout as the SharePoint one).
> **Reuses unchanged:** the whole text-extraction layer — `buildDocument` / `classify` / the native Apache **Tika** `TextExtractor`. Only the *acquisition* layer (auth, listing, download) is new.

---

## 1. Goal & Scope

Build a `TextDataLoader` that:

- Retrieves blobs from one or more Azure Blob **containers** and returns them as `ai:TextDocument` values.
- Implements `*ai:DataLoader`, so it drops into any Ballerina AI / RAG ingestion pipeline exactly like the SharePoint loader.
- Decodes inherently textual blobs directly and extracts **PDF** text via Apache Tika; skips (with a warning) non-text blobs, and errors on an explicitly-named unsupported blob.
- Returns a single `ai:Document` when exactly one blob resolves, an `ai:Document[]` otherwise.

**Non-goals (v1):** writing/uploading blobs, Office-format extraction (same limitation as SharePoint — PDF only), blob snapshots/versions, page/append blob semantics beyond reading current content.

---

## 2. What we reuse from the SharePoint module (do NOT rebuild)

The SharePoint loader cleanly separates **acquisition** from **text conversion**. The conversion half is service-agnostic and copies over verbatim:

| Reusable asset | File | Notes |
|---|---|---|
| `buildDocument(content, name, mime, size, created, modified)` | `utils.bal` | Byte-array → `ai:TextDocument`, MIME/extension driven. **No change.** |
| `classify` + `DocumentKind` enum | `utils.bal` | PLAIN_TEXT / EXTRACTABLE (PDF) / UNSUPPORTED_OFFICE / UNSUPPORTED. **No change.** |
| `TEXT_*`, `EXTRACTABLE_*`, `OFFICE_*` constant lists | `utils.bal` | **No change.** |
| `extractText` external fn + `TextExtractor.java` (Tika PDFParser) | `utils.bal` / native | **No change.** Reads in-memory bytes; no temp file. |
| Helpers: `getExtension`, `matchesExtensionFilter`, `toUtc`, `dedupeStrings`, `isUnsupportedOfficeDocument`, `originOf`, `relativeUrl` | `utils.bal` | Copy as-is. |
| Native-image config + Tika/PDFBox platform deps in `Ballerina.toml` | native + toml | Copy the `[[platform.java21.dependency]]` block wholesale. |

**What must be rewritten** (SharePoint/Graph-specific): the `TextDataLoader` class body, `types.bal` (config + Source model), auth handling, listing, pagination, path normalization. Graph specifics to drop: `normalizeSiteId`, `@odata.nextLink` JSON pagination, `collectWebPartText`/`htmlToText`/site-pages, `encodeDrivePath` (Graph `root:` addressing).

---

## 3. Azure Blob Storage domain model

```
Storage Account  (https://<account>.blob.core.windows.net)
   └── Container            ← analogous to a SharePoint "Library"/drive
        └── Blob            ← a file; name may contain "/" giving virtual folders
             e.g.  reports/2026/q1.pdf
```

- **No real folders.** Hierarchy is simulated by `/` in blob names plus the `delimiter` list parameter.
- **List Blobs** REST call returns **XML** (not JSON — the biggest structural difference from Graph):
  `GET https://<account>.blob.core.windows.net/<container>?restype=container&comp=list`
  Query params used: `prefix`, `delimiter`, `marker`, `maxresults`, `include`.
- **List Containers:** `GET https://<account>.blob.core.windows.net/?comp=list` (for a `"*"`-style all-containers option).
- **Download blob:** `GET https://<account>.blob.core.windows.net/<container>/<blob-name>` → raw bytes + headers.
- **Required header on every request:** `x-ms-version: 2021-12-02` (or newer).
- **Metadata sources:** response headers `Content-Type`, `Content-Length`, `Last-Modified`, `x-ms-creation-time`; and per-blob `<Properties>` in the list XML.

### List Blobs response shape (XML)
```xml
<EnumerationResults>
  <Blobs>
    <Blob>
      <Name>reports/q1.pdf</Name>
      <Properties>
        <Creation-Time>...</Creation-Time>
        <Last-Modified>...</Last-Modified>
        <Content-Length>12345</Content-Length>
        <Content-Type>application/pdf</Content-Type>
      </Properties>
    </Blob>
    <BlobPrefix><Name>reports/subfolder/</Name></BlobPrefix>  <!-- only when delimiter set -->
  </Blobs>
  <NextMarker>...</NextMarker>   <!-- pagination cursor; empty on last page -->
</EnumerationResults>
```

### Recursion maps naturally onto `delimiter`
- **`recursive: true`** → list with `prefix=<path>` and **no delimiter** → every blob under the prefix at any depth, in one (paginated) sweep.
- **`recursive: false`** → list with `prefix=<path>` and `delimiter="/"` → only blobs directly under the prefix; `<BlobPrefix>` entries (sub-"folders") are ignored.

---

## 4. Key differences & challenges vs SharePoint

| Aspect | SharePoint (Graph) | Azure Blob | Impact |
|---|---|---|---|
| List response format | JSON | **XML** | Add XML parsing (`ballerina/data.xmldata` or built-in `xml`). New helper set replacing `valuesOf`/`nextLinkOf`/`strField`. |
| Pagination | `@odata.nextLink` (absolute URL) | `NextMarker` (opaque cursor → re-issue with `marker=`) | Different loop; simpler (no origin/relative-URL dance). |
| Auth | OAuth2 (Graph) / Bearer | **SAS token**, **Azure AD OAuth2/Bearer**, (optional) **Shared Key HMAC** | SAS = append query string; AAD = `http:Client` `auth` like today + `x-ms-version`; Shared Key needs per-request HMAC signing (hard — see §6). |
| Container listing | `/sites/{id}/drives` | `/?comp=list` | Only needed for the `"*"` all-containers option. |
| Path addressing | `root:/path/to/item` colon syntax | plain `/<container>/<blob>` URL | Simpler; encode each segment, keep `/`. |
| Site pages | web-part extraction | **none** | Drop `pages`, `collectWebPartText`, `htmlToText`. |
| "Folder" detection | `driveItem.folder` facet | no facet — infer from `/` + `delimiter` | Explicit-blob vs prefix disambiguation (§7). |

---

## 5. Proposed public API (`types.bal`)

```ballerina
# Authentication for Azure Blob Storage.
public type BlobAuthConfig
    SasTokenConfig
    | http:BearerTokenConfig                       // pre-obtained AAD token
    | AzureAdOAuth2ClientCredentialsGrantConfig;    // AAD app-only (scope https://storage.azure.com/.default)

# A Shared Access Signature (query-string token, with or without leading '?').
public type SasTokenConfig record {|
    string sasToken;
|};

# AAD client-credentials grant defaulted to the Azure Storage resource scope.
public type AzureAdOAuth2ClientCredentialsGrantConfig record {|
    *http:OAuth2ClientCredentialsGrantConfig;
    string tokenUrl = "https://login.microsoftonline.com/common/oauth2/v2.0/token";
    string[] scopes = ["https://storage.azure.com/.default"];
|};

# Connection + HTTP configuration (mirrors SharePoint ConnectionConfig field-for-field
# for the HTTP-level options; auth + endpoint differ).
public type ConnectionConfig record {|
    BlobAuthConfig auth;
    # Storage account name; used to build the default endpoint.
    string accountName;
    # Blob service endpoint. Defaults to https://<accountName>.blob.core.windows.net
    string serviceUrl?;
    # REST API version header value.
    string apiVersion = "2021-12-02";
    # ... identical HTTP block copied from SharePoint ConnectionConfig:
    # httpVersion, http1Settings, http2Settings, timeout, forwarded, followRedirects,
    # poolConfig, cache, compression, circuitBreaker, retryConfig, cookieConfig,
    # responseLimits, secureSocket, proxy, socketConfig, validation, laxDataBinding
|};

# One container to read from (analogous to SharePoint `Source` + `Library` merged,
# since a container IS the drive).
public type Source record {|
    # Container name, or "*" for every container in the account.
    string container;
    # Blob-name prefixes / virtual-folder paths (e.g. "/reports"). Default whole container.
    string[] paths = ["/"];
    # Traverse virtual sub-folders (drop the delimiter). Default false.
    boolean recursive = false;
    # Case-insensitive extension allowlist for prefix listings. Default all.
    string[]? includeExtensions = ();
|};
```

**Design choice:** Azure has one fewer level than SharePoint (no site → library → drive chain; a container *is* the drive), so `Source` and `Library` collapse into a single `Source`. Keep the `"*"` wildcard + `tolerateMissing` semantics for the all-containers case.

---

## 6. Authentication strategy (detail)

Support, in priority order:

1. **SAS token** *(simplest, ship first)* — append the token query string to every request URL. No `Authorization` header, no signing. Just handle the leading `?`.
2. **Azure AD OAuth2 (client credentials) + Bearer token** — reuse the exact `http:Client` `auth` mechanism the SharePoint loader already uses; the HTTP layer attaches `Authorization: Bearer`. Requires scope `https://storage.azure.com/.default` and the `x-ms-version` header (added as a default header on the client / per request).
3. **Shared Key (account name + key)** *(optional / phase 4 — hardest)* — requires per-request `Authorization: SharedKey <account>:<sig>` where `sig = base64(HMAC-SHA256(key, StringToSign))`, and `StringToSign` is the canonicalized verb + headers + `x-ms-*` headers + canonicalized resource. **Recommend implementing the HMAC signing in the native Java layer** (alongside `TextExtractor`) rather than in Ballerina, and treat it as a stretch goal. If time-boxed, ship v1 with SAS + AAD only.

`x-ms-version` must be sent on **every** request → set it as a default header on the raw `http:Client`, or add it explicitly in each call.

---

## 7. `load()` algorithm

```
for each Source src:
    containers = resolveContainers(src.container)      // ["name"] or all when "*"
    tolerateMissing = src.container == "*"
    for each container:
        for each rawPath in src.paths:
            prefix = normalizeBlobPath(rawPath)         // "" for root, else "reports/x"
            docs = loadPrefix(container, prefix, src.recursive,
                              src.includeExtensions, tolerateMissing)
            documents.push(...docs)
return documents.length()==1 ? documents[0] : documents
```

`loadPrefix`:
1. **Explicit-blob check** (mirror SharePoint's "explicit file always loaded, error if unsupported"): if `prefix` doesn't end in `/` and an exact blob with that name exists (a `GET`/`HEAD` returns 200), treat it as an explicitly-named file → download + `toDocument`; if unsupported → **error** (format-specific message for Office).
2. Otherwise treat as a **prefix (folder)**: `listBlobs(container, prefix, recursive)` → for each blob, apply `matchesExtensionFilter`, download via `toDocument`, and **skip with a warning** on unsupported/Office (never error inside a listing).
3. `tolerateMissing` + a 404 / empty listing → return `[]` instead of erroring (the `"*"` container case).

`toDocument` (≈ copy of SharePoint's): `GET /<container>/<blob>` → read `getBinaryPayload()` (not typed `byte[]` — same content-negotiation pitfall) → check status ≥ 400 explicitly → `buildDocument(bytes, name, contentTypeHeader, contentLength, creationTime, lastModified)`.

---

## 8. Listing & pagination (new XML helpers in `utils.bal`)

Replace the JSON OData helpers with XML equivalents:

- `listBlobs(container, prefix, recursive) → BlobEntry[]`
  - build query: `restype=container&comp=list&prefix=<enc>` + `&delimiter=/` when `!recursive` + `&marker=<m>` on subsequent pages.
  - parse XML `<EnumerationResults>`; collect `<Blob>` (Name + Properties); read `<NextMarker>`; loop until empty.
- New helper set (analogues of `valuesOf`/`nextLinkOf`/`strField`):
  - `blobsOf(xml) → BlobEntry[]`, `nextMarkerOf(xml) → string?`, `xmlText(element, tag) → string?`.
- New record:
  ```ballerina
  type BlobEntry record {| string name; string? contentType; decimal? contentLength;
                           string? creationTime; string? lastModified; |};
  ```
- XML parsing via `ballerina/data.xmldata` (`xmldata:parseString`/`fromXml`) or the built-in `xml` type with `re`/`xml` navigation. Prefer `data.xmldata` bound to `BlobEntry`-shaped records for robustness.

Segment encoding: reuse a `url:encode`-per-segment helper (like `encodeDrivePath`) but for `/<container>/<blob>` — keep `/` between segments, encode each.

---

## 9. File / component plan (mirror the existing repo)

```
module-ballerinax-ai.azure.storage.blob/
├── ballerina/
│   ├── blob_data_loader.bal      ← new TextDataLoader class (based on sharepoint_data_loader.bal)
│   ├── types.bal                 ← ConnectionConfig, BlobAuthConfig, Source, BlobEntry
│   ├── utils.bal                 ← reused text layer + NEW xml/list/auth helpers
│   ├── Ballerina.toml            ← copy Tika/PDFBox platform deps; new org/name/keywords
│   └── tests/
│       ├── mock_service.bal      ← XML-returning mock of the Blob REST API
│       ├── fixtures.bal
│       └── loader_test.bal
├── native/                       ← copy TextExtractor.java (+ optional SharedKeySigner.java)
│   └── src/main/java/io/ballerina/lib/ai/azure/storage/blob/TextExtractor.java
│       (+ native-image META-INF config, package-renamed)
├── build.gradle / settings.gradle / gradle.properties  ← copy, rename artifacts
└── README.md
```

Package renames to apply everywhere: `ai.microsoft.sharepoint` → `ai.azure.storage.blob`; Java package `io.ballerina.lib.ai.microsoft.sharepoint` → `io.ballerina.lib.ai.azure.storage.blob`; native jar artifactId; native-image config directory name.

---

## 10. Testing plan

- **Mock service** (`http:Service`) returning canned **XML** for `?comp=list` (with/without `delimiter`, with a `NextMarker` page to exercise pagination) and raw bytes for blob GETs. Model it on `tests/mock_service.bal` but XML-flavored.
- Fixtures: a text blob, a PDF (Tika path), an Office blob (skip/error path), a binary (skip), nested prefixes for recursion, a `"*"` container case.
- Cases to cover:
  - root load, prefix load, recursive vs non-recursive, extension filter, explicit-blob-always-loaded, explicit-unsupported → error, folder-unsupported → skip+warn, single-doc vs array return, pagination via `NextMarker`, `"*"` container with `tolerateMissing`, SAS vs AAD auth wiring.

---

## 11. Configuration reference (v1)

**ConnectionConfig** — `auth`, `accountName`, `serviceUrl?` (default `https://<accountName>.blob.core.windows.net`), `apiVersion` (default `2021-12-02`), plus the full HTTP block copied from the SharePoint `ConnectionConfig`.

**Source** — `container` (or `"*"`), `paths` (default `["/"]`), `recursive` (default `false`), `includeExtensions` (default `()`).

---

## 12. Usage example (target API)

```ballerina
import ballerina/ai;
import ballerinax/ai.azure.storage.blob;

final blob:TextDataLoader loader = check new (
    {
        accountName: "contosostorage",
        auth: { sasToken: "sv=2022-11-02&ss=b&srt=co&sp=rl&sig=..." }
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
    // chunk → embed → index ...
}
```

---

## 13. Build phases / checklist

- [ ] **Phase 0 — Scaffold.** Copy repo structure; rename package/org/Java package/artifacts; copy `TextExtractor.java` + native-image config + Tika platform deps; get an empty package building on GraalVM.
- [ ] **Phase 1 — Text layer.** Copy `buildDocument`/`classify`/constants/`extractText`; unit-test PDF + text extraction from raw bytes.
- [ ] **Phase 2 — Types.** Define `ConnectionConfig`, `BlobAuthConfig` (SAS + AAD first), `Source`, `BlobEntry`; endpoint + `x-ms-version` wiring in `toHttpClientConfig`.
- [ ] **Phase 3 — Listing + download.** Implement `resolveContainers`, `listBlobs` (XML parse + `NextMarker` pagination + `delimiter` recursion), `toDocument`, `loadPrefix`, `load()`; explicit-blob vs prefix disambiguation; `tolerateMissing`.
- [ ] **Phase 4 — Tests.** XML mock service + fixtures + all cases in §10.
- [ ] **Phase 5 (optional) — Shared Key auth.** Native HMAC-SHA256 signer + `StringToSign` canonicalization.
- [ ] **Phase 6 — Docs.** `README.md` + module docs mirroring the SharePoint one (auth table, container/prefix model, filtering, examples).

---

## 14. Open decisions (confirm before Phase 2)

1. **Auth set for v1:** SAS + Azure AD only, with Shared Key deferred? *(Recommended.)*
2. **Package name:** `ai.azure.storage.blob` vs `ai.azure.blob`.
3. **New repo** vs adding a second loader into the current SharePoint repo. *(Separate repo recommended — matches the one-service-per-module convention.)*
4. **XML binding approach:** `ballerina/data.xmldata` record binding vs manual `xml` navigation.
5. **Connection-string support?** (Parse `AccountName`/`AccountKey`/`SharedAccessSignature` out of a single connection string as a convenience — depends on decision #1.)
```
