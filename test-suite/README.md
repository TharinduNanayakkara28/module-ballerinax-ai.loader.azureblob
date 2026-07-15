# Azure Blob Storage loader — integration test suite

A standalone package that exercises the public `TextDataLoader` API end-to-end against a
real Azure Blob Storage account. It covers reading every supported text format, PDF text
extraction (including a document of more than ten pages), virtual-folder recursion,
extension filtering, single-vs-array results, metadata, and the error/skip paths for
unsupported files.

This suite does **not** create or upload anything — you upload a fixed set of fixtures
once, then run it. The expected layout is defined in
[`tests/manifest.bal`](tests/manifest.bal) and the files to upload are in
[`fixtures/`](fixtures/).

## 1. Prerequisites

Publish the loader to the local repository so this package can resolve it:

```bash
cd ../ballerina
bal pack && bal push --repository=local
```

## 2. Upload the fixtures

Create a **dedicated** container (default name `loader-test-suite`) and upload everything
under `fixtures/`, **preserving the relative paths** (so `fixtures/formats/sample.json`
becomes the blob `formats/sample.json`). The container must contain these blobs and
nothing else, since some tests assert exact document counts.

Using the Azure CLI:

```bash
az storage container create --name loader-test-suite --account-name <ACCOUNT>
az storage blob upload-batch \
    --account-name <ACCOUNT> \
    --destination loader-test-suite \
    --source fixtures
```

The layout that gets created:

| Blob | Purpose |
|------|---------|
| `formats/sample.<ext>` (19 files) | one per supported text extension |
| `readme.txt`, `data.json` | root-level text (with content types) |
| `single.pdf` | single-page PDF text extraction |
| `book.pdf` | **12-page** PDF — proves >10-page extraction |
| `reports/q1.txt`, `reports/q1.pdf` | direct children (recursion) |
| `reports/2026/deep.txt` | nested child (recursion) |
| `photo.png` | unsupported image (skipped / errors when named) |
| `report.docx`, `sheet.xlsx`, `slides.pptx` | unsupported Office (skipped / errors when named) |

## 3. Configure

`bal test` reads `Config.toml` from the **`tests/` directory** (not the package root), so
place it there:

```bash
cp tests/Config.toml.template tests/Config.toml   # then fill in credentials + container name
```

Use the **current** access key (Azure Portal → your storage account → *Security + networking*
→ *Access keys* → *Show* key1 → copy). A stale key fails every request with
`403 AuthenticationFailed ... signature`.

## 4. Run

```bash
bal test                       # all scenarios
bal test --groups integration  # same set, explicitly
```

Alternatively, pass values on the command line without a file:

```bash
bal test -CaccountName=<acct> -CaccessKeyOrSAS=<key> -CauthMethod=ACCESS_KEY -CtestContainer=loader-test-suite
```
