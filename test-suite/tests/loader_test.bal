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

// End-to-end scenarios for the Azure Blob Storage `TextDataLoader`, run against the fixtures
// uploaded to the test container (see `manifest.bal` and the package README). Every test is
// in the `integration` group so it can be selected/skipped as a batch.

import ballerina/ai;
import ballerina/io;
import ballerina/test;
import ballerinax/ai.azure.storage.blob;

// When true, every load prints the documents it returned (name, size, metadata and the
// full extracted text). Off by default so a normal `bal test` run stays quiet; enable with
// `printContent = true` in tests/Config.toml, or `bal test -CprintContent=true`.
configurable boolean printContent = false;

// ---- helpers -----------------------------------------------------------------

// Builds one source over the test container.
isolated function srcOf(string[] paths, boolean recursive = false, string[]? includeExtensions = ())
        returns blob:Source =>
    {container: testContainer, paths, recursive, includeExtensions};

// Loads the given sources and always returns an array, collapsing `load()`'s single-document
// return so assertions can be uniform.
isolated function loadAll(blob:Source[] sources) returns ai:Document[]|ai:Error {
    blob:TextDataLoader loader = check new (connectionConfig(), sources);
    ai:Document[]|ai:Document result = check loader.load();
    ai:Document[] docs = result is ai:Document[] ? result : [result];
    dumpDocs(sources, docs);
    return docs;
}

// Prints the loaded documents when `printContent` is enabled.
isolated function dumpDocs(blob:Source[] sources, ai:Document[] docs) {
    if !printContent {
        return;
    }
    io:println(string `
================================================================================
LOAD ${sources.toString()}
  -> ${docs.length()} document(s)`);
    foreach ai:Document doc in docs {
        if doc is ai:TextDocument {
            io:println(string `
--------------------------------------------------------------------------------
file : ${doc.metadata?.fileName ?: "(no name)"}
mime : ${doc.metadata?.mimeType ?: "(none)"}
chars: ${doc.content.length()}
----- content -----
${doc.content}`);
        }
    }
}

// The `fileName` metadata of each loaded document.
isolated function docFileNames(ai:Document[] docs) returns string[] {
    string[] names = [];
    foreach ai:Document doc in docs {
        if doc is ai:TextDocument {
            names.push(doc.metadata?.fileName ?: "");
        }
    }
    return names;
}

// The extracted content of the document with the given file name, or `()` if absent.
isolated function contentOf(ai:Document[] docs, string name) returns string? {
    foreach ai:Document doc in docs {
        if doc is ai:TextDocument && doc.metadata?.fileName == name {
            return doc.content;
        }
    }
    return ();
}

// Asserts the loaded documents are exactly the expected fixtures: the same count, and each
// expected fixture present with its marker in the extracted text.
isolated function assertExactly(ai:Document[] docs, Fixture[] expected, string context) {
    test:assertEquals(docFileNames(docs).length(), expected.length(),
        string `${context}: unexpected document count (got names: ${docFileNames(docs).toString()})`);
    foreach Fixture f in expected {
        string? content = contentOf(docs, f.name);
        if content is () {
            test:assertFail(string `${context}: expected document '${f.name}' was not loaded`);
        } else {
            test:assertTrue(content.includes(f.marker),
                string `${context}: '${f.name}' content is missing marker '${f.marker}'`);
        }
    }
}

// ---- whole-container loads ---------------------------------------------------

@test:Config {groups: ["integration"]}
isolated function testLoadWholeContainerRecursive() returns error? {
    ai:Document[] docs = check loadAll([srcOf(["/"], recursive = true)]);
    assertExactly(docs, expectedSupported("", true), "whole container (recursive)");
    // The image and the scanned (image-only) PDF must be skipped, never surfaced;
    // the six Office documents under office/ ARE now loaded (see assertExactly above).
    foreach string name in ["photo.png", "scanned.pdf"] {
        test:assertTrue(contentOf(docs, name) is (), string `unsupported '${name}' must be skipped`);
    }
}

@test:Config {groups: ["integration"]}
isolated function testLoadRootNonRecursive() returns error? {
    ai:Document[] docs = check loadAll([srcOf(["/"])]);
    // Only root-level supported files; nothing from formats/ or reports/.
    assertExactly(docs, expectedSupported("", false), "container root (non-recursive)");
    foreach string name in docFileNames(docs) {
        test:assertFalse(name.includes("/"), string `non-recursive root must not descend: '${name}'`);
    }
}

// ---- every text format -------------------------------------------------------

@test:Config {groups: ["integration"]}
isolated function testAllTextFormatsExtracted() returns error? {
    ai:Document[] docs = check loadAll([srcOf(["formats/"], recursive = true)]);
    Fixture[] expected = expectedSupported("formats/", true);
    // Sanity: one fixture per known text extension.
    test:assertEquals(expected.length(), TEXT_FORMAT_EXTENSIONS.length(), "one fixture per text extension");
    assertExactly(docs, expected, "formats/ (all text extensions)");
    foreach ai:Document doc in docs {
        test:assertTrue(doc is ai:TextDocument, "every format fixture must load as a TextDocument");
    }
}

