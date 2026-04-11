import Foundation
import XCTest
@testable import OpenType

final class UtilityTests: XCTestCase {
    func testModelStorageMakesStableLocalIDs() {
        XCTAssertEqual(ModelStorage.makeLocalID(
            prefix: "llm",
            folderName: "Qwen",
            existing: []
        ), "local/llm-Qwen")
        XCTAssertEqual(ModelStorage.makeLocalID(
            prefix: "whisper",
            folderName: "",
            existing: []
        ), "local/whisper-model")
        XCTAssertEqual(ModelStorage.makeLocalID(
            prefix: "llm",
            folderName: "Qwen",
            existing: ["local/llm-Qwen"]
        ), "local/llm-Qwen-2")
        XCTAssertEqual(ModelStorage.makeLocalID(
            prefix: "llm",
            folderName: "Qwen",
            existing: ["local/llm-Qwen", "local/llm-Qwen-2"]
        ), "local/llm-Qwen-3")
    }

    func testModelStorageDirectorySize() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenTypeTests-\(UUID().uuidString)", isDirectory: true)
        let nested = root.appendingPathComponent("nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 12).write(to: root.appendingPathComponent("a.bin"))
        try Data(repeating: 2, count: 8).write(to: nested.appendingPathComponent("b.bin"))
        defer { try? FileManager.default.removeItem(at: root) }

        XCTAssertEqual(ModelStorage.directorySize(at: root), 20)
        XCTAssertEqual(ModelStorage.directorySize(at: root.appendingPathComponent("missing")), 0)
    }

    func testGzipRoundTripForTextAndBinaryData() throws {
        let text = Data("OpenType voice input. 你好，世界。".utf8)
        let compressedText = try XCTUnwrap(Gzip.compress(text))
        XCTAssertGreaterThan(compressedText.count, 18)
        XCTAssertEqual(Gzip.decompress(compressedText), text)

        let binary = Data((0..<255).map(UInt8.init))
        let compressedBinary = try XCTUnwrap(Gzip.compress(binary))
        XCTAssertEqual(Gzip.decompress(compressedBinary), binary)
    }

    func testGzipHandlesEmptyAndInvalidInput() throws {
        XCTAssertEqual(Gzip.compress(Data()), Data())
        XCTAssertNil(Gzip.decompress(Data()))
        XCTAssertNil(Gzip.decompress(Data("not gzip".utf8)))

        var truncated = try XCTUnwrap(Gzip.compress(Data("hello".utf8)))
        truncated.removeLast(4)
        XCTAssertNil(Gzip.decompress(truncated))
    }
}
