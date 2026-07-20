# Phase 6 — Microsoft Office Text Extraction

**Status:** ✅ Complete & verified (54/54 unit tests passing; real extraction of PDF and all six
Office formats — `.docx/.xlsx/.pptx` and `.doc/.xls/.ppt`)
**Goal:** Extend the text-conversion layer to extract text from Microsoft Office documents
(`.doc/.docx`, `.ppt/.pptx`, `.xls/.xlsx`) via Apache POI, alongside the existing PDF (PDFBox)
support — replacing the previous behavior where Office formats were recognised only to be
skipped/rejected. Ported from the Azure **Files** loader, where the same design is already
proven; adapted here to the blob loader's flat-namespace/prefix semantics.

---

## 1. What changed

| Layer | Change |
|---|---|
| `native/TextExtractor.java` | Selects the Tika parser explicitly from the file extension — `PDFParser` (PDF), `OOXMLParser` (`.docx/.xlsx/.pptx`), `OfficeParser` (`.doc/.xls/.ppt`) — instead of only `PDFParser`; for extension-less names it falls back to the blob's `Content-Type` (see §2.4). |
| `native/build.gradle` | Compiles against `tika-parser-microsoft-module` in addition to `tika-core` + `tika-parser-pdf-module`. |
| `ballerina/Ballerina.toml` (+ `build-config` template) | Ships the POI runtime stack as platform dependencies: `tika-parser-microsoft-module`, `tika-parser-zip-commons`, `poi`, `poi-ooxml`, `poi-ooxml-lite`, `poi-scratchpad`, `xmlbeans`, `commons-collections4`, `commons-compress`, `SparseBitSet`, `log4j-api`, `log4j-core`. |
| `gradle.properties` | Adds the POI-stack version properties. |
| `ballerina/utils.bal` | `classify` now returns `EXTRACTABLE` for Office types (folded into `EXTRACTABLE_*`); the `UNSUPPORTED_OFFICE` `DocumentKind`, `isUnsupportedOfficeDocument`, and the `OFFICE_*` lists were removed. |
| `ballerina/blob_data_loader.bal` | Removed the now-dead Office-specific error (named path) and warn (prefix listing) branches. |
| Tests | `text_layer_test.bal` asserts Office → `EXTRACTABLE` (by extension **and** MIME type) and extracts real fixtures for all six formats; Office fixtures are read from `tests/resources/office-*.{docx,xlsx,pptx,doc,xls,ppt}`. |

Dependency versions match those bundled by the `ballerina/ai` module for Tika 3.2.2 (POI 5.4.1,
xmlbeans 5.3.0, …), i.e. a combination already proven compatible in the AI ecosystem.

### Blob-specific note: the MIME branch is live

Unlike Azure Files, Azure Blob Storage listings surface a real `Content-Type` for every blob, so
the MIME branch of `classify` actually fires here. The six Office MIME types therefore live in
`EXTRACTABLE_MIME_TYPES` (not only the extensions in `EXTRACTABLE_EXTENSIONS`), and the tests
cover MIME-based classification explicitly (`classify("noext", "application/msword")` etc.).

---

## 2. Two runtime realities that shaped the implementation — do NOT "simplify" these away

### 2.1 Explicit parser selection, not `AutoDetectParser`
The obvious implementation — `new AutoDetectParser()` — **fails at runtime** in a full Ballerina
process. `AutoDetectParser` eagerly instantiates *every* Tika parser registered on the classpath,
and in the full runtime one of those unrelated parsers fails to initialise against the
`commons-lang3` version **bundled inside the Ballerina runtime jar** (it calls
`SystemProperties.getUserName(String)`, absent from the runtime's older `commons-lang3` →
`NoSuchMethodError`). A platform-dependency `commons-lang3` cannot override the copy baked into
`ballerina-rt`, so the fix is to **not** load unrelated parsers at all: `selectParser` picks the
one parser the file needs. This keeps the loader working on the current distribution (2201.12.0)
with no runtime bump.

### 2.2 Embedded objects are not recursed into
Office documents can carry embedded objects (e.g. an OOXML **thumbnail**, OLE objects). POI's
parsers hand those to Tika's embedded-document extractor, which routes them through
`AutoDetectParser` + container detection — hitting the exact same `commons-lang3` failure as in
§2.1 (observed on a `.pptx` with a thumbnail). `TextExtractor` therefore installs a **no-op
`EmbeddedDocumentExtractor`** in the `ParseContext`, so parsing never recurses into embedded
content. This is both the fix and the desired behavior: we want the document's own text, not the
bytes of embedded thumbnails/attachments.

### 2.3 Office test fixtures are resource files, not base64 literals
The Office fixtures (~3.5–25 KB) exceed the size the Ballerina base64-literal tokenizer accepts
("invalid base64 content"; the smaller PDF fixtures stay inline). So `DOCX_BYTES`/`XLSX_BYTES`/
`PPTX_BYTES`/`DOC_BYTES`/`XLS_BYTES`/`PPT_BYTES` are read from
`tests/resources/office-*.{docx,xlsx,pptx,doc,xls,ppt}` via `io:fileReadBytes` at module init.

### 2.4 Parser selection is MIME-aware, not extension-only (blob-specific fix)
Because blob listings surface a real `Content-Type`, `classify` can mark an **extension-less**
blob EXTRACTABLE from its MIME type alone. If `selectParser` considered only the extension (as
the Azure Files reference does — harmless there, since Files listings carry no content type),
such a blob would fall through to `PDFParser`, fail to parse, and — worse — the non-sentinel
error would abort the entire prefix listing. `extractText` therefore takes the blob's
`Content-Type` as a third argument, and `selectParser` falls back to it when the name has no
recognised extension (OOXML MIME → `OOXMLParser`, legacy Office MIME → `OfficeParser`).
Covered by `testExtractTextOfficeByMimeTypeOnly`, `testExtractTextLegacyOfficeByMimeTypeOnly`,
and `testBuildDocumentOfficeByMimeTypeOnly`. This gap was caught by the independent post-port
review; classification and extraction must always agree on the same signals.

---

## 3. Behavior contract (unchanged shape, wider coverage)

- Office documents now extract to `ai:TextDocument`s exactly like PDFs — loaded in prefix
  listings (subject to `includeExtensions`) and when named explicitly.
- A named **image / archive / unknown binary** is still an error; the same blob in a listing is
  still skipped with a `log:printWarn`.
- Everything else in the loader (prefix walk, `isDirectChild` filtering, `"*"` containers,
  pagination, single-vs-array return) is untouched.

---

## 4. Verification

```bash
cd ballerina && bal test    # 54 passing, 0 failing
```

The `testExtractTextFrom{Docx,Xlsx,Pptx,Xls,Ppt}Bytes` cases prove the native POI path end-to-end
for all six Office formats (bytes → extracted text containing the fixture marker), and the
pre-existing PDF cases confirm the PDF path still works under explicit parser selection.

> The native jar is a git-ignored build artifact; `./gradlew build` regenerates it when the
> `packageUser`/`packagePAT` credentials are set. Without them, compile the class manually with
> `javac` against `ballerina-rt` + `tika-core` + `tika-parser-pdf-module` +
> `tika-parser-microsoft-module` (all present under `ballerina/target/platform-libs` after a
> `bal build`) and `jar` it to `native/build/libs/ai.azure.storage.blob-native-1.0.0.jar`.