// ---- PDFs --------------------------------------------------------------------

@test:Config {groups: ["integration"]}
isolated function testMultiPagePdfAllPagesExtracted() returns error? {
    ai:Document[] docs = check loadAll([srcOf(["book.pdf"])]);
    test:assertEquals(docs.length(), 1, "one document for a single named blob");
    string? content = contentOf(docs, "book.pdf");
    if content is () {
        test:assertFail("book.pdf was not loaded");
    }
    test:assertTrue(content.includes(MULTIPAGE_PDF_MARKER), "per-page marker present");
    test:assertTrue(content.includes(MULTIPAGE_PDF_LAST_PAGE), "final-page sentinel present (all pages read)");
    // Every page's 'Page N of 12.' line must have been extracted.
    int page = 1;
    while page <= MULTIPAGE_PDF_PAGE_COUNT {
        string line = string `Page ${page} of ${MULTIPAGE_PDF_PAGE_COUNT}.`;
        test:assertTrue(content.includes(line), string `missing text for page ${page}: '${line}'`);
        page += 1;
    }
}

@test:Config {groups: ["integration"]}
isolated function testSingleBlobReturnsOneDocument() returns error? {
    blob:TextDataLoader loader = check new (connectionConfig(), [srcOf(["single.pdf"])]);
    ai:Document[]|ai:Document result = check loader.load();
    // A single resolved blob returns one Document, not an array.
    test:assertFalse(result is ai:Document[], "a single blob returns one Document, not an array");
    if result is ai:TextDocument {
        test:assertTrue(result.content.includes(SINGLE_PDF_MARKER), "single.pdf text extracted");
    }
}

// ---- extension filtering -----------------------------------------------------

@test:Config {groups: ["integration"]}
isolated function testExtensionFilterPdfOnly() returns error? {
    ai:Document[] docs = check loadAll([srcOf(["/"], recursive = true, includeExtensions = ["pdf"])]);
    assertExactly(docs, expectedSupported("", true, ["pdf"]), "extension filter [pdf]");
    foreach string name in docFileNames(docs) {
        test:assertTrue(name.endsWith(".pdf"), string `filter [pdf] leaked a non-pdf: '${name}'`);
    }
}

@test:Config {groups: ["integration"]}
isolated function testExtensionFilterMultipleWithDotAndCase() returns error? {
    // Leading dot and mixed case in the allowlist are tolerated; only exact-extension matches.
    ai:Document[] docs = check loadAll([srcOf(["formats/"], recursive = true, includeExtensions = [".MD", "json"])]);
    assertExactly(docs, expectedSupported("formats/", true, [".MD", "json"]), "extension filter [.MD, json]");
}

// ---- nested folders: recursive vs non-recursive ------------------------------

@test:Config {groups: ["integration"]}
isolated function testReportsNonRecursive() returns error? {
    ai:Document[] docs = check loadAll([srcOf(["reports/"])]);
    // Direct children only: q1.txt and q1.pdf, not reports/2026/deep.txt.
    assertExactly(docs, expectedSupported("reports/", false), "reports/ (non-recursive)");
    test:assertTrue(contentOf(docs, "reports/2026/deep.txt") is (), "nested blob excluded when non-recursive");
}

@test:Config {groups: ["integration"]}
isolated function testReportsRecursive() returns error? {
    ai:Document[] docs = check loadAll([srcOf(["reports/"], recursive = true)]);
    assertExactly(docs, expectedSupported("reports/", true), "reports/ (recursive)");
    test:assertTrue(contentOf(docs, "reports/2026/deep.txt") !is (), "nested blob included when recursive");
}

@test:Config {groups: ["integration"]}
isolated function testAmbiguousPathResolvesToFolder() returns error? {
    // 'reports' has no trailing slash and no extension, and no blob is named exactly
    // 'reports', so it is treated as the folder prefix 'reports/'.
    ai:Document[] docs = check loadAll([srcOf(["reports"])]);
    assertExactly(docs, expectedSupported("reports/", false), "ambiguous 'reports' -> folder");
}

// ---- explicitly named blobs --------------------------------------------------

@test:Config {groups: ["integration"]}
isolated function testExplicitTextBlobByName() returns error? {
    ai:Document[] docs = check loadAll([srcOf(["readme.txt"])]);
    test:assertEquals(docs.length(), 1);
    string? content = contentOf(docs, "readme.txt");
    test:assertTrue(content is string && content.includes("ROOT_README"), "named text blob loaded");
}

@test:Config {groups: ["integration"]}
isolated function testMetadataPopulated() returns error? {
    ai:Document[] docs = check loadAll([srcOf(["single.pdf"])]);
    ai:Document doc = docs[0];
    if doc is ai:TextDocument {
        test:assertEquals(doc.metadata?.fileName, "single.pdf", "fileName metadata");
        test:assertEquals(doc.metadata?.mimeType, "application/pdf", "mimeType metadata");
        decimal? size = doc.metadata?.fileSize;
        test:assertTrue(size is decimal && size > 0d, "fileSize metadata populated");
    } else {
        test:assertFail("expected a TextDocument");
    }
}

