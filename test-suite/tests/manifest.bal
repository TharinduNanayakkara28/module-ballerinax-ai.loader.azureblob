// Copyright (c) 2026, WSO2 LLC. (http://www.wso2.com).
//
// WSO2 LLC. licenses this file to you under the Apache License,
// Version 2.0 (the "License"); you may not use this file except
// in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing,
// software distributed under the License is distributed on an
// "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
// KIND, either express or implied.  See the License for the
// specific language governing permissions and limitations
// under the License.

// The exact blob layout this suite expects in the test container, and the single source of
// truth the scenarios derive their expectations from. Upload the files under
// `test-suite/fixtures/` to your container preserving their relative paths (see the
// package README); this manifest mirrors those files one-to-one.

// One expected blob in the test container.
type Fixture record {|
    // The full blob name (virtual folders included), matching the uploaded path.
    string name;
    // Whether the loader should turn it into an `ai:TextDocument`. Office documents,
    // images and other binaries are `false` (skipped in folder loads, errored when named).
    boolean supported;
    // A substring the extracted text must contain, when `supported`.
    string marker = "";
|};

// The marker Tika extracts from the single-page PDF fixtures (`single.pdf`, `reports/q1.pdf`).
const string SINGLE_PDF_MARKER = "Mock PDF document text.";

// Markers Tika extracts from the 12-page PDF fixture (`book.pdf`).
const string MULTIPAGE_PDF_MARKER = "Multi-page PDF fixture marker.";
const string MULTIPAGE_PDF_LAST_PAGE = "PDF_LAST_PAGE";
const int MULTIPAGE_PDF_PAGE_COUNT = 12;

// Every extension the loader treats as plain text, seeded once each under `formats/`
// (mirrors the loader's `TEXT_EXTENSIONS`). Proves "read all the text formats".
final readonly & string[] TEXT_FORMAT_EXTENSIONS = [
    "txt", "text", "md", "markdown", "csv", "tsv", "json", "xml", "html", "htm",
    "yaml", "yml", "log", "ini", "conf", "properties", "css", "js", "ts"
];

// The full expected fixture set. Must match the files under `test-suite/fixtures/` exactly;
// the test container should contain these blobs and nothing else.
final readonly & Fixture[] MANIFEST = buildManifest().cloneReadOnly();

isolated function buildManifest() returns Fixture[] {
    Fixture[] fixtures = [];

    // formats/sample.<ext> -> marker FORMAT_MARKER_<EXT>
    foreach string ext in TEXT_FORMAT_EXTENSIONS {
        fixtures.push({
            name: string `formats/sample.${ext}`,
            supported: true,
            marker: string `FORMAT_MARKER_${ext.toUpperAscii()}`
        });
    }

    // Root-level text.
    fixtures.push({name: "readme.txt", supported: true, marker: "ROOT_README"});
    fixtures.push({name: "data.json", supported: true, marker: "ROOT_JSON"});

    // PDFs (single page and 12 pages).
    fixtures.push({name: "single.pdf", supported: true, marker: SINGLE_PDF_MARKER});
    fixtures.push({name: "book.pdf", supported: true, marker: MULTIPAGE_PDF_MARKER});

    // Nested virtual folder.
    fixtures.push({name: "reports/q1.txt", supported: true, marker: "REPORTS_Q1"});
    fixtures.push({name: "reports/q1.pdf", supported: true, marker: SINGLE_PDF_MARKER});
    fixtures.push({name: "reports/2026/deep.txt", supported: true, marker: "REPORTS_DEEP"});

    // office/: Microsoft Office text extraction via Apache POI. .docx/.xlsx/.pptx exercise
    // the OOXML parser; .doc/.xls/.ppt the legacy OLE2 parser. All are now EXTRACTABLE.
    fixtures.push({name: "office/report.docx", supported: true, marker: "OFFICE_MARKER_DOCX"});
    fixtures.push({name: "office/report.xlsx", supported: true, marker: "OFFICE_MARKER_XLSX"});
    fixtures.push({name: "office/report.pptx", supported: true, marker: "OFFICE_MARKER_PPTX"});
    fixtures.push({name: "office/legacy.doc", supported: true, marker: "OFFICE_MARKER_DOC"});
    fixtures.push({name: "office/legacy.xls", supported: true, marker: "OFFICE_MARKER_XLS"});
    fixtures.push({name: "office/legacy.ppt", supported: true, marker: "OFFICE_MARKER_PPT"});

    // A scanned (image-only) PDF: parses but has no text layer, so the loader skips it in
    // listings (with a warning) and errors when it is named explicitly. OCR is not supported.
    fixtures.push({name: "scanned.pdf", supported: false});

    // Unsupported binary: skipped in folder loads, errored when named explicitly.
    fixtures.push({name: "photo.png", supported: false});

    return fixtures;
}

// The sentinel phrase in the error a named scanned (image-only) PDF surfaces.
const string SCANNED_PDF_SENTINEL = "no extractable text layer";

// ---- expectation helpers ----------------------------------------------------

// The blobs a load of `prefix` should return as documents, applying the loader's rules:
// direct-child-only unless `recursive`, plus an optional extension allowlist. `prefix` is
// an Azure blob-name prefix ("" is the whole container, "reports/" a folder).
isolated function expectedSupported(string prefix, boolean recursive, string[]? extFilter = ())
        returns Fixture[] {
    Fixture[] expected = [];
    foreach Fixture f in MANIFEST {
        if !f.supported || !f.name.startsWith(prefix) {
            continue;
        }
        string remainder = f.name.substring(prefix.length());
        if !recursive && remainder.includes("/") {
            continue;
        }
        if extFilter is string[] && !hasExtension(f.name, extFilter) {
            continue;
        }
        expected.push(f);
    }
    return expected;
}

// The lower-cased extension (without dot) of a blob name, or "".
isolated function fixtureExtension(string name) returns string {
    int? dot = name.lastIndexOf(".");
    return dot is () ? "" : name.substring(dot + 1).toLowerAscii();
}

isolated function hasExtension(string name, string[] allowed) returns boolean {
    string ext = fixtureExtension(name);
    foreach string a in allowed {
        string normalized = a.toLowerAscii();
        normalized = normalized.startsWith(".") ? normalized.substring(1) : normalized;
        if normalized == ext {
            return true;
        }
    }
    return false;
}
