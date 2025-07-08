// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "RestaurantDemo",
    platforms: [
        .iOS(.v15)
    ],
    products: [
        .library(
            name: "RestaurantDemo",
            targets: ["RestaurantDemo"]),
    ],
    dependencies: [
        // Add dependencies here if needed
        .package(url: "https://github.com/onevcat/Kingfisher.git", from: "7.0.0")
    ],
    targets: [
        .target(
            name: "RestaurantDemo",
            dependencies: [
                .product(name: "Kingfisher", package: "Kingfisher")
            ],
            path: ".",
            exclude: [
                "backend", "backend-deploy", "functions", "uploads", "Restaurant Demo.xcodeproj", "Restaurant DemoTests", "Restaurant DemoUITests", "node_modules"
            ],
            sources: [
                "."
            ]
        )
    ]
)

#if DEBUG
print("Running in development (debug) mode")
#else
print("Running in production (release) mode")
#endif