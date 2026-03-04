// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "AzureSpeechSDK",
    platforms: [.iOS(.v16)],
    products: [
        .library(
            name: "MicrosoftCognitiveServicesSpeech",
            targets: ["MicrosoftCognitiveServicesSpeech"]
        )
    ],
    targets: [
        .binaryTarget(
            name: "MicrosoftCognitiveServicesSpeech",
            url: "https://csspeechstorage.blob.core.windows.net/drop/1.48.1/MicrosoftCognitiveServicesSpeech-XCFramework-1.48.1.zip",
            checksum: "ac702611b2cdf0192c30c929fb6235e51c54354135708632d9dd80622b5ae277"
        )
    ]
)
