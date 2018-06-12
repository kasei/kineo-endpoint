// swift-tools-version:4.0
import PackageDescription

let package = Package(
    name: "kineo-endpoint",
    dependencies: [
		.package(url: "https://github.com/kasei/kineo.git", from: "0.0.6"),
        .package(url: "https://github.com/vapor/vapor.git", from: "3.0.0"),
    ],
    targets: [
        .target(
            name: "kineo-endpoint",
            dependencies: ["Kineo", "Vapor"]
        ),
    ]
)
