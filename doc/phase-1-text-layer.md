# Phase 1 — Text-Conversion Layer

**Status:** ✅ Complete & verified (21/21 unit tests passing)
**Goal:** Port the service-agnostic text-conversion layer from the SharePoint module
(`buildDocument` / `classify` / format constants / native `extractText`) into
`ballerinax/ai.azure.storage.blob`, and unit-test PDF + plain-text extraction from raw
bytes — with **no HTTP, no connector, no mock service** (that is Phase 3).

---

## 1. What was built

`ballerina/utils.bal` now holds the text layer, copied **verbatim** from the SharePoint
`utils.bal` except for two Azure-specific edits:
- The `extractText` external binding points at the renamed Java class
  `io.ballerina.lib.ai.azure.storage.blob.TextExtractor` (Phase 0's native jar).
- Doc comments say "blob" instead of "SharePoint file".

The Phase 0 placeholder `blob_data_loader.bal` (which only held a throwaway `API_VERSION`
const to make the empty package compile) was **removed** — `utils.bal` now provides the
module's real content.

### Functions & types ported
| Symbol | Role |
|---|---|
| `enum DocumentKind` | `PLAIN_TEXT` / `EXTRACTABLE` / `UNSUPPORTED_OFFICE` / `UNSUPPORTED` |
| `buildDocument(content, fileName, mimeType, fileSize, created, modified)` | byte[] → `ai:TextDocument?` \| `ai:Error`; the entry point |
| `classify(fileName, mimeType)` | MIME-then-extension routing to a `DocumentKind` |
| `extractText(content, fileName)` | `external` → native Apache Tika PDF extractor |
| `isUnsupportedOfficeDocument(fileName, mimeType)` | Office-format predicate |
| `getExtension(fileName)` | lower-cased extension without the dot |
| `matchesExtensionFilter(fileName, includeExtensions)` | case-insensitive, dot-tolerant allowlist; `()`/`[]` = all |
| `toUtc(dateTime)` | ISO 8601 → `time:Utc?` (drops unparseable) |
| `TEXT_*`, `EXTRACTABLE_*`, `OFFICE_*` constant lists | classification tables |

### Imports
Only `ballerina/ai`, `ballerina/jballerina.java`, `ballerina/time`. The SharePoint
`utils.bal` also imported `ballerina/http` and `ballerina/url` for the **acquisition**
helpers — those helpers (`toHttpClientConfig`, `encodeDrivePath`, OData `valuesOf`/
`nextLinkOf`/`strField`, `originOf`/`relativeUrl`, `normalizeSiteId`, `normalizePath`,
`collectWebPartText`/`htmlToText`, `isNotFoundError`) were **not** ported here.

---

## 2. What was intentionally NOT ported

| SharePoint helper | Why skipped |
|---|---|
| `toHttpClientConfig` | HTTP-client wiring — the connector owns this now (Phase 3 maps our `ConnectionConfig` to the connector's). |
| `encodeUri` / `encodeDrivePath` | Graph `root:/path` addressing — connector builds blob URLs. |
| `valuesOf` / `nextLinkOf` / `strField` | OData JSON parsing — connector returns typed records. |
| `originOf` / `relativeUrl` | `@odata.nextLink` absolute-URL dance — connector paginates via `nextMarker`. |
| `normalizeSiteId` | Graph site addressing — no analogue for blobs. |
| `normalizePath` | OneDrive path shape — Phase 3 adds a blob-prefix variant. |
| `collectWebPartText` / `htmlToText` | SharePoint site pages — dropped feature. |
| `isNotFoundError` | HTTP 404 detection — Phase 3 handles connector errors / `tolerateMissing`. |
| `dedupeStrings` | Only used to de-dup container names in `resolveContainers` — Phase 3. |

These arrive (or are replaced) when the acquisition layer lands in Phase 3.

---

## 3. Tests

Two test files under `ballerina/tests/`:

- **`fixtures.bal`** — the verified PDFBox-generated `PDF_BYTES` (base64) whose Tika-extracted
  text contains the marker `PDF_TEXT = "Mock PDF document text."`. Reused as-is from SharePoint.
- **`text_layer_test.bal`** — 21 focused unit tests calling the ported functions directly
  on raw bytes (no HTTP, no mock).

### Coverage
| Area | Tests |
|---|---|
| `getExtension` | basic, lower-casing, multi-dot, no-dot, path-with-no-dot |
| `classify` | plain-text by extension, plain-text by MIME, PDF extractable, Office (by ext + MIME), unsupported binary/extensionless |
| `isUnsupportedOfficeDocument` | Office true; PDF/text false |
| `matchesExtensionFilter` | `()`/`[]` matches all; allowlist hit/miss; case-insensitive; leading-dot tolerant |
| `toUtc` | valid ISO 8601; `()`; unparseable → `()` |
| `extractText` (native Tika) | PDF bytes → text contains `PDF_TEXT` |
| `buildDocument` plain-text | content decoded; `fileName`/`mimeType`/`fileSize` metadata |
| `buildDocument` timestamps | valid `createdAt`/`modifiedAt` populated; unparseable dropped (non-fatal) |
| `buildDocument` invalid UTF-8 | surfaces `ai:Error` "Failed to decode text" |
| `buildDocument` PDF | extracts text; PDF metadata |
| `buildDocument` skip paths | image → `()`; Office → `()` |

### Result
```
cd ballerina && bal test
→ 21 passing, 0 failing, 0 skipped
```
Notably `testExtractTextFromPdfBytes` and `testBuildDocumentPdfExtractsText` pass, proving
the Phase 0 native jar (renamed Java package) links and runs through Ballerina's JNI binding.

> Test-only usage note: the ported functions are module-private and are exercised only by
> the test files. Ballerina treats `tests/` as part of the same module, so this counts as
> usage — the package compiles clean with no unused-symbol issues.

---

## 4. Files touched

| File | Change |
|---|---|
| `ballerina/utils.bal` | **New** — the ported text layer. |
| `ballerina/blob_data_loader.bal` | **Removed** — Phase 0 placeholder. |
| `ballerina/tests/fixtures.bal` | **New** — PDF fixture + marker. |
| `ballerina/tests/text_layer_test.bal` | **New** — 21 unit tests. |

---

## 5. Phase 1 checklist

- [x] Port `buildDocument` / `classify` / `extractText` / constants (+ `getExtension`,
      `matchesExtensionFilter`, `isUnsupportedOfficeDocument`, `toUtc`).
- [x] Repoint `extractText` at the renamed native Java class.
- [x] Remove the Phase 0 placeholder module.
- [x] Unit-test plain-text decode, PDF (Tika) extraction, Office/binary skip, filter,
      classification, timestamps — from raw bytes.
- [x] `bal test` green (21/21).

**Next:** Phase 2 — define the public API in `types.bal`: `ConnectionConfig`
(`accountName`, `accessKeyOrSAS`, `authorizationMethod`), the `AuthorizationMethod` enum,
`Source` (`container`, `paths`, `recursive`, `includeExtensions`), and the internal
`BlobEntry`; wire client construction from the config (mapped to the connector's config).
