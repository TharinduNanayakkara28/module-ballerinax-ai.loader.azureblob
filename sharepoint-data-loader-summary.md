# Ballerina SharePoint Data Loader — Summary

## What it is
`ballerinax/ai.microsoft.sharepoint` provides a **`TextDataLoader`** that retrieves documents from SharePoint document libraries and returns them as **`ai:TextDocument`** values — ready to be chunked, embedded, and indexed by the Ballerina AI module.

It implements the **`ai:DataLoader`** abstraction, so it works anywhere an `ai:DataLoader` is expected (e.g. a RAG ingestion pipeline).

## How it handles files
- **Textual files** (`txt`, `md`, `html`, `json`, `csv`, `xml`) → decoded directly.
- **PDF files** → text extracted with **Apache Tika**.
- **Non-textual files** (images, audio, archives) → skipped with a logged warning; naming one explicitly as a path is an error.

## Core capabilities
- Resolves a document library (drive) per site via the Microsoft Graph **sites** API.
- Downloads file content via the Microsoft Graph **drive items** API.
- Loads individual files or entire folders (optionally recursive).
- Optionally loads SharePoint **site pages** (modern web-part pages) as text.
- Reads from **multiple sites and libraries** with a single loader instance.

## Authentication
Accessed through the Microsoft Graph API. Three mechanisms via `ConnectionConfig.auth`:

| Mechanism | Type | Best for |
|---|---|---|
| Client credentials grant | `OAuth2ClientCredentialsGrantConfig` | App-only, server-to-server (needs `Sites.Read.All`; use `Sites.Selected` for least-privilege) |
| Refresh token grant | `OAuth2RefreshTokenGrantConfig` | User-delegated access |
| Bearer token | `http:BearerTokenConfig` | Pre-obtained access token (testing / external tokens) |

## Site pages (`pages` field on a `Source`)
- `["*"]` — load every page.
- `["Home", "Q3-Update"]` — specific pages, matched by name (file name incl. `.aspx`), title, or id. Matching by title is usually easier.
- omitted / `()` — load no pages (default).

Each page becomes one `ai:TextDocument`: title + plain text from its web parts (HTML stripped). Metadata includes title, `webUrl`, and timestamps.
> Web-part extraction relies on the Graph `pages/webParts` API — best-effort; some pages may yield only the title.

## Multiple libraries (`libraries` field)
Each `Library` binds a library to its own paths and traversal options (mirrors the Graph model where paths resolve relative to a specific drive).

- `paths` default `["/"]` → a bare `{name: "Specs"}` loads the whole library.
- `libraries` default `[{}]` → a `Source` with only a `siteId` loads the whole default document library; `[]` loads none.
- `name: "Documents"` (default) — the standard library; **localized tenants** use a translated name (e.g. `Dokumente`, `Documentos`, `文档`), so set `name` explicitly there.
- `name: "*"` — every library on the site. Missing paths are skipped (not errors) for wildcard; a named library treats a missing path as an error (catches typos).

## Filtering by file type (`includeExtensions` per `Library`)
- `["pdf"]` — only PDFs.
- `["pdf", ".md", "TXT"]` — case-insensitive; leading dot optional.
- omitted / `()` — load all types (default).

Applies to files discovered while traversing folders. A file listed **explicitly** in `paths` is always loaded, even if its extension isn't allowlisted.

## Loading documents
```ballerina
public function main() returns error? {
    ai:Document[]|ai:Document documents = check loader.load();
    // Pass to a chunker / embedding provider / vector store ...
}
```
`load()` returns a **single** `ai:Document` when exactly one file is resolved, and an **`ai:Document[]`** otherwise (mirrors `ai:TextDataLoader`).

## Initialization example
```ballerina
import ballerina/ai;
import ballerinax/ai.microsoft.sharepoint;

final sharepoint:TextDataLoader loader = check new (
    {
        auth: {
            tokenUrl: "https://login.microsoftonline.com/<tenant-id>/oauth2/v2.0/token",
            clientId: "<client-id>",
            clientSecret: "<client-secret>",
            scopes: ["https://graph.microsoft.com/.default"]
        }
    },
    {
        siteId: "contoso.sharepoint.com:/sites/HR",
        libraries: [
            {
                paths: ["/Policies/leave-policy.pdf", "/Onboarding"],
                recursive: true,
                includeExtensions: ["pdf"]
            }
        ]
    },
    {
        siteId: "contoso.sharepoint.com:/sites/Engineering",
        libraries: [
            {name: "Specs", paths: ["/api-design.md"]},
            {name: "Site Assets", paths: ["/diagrams"], recursive: true}
        ]
    },
    {
        siteId: "contoso.sharepoint.com:/sites/News",
        pages: ["*"]
    }
);
```

## Configuration reference

### `ConnectionConfig` (key fields)
| Field | Type | Default | Description |
|---|---|---|---|
| `auth` | Bearer / ClientCredentials / RefreshToken | — | Authentication config |
| `serviceUrl` | `string` | `https://graph.microsoft.com/v1.0` | Graph base URL |
| `httpVersion` | `http:HttpVersion` | `HTTP_2_0` | HTTP version |
| `timeout` | `decimal` | `30` | Response timeout (s) |
| `followRedirects` | `http:FollowRedirects` | `{enabled: true, maxCount: 5, allowAuthHeaders: true}` | Follows the `/items/{id}/content` 302 download redirect |
| `compression` | `http:Compression` | `COMPRESSION_AUTO` | `accept-encoding` handling |
| `validation` | `boolean` | `true` | Inbound payload validation |
| `laxDataBinding` | `boolean` | `true` | Relaxed data binding |

(Plus standard HTTP client fields: `http1Settings`, `http2Settings`, `poolConfig`, `cache`, `circuitBreaker`, `retryConfig`, `cookieConfig`, `responseLimits`, `secureSocket`, `proxy`, `socketConfig`, `forwarded`.) HTTP-level fields are forwarded to both the sites and pages clients.

### `Source`
| Field | Type | Default | Description |
|---|---|---|---|
| `siteId` | `string` | — | Graph site id: composite `({hostname},{spsite-guid},{spweb-guid})` or path form `({hostname}:/sites/{site-name})` |
| `libraries` | `Library[]` | `[{}]` | Libraries to read; `[{}]` = whole default library, `[]` = none |
| `pages` | `string[]?` | `()` | Site pages to load; `["*"]` = all, `()` = none |

### `Library`
| Field | Type | Default | Description |
|---|---|---|---|
| `name` | `string` | `"Documents"` | Library display name; `"*"` = every library |
| `paths` | `string[]` | `["/"]` | Paths relative to library root; `["/"]` = whole library, `[]` = none |
| `recursive` | `boolean` | `false` | Traverse folders recursively |
| `includeExtensions` | `string[]?` | `()` | Extension allowlist for folder contents; case-insensitive; `()` = all |
