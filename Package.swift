// swift-tools-version:4.2
import PackageDescription

let package = Package(
    name: "kineo-endpoint",
	products: [
		.library(name: "KineoEndpoint", targets: ["KineoEndpoint"]),
	],    
    dependencies: [
        .package(url: "https://github.com/kasei/kineo.git", .upToNextMinor(from: "0.0.68")),
        .package(url: "https://github.com/kasei/swift-hdt.git", .upToNextMinor(from: "0.0.5")),
        .package(url: "https://github.com/vapor/vapor.git", .upToNextMinor(from: "3.2.0")),
        .package(url: "https://github.com/alexaubry/HTMLString", .upToNextMinor(from: "4.0.0")),
    ],
    targets: [
    	.target(
    		name: "KineoEndpoint",
			dependencies: ["Kineo", "Vapor", "HDT", "HTMLString"]
    	),
    	.target(
    		name: "kineo-create-db",
            dependencies: ["KineoEndpoint"]
    	),
        .target(
            name: "kineo-endpoint",
            dependencies: ["KineoEndpoint", "Vapor"]
        ),
    ]
)
