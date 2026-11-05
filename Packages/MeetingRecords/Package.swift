// swift-tools-version: 6.0
import PackageDescription

// Meeting records and summaries, shared by the Traqula app (which writes records) and the MCP server (which reads them).
let package = Package(
    name: "MeetingRecords",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "MeetingRecords", targets: ["MeetingRecords"]),
        .library(name: "MeetingSummaries", targets: ["MeetingSummaries"]),
    ],
    targets: [
        .target(name: "MeetingRecords"),
        .target(name: "MeetingSummaries", dependencies: ["MeetingRecords"]),
        .testTarget(name: "MeetingRecordsTests", dependencies: ["MeetingRecords"]),
        .testTarget(name: "MeetingSummariesTests", dependencies: ["MeetingSummaries"]),
    ]
)
