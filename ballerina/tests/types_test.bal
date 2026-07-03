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
import ballerina/test;
import ballerinax/azure_storage_service.blobs;

// ---- Source defaults ---------------------------------------------------------

@test:Config {}
isolated function testSourceDefaults() {
    Source src = {container: "documents"};
    test:assertEquals(src.paths, ["/"], "paths defaults to the whole container");
    test:assertFalse(src.recursive, "recursive defaults to false");
    test:assertTrue(src.includeExtensions is (), "includeExtensions defaults to () (all types)");
}

@test:Config {}
isolated function testSourceExplicitValues() {
    Source src = {
        container: "specs",
        paths: ["/api", "/design.md"],
        recursive: true,
        includeExtensions: ["pdf", ".md"]
    };
    test:assertEquals(src.container, "specs");
    test:assertEquals(src.paths.length(), 2);
    test:assertTrue(src.recursive);
    test:assertEquals(src.includeExtensions, ["pdf", ".md"]);
}

// ---- ConnectionConfig defaults ----------------------------------------------

@test:Config {}
isolated function testConnectionConfigDefaults() {
    ConnectionConfig config = {
        accountName: "acct",
        accessKeyOrSAS: "token",
        authorizationMethod: SAS
    };
    test:assertEquals(config.httpVersion, http:HTTP_1_1, "httpVersion defaults to HTTP/1.1 (matches the connector)");
    test:assertEquals(config.timeout, <decimal>30);
    test:assertEquals(config.forwarded, "disable");
    test:assertEquals(config.compression, http:COMPRESSION_AUTO);
    test:assertTrue(config.validation);
}

// ---- AuthorizationMethod mapping --------------------------------------------

@test:Config {}
isolated function testAuthMethodMapping() {
    test:assertEquals(toConnectorAuthMethod(ACCESS_KEY), blobs:ACCESS_KEY);
    test:assertEquals(toConnectorAuthMethod(SAS), blobs:SAS);
}

// ---- toConnectorConfig forwarding -------------------------------------------

@test:Config {}
isolated function testToConnectorConfigForwardsIdentityAndAuth() {
    ConnectionConfig config = {
        accountName: "contosostorage",
        accessKeyOrSAS: "sv=2022-11-02&sig=abc",
        authorizationMethod: SAS
    };
    blobs:ConnectionConfig mapped = toConnectorConfig(config);
    test:assertEquals(mapped.accountName, "contosostorage");
    test:assertEquals(mapped.accessKeyOrSAS, "sv=2022-11-02&sig=abc");
    test:assertEquals(mapped.authorizationMethod, blobs:SAS);
    test:assertEquals(mapped.httpVersion, http:HTTP_1_1);
    test:assertEquals(mapped.timeout, <decimal>30);
}

@test:Config {}
isolated function testToConnectorConfigForwardsOptionalHttpOptions() {
    ConnectionConfig config = {
        accountName: "acct",
        accessKeyOrSAS: "key",
        authorizationMethod: ACCESS_KEY,
        timeout: 45,
        retryConfig: {count: 3, interval: 1},
        proxy: {host: "proxy.example", port: 8080},
        secureSocket: {enable: false}
    };
    blobs:ConnectionConfig mapped = toConnectorConfig(config);
    test:assertEquals(mapped.authorizationMethod, blobs:ACCESS_KEY);
    test:assertEquals(mapped.timeout, <decimal>45);
    test:assertEquals(mapped.retryConfig?.count, 3);
    test:assertEquals(mapped.proxy?.host, "proxy.example");
    test:assertEquals(mapped.proxy?.port, 8080);
    test:assertTrue(mapped.secureSocket is http:ClientSecureSocket);
}

@test:Config {}
isolated function testToConnectorConfigOmitsUnsetOptionalOptions() {
    ConnectionConfig config = {
        accountName: "acct",
        accessKeyOrSAS: "key",
        authorizationMethod: ACCESS_KEY
    };
    blobs:ConnectionConfig mapped = toConnectorConfig(config);
    test:assertTrue(mapped.retryConfig is (), "An unset retryConfig is not forwarded");
    test:assertTrue(mapped.proxy is (), "An unset proxy is not forwarded");
    test:assertTrue(mapped.circuitBreaker is (), "An unset circuitBreaker is not forwarded");
}

// ---- newBlobClient construction ---------------------------------------------

@test:Config {}
isolated function testNewBlobClientWithSas() returns error? {
    ConnectionConfig config = {
        accountName: "contosostorage",
        accessKeyOrSAS: "sv=2022-11-02&ss=b&srt=co&sp=rl&sig=abc",
        authorizationMethod: SAS
    };
    blobs:BlobClient _ = check newBlobClient(config);
}

@test:Config {}
isolated function testNewBlobClientWithAccessKey() returns error? {
    ConnectionConfig config = {
        accountName: "contosostorage",
        // A syntactically valid base64 access key; no network call is made at construction.
        accessKeyOrSAS: "dGhpcy1pcy1hLWZha2Uta2V5LWZvci10ZXN0aW5n",
        authorizationMethod: ACCESS_KEY
    };
    blobs:BlobClient _ = check newBlobClient(config);
}

// ---- BlobEntry shape ---------------------------------------------------------

@test:Config {}
isolated function testBlobEntryDefaults() {
    BlobEntry entry = {name: "reports/q1.pdf"};
    test:assertEquals(entry.name, "reports/q1.pdf");
    test:assertTrue(entry.contentType is (), "Optional metadata defaults to ()");
    test:assertTrue(entry.contentLength is ());
    test:assertTrue(entry.creationTime is ());
    test:assertTrue(entry.lastModified is ());
}
