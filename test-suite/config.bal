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

// A standalone integration test suite for the Azure Blob Storage `TextDataLoader`. Unlike
// the module's in-package unit tests, this package can only exercise the public API, so it
// runs end-to-end against a real Azure Blob Storage account: it seeds a dedicated container
// with fixtures of every supported and unsupported format (including a 12-page PDF), runs
// the loader across every configuration case, asserts the results, then deletes what it
// created. See `tests/` for the scenarios and `Config.toml.template` for setup.

import ballerinax/ai.azure.storage.blob;

// Read from Config.toml (see Config.toml.template).
configurable string accountName = ?;
configurable string accessKeyOrSAS = ?;
configurable string authMethod = "ACCESS_KEY";
configurable string testContainer = "loader-test-suite";

// The connection configuration passed to the loader under test.
isolated function connectionConfig() returns blob:ConnectionConfig => {
    accountName,
    accessKeyOrSAS,
    authorizationMethod: authMethod == "SAS" ? blob:SAS : blob:ACCESS_KEY
};
