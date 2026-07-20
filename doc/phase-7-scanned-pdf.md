# Phase 7 — Scanned (Image-Only) PDF Detection

**Status:** ✅ Complete & verified (54/54 unit tests passing)
**Goal:** Stop scanned PDFs from silently producing **empty documents**. A scanned PDF is page
*images* wrapped in a PDF container — there is no text layer, and PDFBox extracts only the text
layer — so before this phase such a file parsed "successfully" and yielded an `ai:TextDocument`
with empty content, invisibly polluting downstream chunking/embedding. Ported from the Azure
**Files** loader.

---

## 1. Behavior

| Situation | Result |
|---|---|
| Scanned PDF **named explicitly** in `paths` | `ai:Error` — *"Failed to extract text from 'scan.pdf': the PDF has no extractable text layer (it appears to be a scanned/image-only document), and OCR is not supported"* |
| Scanned PDF **discovered in a prefix listing** | Skipped with a `log:printWarn` (like other non-text content); the walk continues |

This mirrors the loader's existing philosophy: explicitly naming an unreadable blob is an error
worth surfacing; encountering one while sweeping a folder prefix is a skip.

## 2. Implementation

- **`native/TextExtractor.java`** — after a successful parse by `PDFParser`, if the extracted
  text is empty (trimmed), return a descriptive error (`SCANNED_PDF_MESSAGE`) instead of the
  empty string. Detection is deliberately simple: parsed OK + zero text = image-only (or a
  genuinely blank PDF — equally unusable as text).
- **OCR fallback disabled explicitly** — Tika 3.x's `PDFParser` defaults to an *auto* OCR
  strategy: on image-only pages it reaches for its Tesseract integration, which is not shipped,
  and **NPEs** (`this.ocrParser is null`). `TextExtractor` sets
  `PDFParserConfig.OCR_STRATEGY.NO_OCR` in the `ParseContext`, so the parser returns cleanly and
  the empty-text detection above takes over. Removing this line reintroduces the NPE.
- **`ballerina/utils.bal`** — `isScannedPdfError` recognises the sentinel phrase
  (`"no extractable text layer"`), the same message-matching pattern as `isNotFoundError`.
- **`ballerina/blob_data_loader.bal`** — `listPrefix` catches a scanned-PDF error from
  `toDocument` and converts it to warn-and-skip; every other extraction error still aborts the
  listing, and the explicit-path branch in `loadPrefix` propagates the error unchanged (via
  `check buildDocument(...)`).

## 3. Tests & fixtures

- `tests/fixtures.bal` — `SCANNED_PDF_BYTES`: a hand-built one-page PDF containing a single
  image XObject and **no text operators** (structurally what a scanner produces); verified to
  parse with 0 extracted characters via PDFBox before being trusted.
- Unit tests: `testExtractTextFromScannedPdfErrors`, `testBuildDocumentScannedPdfErrors`,
  `testIsScannedPdfErrorRejectsOtherErrors`.
- Integration suite (`test-suite/`): `scanned.pdf` fixture (manifest `supported: false`) with
  `testNamedScannedPdfErrors` and `testScannedPdfSkippedInListing`.

## 4. Reading scanned PDFs for real (future work)

Detection tells you a scan exists; *reading* one needs OCR:
- **Tesseract via Tika** (`tika-parser-ocr-module` + the native `tesseract` binary installed on
  the host) — free/local, but a deployment burden for a library.
- **Azure AI Document Intelligence** — managed OCR, a natural fit for an Azure loader, at the
  cost of credentials, latency, and per-page pricing.

Neither is pure-Java; that is why the default posture is detect-and-report rather than OCR.
