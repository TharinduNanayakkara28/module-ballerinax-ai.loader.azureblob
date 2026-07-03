# Phase 5 — Documentation

**Status:** ✅ Complete
**Goal:** Write the user-facing documentation — the module README (the Package.md shown on
Ballerina Central) and the repository README — covering authentication, the container/prefix
model, recursion, filtering, usage examples, and the configuration reference.

> In the connector-based plan, this is the final phase. (The original hand-built plan had a
> separate "Phase 5 — Shared Key auth"; that work is unnecessary here because the connector
> already provides Shared Key signing, so this Phase 5 is Documentation.)

---

## 1. What was written

### `ballerina/README.md` (module / Package.md)
The primary user guide, modelled on the SharePoint module's README but rewritten for the
connector-based Azure Blob loader. Sections:

- **Overview** — what the loader does; textual vs PDF vs skipped/unsupported (incl. Office).
- **Authentication** — a table of the two supported mechanisms and how they map to
  `authorizationMethod` + `accessKeyOrSAS`; an explicit note that Azure AD / OAuth2 is not
  supported in this version; the derived endpoint `https://{accountName}.blob.core.windows.net`.
- **Usage**
  - Initialization example (`blob:TextDataLoader`, `blob:SAS`).
  - **The container / prefix model** — the flat-namespace explanation, and the
    explicit-blob-vs-folder disambiguation rules (trailing `/`, extension-based typo
    detection, explicit non-text → error).
  - **Recursion** — `recursive: true`.
  - **Reading from every container** — `container: "*"` and its skip-on-missing semantics.
  - **Filtering by file type** — `includeExtensions` (case-insensitive, dot-optional;
    explicit paths bypass it).
  - **Loading documents** — `load()` single-vs-array return; the RFC 1123 timestamp note.
- **Configuration reference** — `ConnectionConfig` and `Source` field tables.

### `README.md` (repository root)
Updated the summary, added an authentication one-liner, linked to the module README, and
replaced the "under active development" status with an accurate current state (implemented;
text + pure loader logic unit-tested; `load()` orchestration not integration-tested, linking
to `doc/phase-3-loader.md` §6).

---

## 2. Accuracy notes baked into the docs

The documentation deliberately records the real, as-built behaviour — including the
constraints discovered while implementing:

- **Auth:** SAS + Shared Key only; **no AAD** (stated explicitly).
- **Endpoint:** derived from `accountName`, no override field.
- **Timestamps:** Azure's RFC 1123 `Creation-Time`/`Last-Modified` are not parsed by the
  ISO 8601 `time` API, so `createdAt`/`modifiedAt` are omitted — documented as a note rather
  than silently surprising users.
- **Office formats:** unsupported — skipped in listings, error when named explicitly.
- **`ConnectionConfig` fields:** the reference lists exactly the fields the config exposes
  (no `serviceUrl`, no `http1Settings`, no `cookieConfig`/`socketConfig`/`laxDataBinding`),
  matching what the connector actually accepts (Phase 2).

The module import prefix is `blob` (the last segment of `ai.azure.storage.blob`), so the docs
use `blob:TextDataLoader`, `blob:SAS`, `blob:ACCESS_KEY`.

---

## 3. Files touched

| File | Change |
|---|---|
| `ballerina/README.md` | **Rewritten** — full module usage guide + configuration reference. |
| `README.md` | **Updated** — status, auth summary, link to the module README. |

Build re-verified after the doc changes: `cd ballerina && bal build` → `target/bin/ai.azure.storage.blob.jar`.

---

## 4. Phase 5 checklist

- [x] Module README: overview, auth table, container/prefix model, recursion, `"*"`,
      filtering, usage, config reference.
- [x] Root README: status + pointers.
- [x] Docs reflect the real constraints (no AAD, no endpoint override, RFC 1123 timestamps,
      Office unsupported).
- [x] Build still green.

---

## 5. Project status (all phases)

| Phase | Deliverable | State |
|---|---|---|
| 0 | Scaffold + native Tika jar | ✅ `bal build` green |
| 1 | Text-conversion layer | ✅ 21 unit tests |
| 2 | Public API + client wiring | ✅ +10 tests |
| 3 | Loader over the connector | ✅ +15 tests (pure logic); `load()` orchestration not integration-tested (by decision) |
| 5 | Documentation | ✅ this phase |

**Total:** 46 tests passing. The package builds and is documented.

### Optional follow-ups (not scheduled)
- `BlobStore` seam + mock service to integration-test `load()` (plan §9 / phase-3 §6).
- RFC 1123 → `time:Utc` parsing to populate document timestamps.
- Azure AD / OAuth2 auth (would require the seam or a raw client path).
- GitHub Actions CI (`packageUser`/`packagePAT`) to run the Gradle build + native jar.
