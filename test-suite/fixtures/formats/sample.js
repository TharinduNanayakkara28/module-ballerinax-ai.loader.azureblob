// FORMAT_MARKER_JS
// Azure Blob Loader JS fixture
const marker = "FORMAT_MARKER_JS";
const notes = ["The Azure Blob Storage data loader retrieves documents from one or more containers and returns them as text.", "Plain-text formats are decoded directly from their bytes, while PDF documents are parsed with Apache Tika.", "Virtual folders are expressed as slashes in the blob name, and recursion can be enabled per configured source.", "An optional extension allowlist restricts which blobs in a folder listing are turned into documents.", "Unsupported binaries such as images and Microsoft Office documents are skipped during folder loads.", "When a blob is named explicitly, a deliberately unsupported type is reported as an error instead of skipped.", "Listing follows the NextMarker pagination cursor so that large containers are fully enumerated.", "Each returned document carries metadata: the file name, MIME type, size, and any available timestamps.", "This fixture exists to exercise the loader end to end against a real storage account.", "It contains several paragraphs so that extraction has meaningful content to return and assert on.", "Text extraction should preserve the readable words on every page of a multi-page document.", "The loader treats a path with a trailing slash as a folder prefix rather than an exact blob name."];
function describe() {
  console.log("[1] " + notes[0]);
  console.log("[2] " + notes[1]);
  console.log("[3] " + notes[2]);
  console.log("[4] " + notes[3]);
  console.log("[5] " + notes[4]);
  console.log("[6] " + notes[5]);
  console.log("[7] " + notes[6]);
  console.log("[8] " + notes[7]);
  console.log("[9] " + notes[8]);
  console.log("[10] " + notes[9]);
  console.log("[11] " + notes[10]);
  console.log("[12] " + notes[11]);
}
describe();
