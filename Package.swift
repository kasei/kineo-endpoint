// swift-tools-version:4.0
import PackageDescription

let package = Package(
    name: "kineo-endpoint",
    dependencies: [
        .package(url: "https://github.com/kasei/kineo.git", .upToNextMinor(from: "0.0.21")),
        .package(url: "https://github.com/vapor/vapor.git", .upToNextMinor(from: "3.0.0")),
    ],
    targets: [
    	.target(
    		name: "kineo-create-db",
            dependencies: ["Kineo"]
    	),
        .target(
            name: "kineo-endpoint",
            dependencies: ["Kineo", "Vapor"]
        ),
    ]
)
