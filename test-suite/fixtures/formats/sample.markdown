# FORMAT_MARKER_MARKDOWN

## Azure Blob Loader Markdown Fixture

The Azure Blob Storage data loader retrieves documents from one or more containers and returns them as text.

### Details

- The Azure Blob Storage data loader retrieves documents from one or more containers and returns them as text.
- Plain-text formats are decoded directly from their bytes, while PDF documents are parsed with Apache Tika.
- Virtual folders are expressed as slashes in the blob name, and recursion can be enabled per configured source.
- An optional extension allowlist restricts which blobs in a folder listing are turned into documents.
- Unsupported binaries such as images and Microsoft Office documents are skipped during folder loads.
- When a blob is named explicitly, a deliberately unsupported type is reported as an error instead of skipped.
- Listing follows the NextMarker pagination cursor so that large containers are fully enumerated.
- Each returned document carries metadata: the file name, MIME type, size, and any available timestamps.
- This fixture exists to exercise the loader end to end against a real storage account.
- It contains several paragraphs so that extraction has meaningful content to return and assert on.
- Text extraction should preserve the readable words on every page of a multi-page document.
- The loader treats a path with a trailing slash as a folder prefix rather than an exact blob name.
- A path without an extension that matches no blob is resolved as a folder prefix automatically.
- Content is intentionally verbose to make the extracted output realistic rather than trivial.
- Downstream retrieval-augmented generation pipelines consume these text documents as context.

> Plain-text formats are decoded directly from their bytes, while PDF documents are parsed with Apache Tika.
