# Phase 0 — Scaffold

**Status:** ✅ Complete & verified
**Goal:** Stand up the full repository structure for `ballerinax/ai.azure.storage.blob` by copying and renaming the `ballerinax/ai.microsoft.sharepoint` module, bring over the native Apache Tika text-extractor, and prove the package builds.

---

## 1. What was built

A complete, compiling Ballerina package skeleton — no acquisition or loader logic yet (that arrives in Phases 2–4). Concretely:

- Repo/Gradle scaffolding renamed from the SharePoint module.
- Both `Ballerina.toml` files (committed + build-config placeholder) with the Tika/PDFBox platform dependency block.
- The native `TextExtractor.java` (Apache Tika PDF text extraction) ported to the new Java package.
- A minimal placeholder Ballerina module so the package has valid source.
- Verified: the native jar compiles and `bal build` produces an executable.

---

## 2. Naming map applied everywhere

| Aspect | SharePoint (source) | This package |
|---|---|---|
| Ballerina package | `ai.microsoft.sharepoint` | `ai.azure.storage.blob` |
| Org | `ballerinax` | `ballerinax` (unchanged) |
| Java package | `io.ballerina.lib.ai.microsoft.sharepoint` | `io.ballerina.lib.ai.azure.storage.blob` |
| Native artifactId | `ai.microsoft.sharepoint-native` | `ai.azure.storage.blob-native` |
| Native-image config dir | `.../ai.microsoft.sharepoint-native/` | `.../ai.azure.storage.blob-native/` |
| Gradle root project | `module-ballerinax-ai.microsoft.sharepoint` | `module-ballerinax-ai.loader.azureblob` |
| Gradle subprojects | `:ai.microsoft.sharepoint-{native,ballerina}` | `:ai.azure.storage.blob-{native,ballerina}` |

> Note the intentional split: the **repo directory** is `module-ballerinax-ai.loader.azureblob` (matches the GitHub repo), but the **package** is `ai.azure.storage.blob` (per the plan). `rootProject.name` follows the repo dir; everything else follows the package name.

---

## 3. Files created

### Root
| File | Origin | Notes |
|---|---|---|
| `gradlew`, `gradlew.bat`, `gradle/wrapper/*` | copied verbatim | Gradle 8.11.1 wrapper |
| `LICENSE`, `.gitignore`, `.gitattributes` | copied verbatim | generic |
| `settings.gradle` | renamed | root project + subproject names/paths |
| `build.gradle` | renamed | release config; `build` depends on `:ai.azure.storage.blob-ballerina:build` |
| `gradle.properties` | copied | `group=io.ballerina.lib`, `version=1.0.1-SNAPSHOT`, dep versions (Tika 3.2.2, PDFBox 3.0.5, …) |
| `README.md` | new | project overview + build note |

### `ballerina/`
| File | Notes |
|---|---|
| `Ballerina.toml` | Committed manifest. `org=ballerinax`, `name=ai.azure.storage.blob`, `version=1.0.0`, distribution `2201.12.0`. Full `[[platform.java21.dependency]]` block: native jar + tika-core + tika-parser-pdf-module + pdfbox/pdfbox-io/fontbox/jempbox + commons-io. |
| `build.gradle` | `io.ballerina.plugin`; `packageName="ai.azure.storage.blob"`, `isConnector=true`, `platform="java21"`. `build`/`test` depend on `:ai.azure.storage.blob-native:build`. |
| `blob_data_loader.bal` | **Placeholder module.** License header + module doc + one public const `API_VERSION`. Replaced with real code in later phases. |
| `README.md` | Package landing doc (Package.md). |
| `icon.png` | copied from SharePoint. |

### `build-config/resources/`
| File | Notes |
|---|---|
| `Ballerina.toml` | Template with `@toml.version@` / `@project.version@` / `@tikaVersion@` … placeholders, expanded by the Gradle `updateTomlFiles` task at build time. |