// ---- Microsoft Office extraction ---------------------------------------------

@test:Config {groups: ["integration"]}
isolated function testOfficeFolderExtractsAllFormats() returns error? {
    // A load of office/ extracts every Office format via Apache POI — the OOXML
    // (.docx/.xlsx/.pptx) and legacy OLE2 (.doc/.xls/.ppt) parsers.
    ai:Document[] docs = check loadAll([srcOf(["office/"], recursive = true)]);
    Fixture[] expected = expectedSupported("office/", true);
    test:assertEquals(expected.length(), 6, "six Office fixtures expected");
    assertExactly(docs, expected, "office/ (all Office formats)");
}

@test:Config {groups: ["integration"]}
isolated function testNamedOfficeDocxExtracts() returns error? {
    // A named Office document is extracted via Apache POI, exactly like a PDF.
    ai:Document[] docs = check loadAll([srcOf(["office/report.docx"])]);
    test:assertEquals(docs.length(), 1);
    string? content = contentOf(docs, "office/report.docx");
    test:assertTrue(content is string && content.includes("OFFICE_MARKER_DOCX"), "docx extracted");
}

@test:Config {groups: ["integration"]}
isolated function testNamedLegacyOfficeXlsExtracts() returns error? {
    // Legacy OLE2 .xls exercises POI's OfficeParser.
    ai:Document[] docs = check loadAll([srcOf(["office/legacy.xls"])]);
    string? content = contentOf(docs, "office/legacy.xls");
    test:assertTrue(content is string && content.includes("OFFICE_MARKER_XLS"), "xls extracted");
}

// ---- scanned (image-only) PDF ------------------------------------------------

@test:Config {groups: ["integration"]}
isolated function testNamedScannedPdfErrors() {
    // A scanned PDF named explicitly surfaces a descriptive error (never an empty document).
    ai:Document[]|ai:Error result = loadAll([srcOf(["scanned.pdf"])]);
    if result is ai:Error {
        test:assertTrue(result.message().includes(SCANNED_PDF_SENTINEL), result.message());
    } else {
        test:assertFail("an explicitly named scanned PDF should error");
    }
}

@test:Config {groups: ["integration"]}
isolated function testScannedPdfSkippedInListing() returns error? {
    // In a whole-container listing the scanned PDF is skipped (warn), not an error, and
    // never surfaces as a document.
    ai:Document[] docs = check loadAll([srcOf(["/"], recursive = true)]);
    test:assertTrue(contentOf(docs, "scanned.pdf") is (), "scanned PDF skipped in listing");
}

// ---- error paths -------------------------------------------------------------

@test:Config {groups: ["integration"]}
isolated function testExplicitImageErrors() {
    ai:Document[]|ai:Error result = loadAll([srcOf(["photo.png"])]);
    if result is ai:Error {
        test:assertTrue(result.message().toLowerAscii().includes("unsupported"), result.message());
    } else {
        test:assertFail("an explicitly named image should error");
    }
}

@test:Config {groups: ["integration"]}
isolated function testMissingNamedFileErrors() {
    // A path that looks like a file (has an extension) but does not exist is an error.
    ai:Document[]|ai:Error result = loadAll([srcOf(["does-not-exist.pdf"])]);
    if result is ai:Error {
        test:assertTrue(result.message().toLowerAscii().includes("not found") ||
            result.message().toLowerAscii().includes("failed to load"), result.message());
    } else {
        test:assertFail("a missing named file should error");
    }
}

// ---- empty results, multiple paths and sources -------------------------------

@test:Config {groups: ["integration"]}
isolated function testNonexistentFolderPrefixIsEmpty() returns error? {
    // A folder-looking prefix that matches nothing returns an empty result, not an error.
    ai:Document[] docs = check loadAll([srcOf(["no-such-folder-xyz/"])]);
    test:assertEquals(docs.length(), 0, "an empty prefix yields no documents");
}

@test:Config {groups: ["integration"]}
isolated function testEmptyPathsReadsNothing() returns error? {
    ai:Document[] docs = check loadAll([srcOf([])]);
    test:assertEquals(docs.length(), 0, "paths [] reads nothing");
}

@test:Config {groups: ["integration"]}
isolated function testMultiplePaths() returns error? {
    ai:Document[] docs = check loadAll([srcOf(["reports/q1.txt", "single.pdf"])]);
    test:assertEquals(docs.length(), 2, "two named paths -> two documents");
    test:assertTrue(contentOf(docs, "reports/q1.txt") is string);
    test:assertTrue(contentOf(docs, "single.pdf") is string);
}

@test:Config {groups: ["integration"]}
isolated function testMultipleSources() returns error? {
    ai:Document[] docs = check loadAll([srcOf(["formats/"], true), srcOf(["reports/"], true)]);
    Fixture[] expected = expectedSupported("formats/", true);
    expected.push(...expectedSupported("reports/", true));
    assertExactly(docs, expected, "two sources combined");
}
