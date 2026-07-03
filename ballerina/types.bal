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

import ballerina/http;

# The mechanism used to authorize requests to Azure Blob Storage. Azure AD / OAuth2 is
# intentionally not offered in this version (the underlying connector supports Shared Key
# and SAS only); it can be added later without changing this enum.
public enum AuthorizationMethod {
    # An account access key (Shared Key). The connector signs each request with HMAC-SHA256.
    ACCESS_KEY,
    # A Shared Access Signature: a scoped, time-limited, pre-signed token.
    SAS
}

# Authentication and connection configuration for Azure Blob Storage. This is a stable,
# loader-owned surface that maps onto the `ballerinax/azure_storage_service.blobs`
# connector's configuration; the HTTP-level options are forwarded to the connector's
# blob client. The service endpoint is derived from `accountName`
# (`https://{accountName}.blob.core.windows.net`).
public type ConnectionConfig record {|
    # The Azure Storage account name; used to build the blob service endpoint.
    string accountName;
    # An account access key or a SAS token, interpreted according to `authorizationMethod`.
    @display {label: "", kind: "password"}
    string accessKeyOrSAS;
    # Whether `accessKeyOrSAS` is an account access key (Shared Key) or a SAS token.
    AuthorizationMethod authorizationMethod;
    # The HTTP version understood by the client
    http:HttpVersion httpVersion = http:HTTP_1_1;
    # Configurations related to HTTP/2 protocol
    http:ClientHttp2Settings http2Settings?;
    # The maximum time to wait (in seconds) for a response before closing the connection
    decimal timeout = 30;
    # The choice of setting `forwarded`/`x-forwarded` header
    string forwarded = "disable";
    # Configurations associated with request pooling
    http:PoolConfiguration poolConfig?;
    # HTTP caching related configurations
    http:CacheConfig cache?;
    # Specifies the way of handling compression (`accept-encoding`) header
    http:Compression compression = http:COMPRESSION_AUTO;
    # Configurations associated with the behaviour of the Circuit Breaker
    http:CircuitBreakerConfig circuitBreaker?;
    # Configurations associated with retrying
    http:RetryConfig retryConfig?;
    # Configurations associated with inbound response size limits
    http:ResponseLimitConfigs responseLimits?;
    # SSL/TLS-related options
    http:ClientSecureSocket secureSocket?;
    # Proxy server related options
    http:ProxyConfig proxy?;
    # Enables the inbound payload validation functionality provided by the constraint package
    boolean validation = true;
|};

# A rule selecting what to load from one Azure Blob container. Several may be configured
# per loader. A container is the unit of addressing (analogous to a SharePoint library):
# there is no site/library chain, so a container maps directly to a `Source`.
public type Source record {|
    # The container name to read from, or `"*"` for every container in the account.
    # For `"*"`, a missing path is tolerated (skipped) rather than an error.
    string container;
    # Blob-name prefixes (virtual-folder paths, e.g. `/reports`) to read.
    # Defaults to `["/"]`, the whole container; `[]` reads nothing.
    string[] paths = ["/"];
    # Whether virtual sub-folders under a prefix are traversed. Defaults to `false`.
    boolean recursive = false;
    # Case-insensitive extension allowlist for prefix listings.
    # Defaults to `()`, all types.
    string[]? includeExtensions = ();
|};

// A normalized listing entry, decoupled from the connector's `Blob` record (whose
// `Properties` are an untyped `map<json>`). The loader (Phase 3) reads the connector's
// blob metadata into this shape before building an `ai:TextDocument`.

# A single blob discovered while listing a container prefix.
type BlobEntry record {|
    # The full blob name (may contain `/`, giving virtual folders), e.g. `reports/q1.pdf`.
    string name;
    # The blob's `Content-Type`, if reported.
    string? contentType = ();
    # The blob's size in bytes, if reported.
    decimal? contentLength = ();
    # The blob's creation timestamp (ISO 8601), if reported.
    string? creationTime = ();
    # The blob's last-modified timestamp (ISO 8601), if reported.
    string? lastModified = ();
|};
