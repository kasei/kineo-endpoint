// swift-tools-version:4.0
import PackageDescription

let package = Package(
    name: "kineo-endpoint",
	products: [
		.library(name: "KineoEndpoint", targets: ["KineoEndpoint"]),
	],    
    dependencies: [
        .package(url: "https://github.com/kasei/kineo.git", .upToNextMinor(from: "0.0.31")),
        .package(url: "https://github.com/vapor/vapor.git", .upToNextMinor(from: "3.0.0")),
    ],
    targets: [
    	.target(
    		name: "KineoEndpoint",
			dependencies: ["Kineo", "Vapor"]
    	),
    	.target(
    		name: "kineo-create-db",
            dependencies: ["Kineo"]
    	),
        .target(
            name: "kineo-endpoint",
            dependencies: ["KineoEndpoint", "Vapor"]
        ),
    ]
)
