// swift-tools-version: 5.10
// Local stub — target is NOT named OnnxRuntimeBindings so canImport(OnnxRuntimeBindings)
// returns false, compiling out all #if canImport(OnnxRuntimeBindings) blocks in Automix.
import PackageDescription

let package = Package(
    name: "onnxruntime-swift-package-manager",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "onnxruntime", targets: ["OnnxRuntimeStubEmpty"]),
    ],
    targets: [
        .target(name: "OnnxRuntimeStubEmpty"),
    ]
)
