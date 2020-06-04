// swift-tools-version:5.2
import PackageDescription

let package = Package(
    name: "kineo-endpoint",
    platforms: [.macOS(.v10_15)],
	products: [
		.library(name: "KineoEndpoint", targets: ["KineoEndpoint"]),
	],    
    dependencies: [
//        .package(name: "Kineo", url: "https://github.com/kasei/kineo.git", .upToNextMinor(from: "0.0.81")),
        .package(name: "Kineo", url: "https://github.com/kasei/kineo.git", .branch("sparql-12")),
        .package(name: "Vapor", url: "https://github.com/vapor/vapor.git", from: "3.2.0"),
        .package(name: "HTMLString", url: "https://github.com/alexaubry/HTMLString", .upToNextMinor(from: "4.0.0")),
       .package(name: "Diomede", url: "https://github.com/kasei/diomede.git", .upToNextMinor(from: "0.0.16")),
//        .package(url: "https://github.com/kasei/swift-hdt.git", .upToNextMinor(from: "0.0.6")),
    ],
    targets: [
    	.target(
    		name: "KineoEndpoint",
			dependencies: [
				"Kineo",
				"Vapor",
				.product(name: "DiomedeQuadStore", package: "Diomede"),
//				"HDT",
				"HTMLString"
			]
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
