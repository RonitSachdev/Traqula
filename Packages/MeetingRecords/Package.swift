// swift-tools-version: 6.0
import PackageDescription

// The meeting record format, shared by the Traqula app (which writes it) and the MCP server (which reads it).
let package = Package(
    name: "MeetingRecords",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "MeetingRecords", targets: ["MeetingRecords"]),
    ],
    targets: [
        .target(name: "MeetingRecords"),
        .testTarget(name: "MeetingRecordsTests", dependencies: ["MeetingRecords"]),
    ]
)
