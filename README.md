# module-ballerinax-ai.loader.azureblob

A Ballerina data loader that ingests documents from **Azure Blob Storage** and returns them
as `ai:TextDocument` values for the Ballerina AI module (chunking, embedding, RAG ingestion).

- **Package:** `ballerinax/ai.azure.storage.blob`
- **Acquisition layer:** the [`ballerinax/azure_storage_service.blobs`](https://central.ballerina.io/ballerinax/azure_storage_service.blobs) connector (auth, listing, download, pagination).
- **Text extraction:** direct decode for textual blobs; Apache Tika for PDFs.
- **Authentication:** Shared Access Signature (SAS) and Shared Key (account access key). Azure AD / OAuth2 is not supported in this version.

See the [module README](ballerina/README.md) for the full usage guide and configuration
reference, and [`doc/`](doc/) for the per-phase implementation records.

## Status

Implemented: scaffold, text-extraction layer, public API, and the loader over the connector.
The text layer and all pure loader logic are unit-tested (`bal test`); the connector-backed
`load()` orchestration is not integration-tested (see [`doc/phase-3-loader.md`](doc/phase-3-loader.md) §6).
Overall design: [`azure-blob-data-loader-connector-plan.md`](azure-blob-data-loader-connector-plan.md).

## Building

```bash
./gradlew build
```

The Gradle build requires the `packageUser`/`packagePAT` environment variables (a GitHub
account + PAT with `read:packages`) to resolve the `io.ballerina.plugin` Gradle plugin from
GitHub Packages.
