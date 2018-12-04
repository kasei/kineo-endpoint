// swift-tools-version:4.2
import PackageDescription

let package = Package(
    name: "kineo-endpoint",
	products: [
		.library(name: "KineoEndpoint", targets: ["KineoEndpoint"]),
	],    
    dependencies: [
        .package(url: "https://github.com/kasei/kineo.git", .upToNextMinor(from: "0.0.50")),
        .package(url: "https://github.com/kasei/swift-hdt.git", .upToNextMinor(from: "0.0.4")),
        .package(url: "https://github.com/vapor/vapor.git", .upToNextMinor(from: "3.1.0")),
    ],
    targets: [
    	.target(
    		name: "KineoEndpoint",
			dependencies: ["Kineo", "Vapor", "HDT"]
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
