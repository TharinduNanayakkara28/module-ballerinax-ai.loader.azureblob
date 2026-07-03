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

import ballerina/ai;
import ballerina/http;
import ballerinax/azure_storage_service.blobs;

// Maps this loader's `AuthorizationMethod` onto the connector's, keeping our public enum
// decoupled from the connector's (so the two can evolve independently).
isolated function toConnectorAuthMethod(AuthorizationMethod method) returns blobs:AuthorizationMethod =>
    method == ACCESS_KEY ? blobs:ACCESS_KEY : blobs:SAS;

// Builds the connector's `ConnectionConfig` from the loader's, forwarding the account
// identity, the auth method, and every HTTP-level option the connector supports. Optional
// HTTP options are forwarded only when set, so the connector's own defaults apply otherwise.
isolated function toConnectorConfig(ConnectionConfig config) returns blobs:ConnectionConfig {
    blobs:ConnectionConfig connectorConfig = {
        accountName: config.accountName,
        accessKeyOrSAS: config.accessKeyOrSAS,
        authorizationMethod: toConnectorAuthMethod(config.authorizationMethod),
        httpVersion: config.httpVersion,
        timeout: config.timeout,
        forwarded: config.forwarded,
        compression: config.compression,
        validation: config.validation
    };
    http:ClientHttp2Settings? http2Settings = config.http2Settings;
    if http2Settings is http:ClientHttp2Settings {
        connectorConfig.http2Settings = http2Settings;
    }
    http:PoolConfiguration? poolConfig = config.poolConfig;
    if poolConfig is http:PoolConfiguration {
        connectorConfig.poolConfig = poolConfig;
    }
    http:CacheConfig? cache = config.cache;
    if cache is http:CacheConfig {
        connectorConfig.cache = cache;
    }
    http:CircuitBreakerConfig? circuitBreaker = config.circuitBreaker;
    if circuitBreaker is http:CircuitBreakerConfig {
        connectorConfig.circuitBreaker = circuitBreaker;
    }
    http:RetryConfig? retryConfig = config.retryConfig;
    if retryConfig is http:RetryConfig {
        connectorConfig.retryConfig = retryConfig;
    }
    http:ResponseLimitConfigs? responseLimits = config.responseLimits;
    if responseLimits is http:ResponseLimitConfigs {
        connectorConfig.responseLimits = responseLimits;
    }
    http:ClientSecureSocket? secureSocket = config.secureSocket;
    if secureSocket is http:ClientSecureSocket {
        connectorConfig.secureSocket = secureSocket;
    }
    http:ProxyConfig? proxy = config.proxy;
    if proxy is http:ProxyConfig {
        connectorConfig.proxy = proxy;
    }
    return connectorConfig;
}

// Constructs the underlying Azure Blob Storage connector client from the loader's
// `ConnectionConfig`, wrapping any construction failure as an `ai:Error`.
isolated function newBlobClient(ConnectionConfig config) returns blobs:BlobClient|ai:Error {
    blobs:BlobClient|error blobClient = new (toConnectorConfig(config));
    if blobClient is error {
        return error ai:Error(
            string `Failed to initialize the Azure Blob Storage client: ${blobClient.message()}`, blobClient);
    }
    return blobClient;
}
