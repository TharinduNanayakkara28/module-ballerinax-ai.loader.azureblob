# module-ballerinax-ai.loader.azureblob

A Ballerina data loader that ingests documents from **Azure Blob Storage** and returns them
as `ai:TextDocument` values for the Ballerina AI module (chunking, embedding, RAG ingestion).

- **Package:** `ballerinax/ai.azure.storage.blob`
- **Acquisition layer:** the [`ballerinax/azure_storage_service.blobs`](https://central.ballerina.io/ballerinax/azure_storage_service.blobs) connector (auth, listing, download, pagination).
- **Text extraction:** direct decode for textual blobs; Apache Tika for PDFs.

## Status

Under active development, built in phases. See [`doc/`](doc/) for the per-phase
implementation records and [`azure-blob-data-loader-connector-plan.md`](azure-blob-data-loader-connector-plan.md)
for the overall design.

## Building

```bash
./gradlew build
```

The Gradle build requires the `packageUser`/`packagePAT` environment variables (a GitHub
account + PAT with `read:packages`) to resolve the `io.ballerina.plugin` Gradle plugin from
GitHub Packages.
