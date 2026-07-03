# Ballerina Azure Blob Storage Data Loader

The `ballerinax/ai.azure.storage.blob` package provides a `TextDataLoader` that retrieves
documents from Azure Blob Storage containers and returns them as `ai:TextDocument` values,
ready to be chunked, embedded, and indexed by the Ballerina AI module.

It implements the `ai:DataLoader` abstraction, so it works anywhere an `ai:DataLoader` is
expected (for example, a RAG ingestion pipeline).

Acquisition (authentication, blob listing, download, pagination) is delegated to the
[`ballerinax/azure_storage_service.blobs`](https://central.ballerina.io/ballerinax/azure_storage_service.blobs)
connector; text extraction from PDFs uses Apache Tika.

> This package is under active development. See `doc/` in the repository for the phased
> implementation plan.
