// swift-tools-version: 6.0
import PackageDescription

let package = Package(
	name: "NewsApp",
	platforms: [
		.macOS(.v15), // macOS 26 target — update to .v26 once Swift toolchain adds the enum case
	],
	dependencies: [
		.package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
		.package(url: "https://github.com/nmdias/FeedKit.git", from: "9.1.2"),
	],
	targets: [
		.executableTarget(
			name: "NewsApp",
			dependencies: [
				.product(name: "GRDB", package: "GRDB.swift"),
				.product(name: "FeedKit", package: "FeedKit"),
			],
			path: "Sources/NewsApp",
			resources: [
				.process("Resources"),
			],
		),
	]
)
