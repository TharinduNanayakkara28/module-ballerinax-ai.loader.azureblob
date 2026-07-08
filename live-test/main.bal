import ballerina/ai;
import ballerina/io;
import ballerinax/ai.azure.storage.blob;

// These are read from Config.toml (see Config.toml.template).
configurable string accountName = ?;
configurable string accessKeyOrSAS = ?;
configurable string authMethod = "ACCESS_KEY"; // "ACCESS_KEY" or "SAS"
configurable string container = ?;

public function main() returns error? {
    blob:AuthorizationMethod method = authMethod == "SAS" ? blob:SAS : blob:ACCESS_KEY;

    io:println("Connecting to account '", accountName, "', container '", container, "' ...");

    blob:TextDataLoader loader = check new (
        {
            accountName,
            accessKeyOrSAS,
            authorizationMethod: method
        },
        [
            {
                container,
                paths: ["/"],       // whole container
                recursive: true     // include virtual sub-folders
            }
        ]
    );

    ai:Document[]|ai:Document result = check loader.load();
    ai:Document[] documents = result is ai:Document[] ? result : [result];

    io:println("\n=== Loaded ", documents.length(), " document(s) ===\n");
    foreach ai:Document doc in documents {
        if doc is ai:TextDocument {
            anydata metadata = doc.metadata;
            string content = doc.content;
            io:println("--------------------------------------------------");
            io:println("metadata : ", metadata.toString());
            io:println("chars    : ", content.length());
            io:println("content  :\n", content);
        }
    }
    io:println("\nDone.");
}