### `native/`
| File | Notes |
|---|---|
| `build.gradle` | `java` plugin, Java 21; deps: `ballerina-runtime` + `tika-core` + `tika-parser-pdf-module`. |
| `src/main/java/io/ballerina/lib/ai/azure/storage/blob/TextExtractor.java` | **Ported verbatim** except package name + one doc comment (“SharePoint” → “Azure Blob Storage”). Uses `PDFParser` directly, reads in-memory bytes via `ByteArrayInputStream`, returns `BString` or a Ballerina error. |
| `src/main/resources/META-INF/native-image/io.ballerina.lib/ai.azure.storage.blob-native/native-image.properties` | `Args = -H:+AddAllCharsets` |

---

## 4. Build verification (how Phase 0 was proven)

The full Gradle build could not run in this environment because the `io.ballerina.plugin`
Gradle plugin resolves from GitHub Packages, which needs `packageUser` / `packagePAT`
credentials (not set here). So the package was verified **without Gradle**, by reproducing
what Gradle would do:

### 4.1 Build the native jar with `javac` + `jar`
Classpath sources (already on this machine):
- Ballerina runtime API classes: `…/ballerina-2201.12.0/bre/lib/ballerina-rt-2201.12.0.jar`
  (note: the API classes `io.ballerina.runtime.api.*` live in `ballerina-rt-*.jar`, **not** `runtime-*.jar`).
- Tika jars from the local Ballerina cache: `~/.ballerina/repositories/local/bala/ballerina/ai/1.11.3/java21/platform/java21/tika-{core,parser-pdf-module}-3.2.2.jar`.

```bash
javac -cp "<ballerina-rt>:<tika-core>:<tika-pdf>" \
  -d native/build/classes \
  native/src/main/java/io/ballerina/lib/ai/azure/storage/blob/TextExtractor.java

jar --create --file native/build/libs/ai.azure.storage.blob-native-1.0.0.jar \
  -C native/build/classes . -C native/src/main/resources .
```
Output jar contains `…/blob/TextExtractor.class` and the `native-image.properties` resource.
Its path/name matches the `path` declared in `ballerina/Ballerina.toml`.

### 4.2 Build the Ballerina package
```bash
cd ballerina && bal build
```
Result: Maven platform deps downloaded, `Compiling source ballerinax/ai.azure.storage.blob:1.0.0`,
and **`Generating executable → target/bin/ai.azure.storage.blob.jar`**. ✅

> When the real Gradle build is available (creds set), `./gradlew build` regenerates this
> native jar automatically and the manual step above is unnecessary.

---

## 5. Notes, deviations & carry-forward

- **Placeholder module.** `blob_data_loader.bal` only exists so the package has a public
  construct to compile. It (and `API_VERSION`) will be superseded by `types.bal`,
  `utils.bal`, and the real loader in Phases 1–4.
- **Native jar is a build artifact.** `native/build/` is git-ignored; it was materialised
  locally only to verify `bal build`. CI/release rebuilds it via Gradle.
- **`Dependencies.toml`** was intentionally **not** created — `bal build` generates it, and
  it will be populated once real module imports (`ballerina/ai`, the connector) are added.
- **Connector not yet wired.** `ballerinax/azure_storage_service.blobs` (v4.3.4) is confirmed
  to exist on Ballerina Central (`bal search`), but is **not** imported yet — that is Phase 3.
  A direct `bal pull` was inconclusive ("package not found" despite search listing it);
  resolution will be validated via a real import when Phase 3 begins.
- **Gradle build prerequisite:** set `packageUser` / `packagePAT` (GitHub account + PAT with
  `read:packages`) before `./gradlew build`.

---

## 6. Phase 0 checklist

- [x] Copy repo structure; rename package / org / Java package / artifacts.
- [x] Copy `TextExtractor.java` + native-image config (package-renamed).
- [x] Copy Tika/PDFBox platform deps into `Ballerina.toml` (+ build-config placeholder).
- [x] Minimal placeholder module so the package compiles.
- [x] Native jar builds; `bal build` produces an executable.
- [ ] (Deferred to Phase 3) Import + resolve `ballerinax/azure_storage_service.blobs`.

**Next:** Phase 1 — copy the text-conversion layer (`buildDocument` / `classify` / constants /
`extractText`) from the SharePoint `utils.bal` and unit-test PDF + text extraction from raw bytes.
