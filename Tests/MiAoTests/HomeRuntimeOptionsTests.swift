import Foundation
import Testing

@testable import MiAo

@Test func inlineInputDefaultsKeepAutomaticSendingOff() {
    let options = HomeRuntimeOptions.load(from: URL(fileURLWithPath: "/nonexistent/remotevoice-options.json"))
    #expect(!options.automaticSend)
    #expect(options.speechEngine == nil)
}

@Test func inlineOptionsPersistPrivatelyAcrossReopen() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("input-options.json")
    var options = HomeRuntimeOptions()
    options.streaming = false
    options.showGuide = true
    options.speechEngine = "qwen"
    try options.save(to: file)
    let readback = HomeRuntimeOptions.load(from: file)
    #expect(!readback.streaming)
    #expect(readback.showGuide)
    #expect(readback.speechEngine == "qwen")
    #expect(!readback.automaticSend)
    let permissions = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber
    #expect(permissions?.intValue == 0o600)
}
