import Foundation
import Testing

@testable import MiAo

@Test func portablePathsBelongToEachUserAndRespectOverrides() {
    let home = URL(fileURLWithPath: "/tmp/another-person", isDirectory: true)
    #expect(
        AppPaths.dataDirectory(environment: [:], home: home).path
            == "/tmp/another-person/Library/Application Support/RemoteVoice")
    #expect(AppPaths.modelDirectory(environment: [:], home: home).path == "/tmp/another-person/.cache/RemoteVoice")
    #expect(
        AppPaths.dataDirectory(environment: ["VOICE_BRIDGE_DATA_DIR": "~/Custom Data"], home: home).path
            == "/tmp/another-person/Custom Data")
    #expect(
        AppPaths.modelDirectory(environment: ["VOICE_BRIDGE_MODEL_DIR": "/tmp/models"], home: home).path
            == "/tmp/models")
}

@Test func newInstallHasNoPersonalDeviceOrNameFilter() {
    let defaults = AppPreferences.defaults
    #expect(defaults.preferredPeripheralIdentifier == nil)
    #expect(!defaults.runtimeArguments.contains("--identifier"))
    #expect(!defaults.runtimeArguments.contains("--name"))
    #expect(defaults.selectedPresetID == ButtonPreset.pointer.id)
}

@Test func tvModeSurvivesCatalogReloadAndCanStillToggle() throws {
    var changes: [RemoteControlMode] = []
    let executor = ButtonActionExecutor(preset: .pointer, controlModeHandler: { changes.append($0) })
    executor.buttonDown(.tv)
    #expect(executor.controlMode == .directional)
    try executor.replaceCatalog(.builtIn, selecting: "pointer")
    #expect(executor.controlMode == .directional)
    #expect(changes == [.directional])
    executor.buttonDown(.tv)
    #expect(executor.controlMode == .pointer)
}

@Test func tvModeSurvivesPresetSwitchAndRestart() throws {
    var bindings = ButtonPreset.pointer.bindings
    bindings[.tv] = .presetSwitch("user.test")
    let custom = ButtonPreset(
        id: "user.test", name: "另一配置", bindings: ButtonPreset.pointer.bindings,
        requiredButtons: ButtonPreset.pointer.requiredButtons, isBuiltIn: false)
    let source = ButtonPreset(
        id: "user.source", name: "起始配置", bindings: bindings,
        requiredButtons: ButtonPreset.pointer.requiredButtons, isBuiltIn: false)
    let executor = ButtonActionExecutor(
        preset: source, catalog: ButtonPresetCatalog(userPresets: [source, custom]),
        initialControlMode: .directional)
    executor.buttonDown(.tv)
    #expect(executor.preset.id == custom.id)
    #expect(executor.controlMode == .directional)
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = AppPreferencesStore(fileURL: root.appendingPathComponent("preferences.json"))
    var preferences = AppPreferences.defaults
    preferences.controlMode = executor.controlMode
    try store.save(preferences)
    let restored = ButtonActionExecutor(preset: .pointer, initialControlMode: store.load().preferences.controlMode)
    #expect(restored.controlMode == .directional)
}

@Test func oldPreferencesMigrateWithoutResettingOtherOptions() throws {
    let preferences = try JSONDecoder().decode(
        AppPreferences.self, from: Data("{\"schemaVersion\":3,\"selectedPresetID\":\"user.saved\"}".utf8))
    #expect(preferences.controlMode == .pointer)
    #expect(preferences.selectedPresetID == "user.saved")
}

#if arch(arm64)
    @Test func qwenConfigurationResolvesRelativePathsAfterMovingItsDirectory() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let original = root.appendingPathComponent("original")
        try FileManager.default.createDirectory(
            at: original.appendingPathComponent("model"), withIntermediateDirectories: true)
        try Data().write(to: original.appendingPathComponent("model/model.safetensors"))
        let python = original.appendingPathComponent("python")
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: python)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: python.path)
        let config = QwenRuntimeConfiguration(
            pythonPath: "python", modelPath: "model", modelSHA256: String(repeating: "a", count: 64))
        try JSONEncoder().encode(config).write(to: original.appendingPathComponent("qwen-runtime.json"))
        let moved = root.appendingPathComponent("Moved with spaces")
        try FileManager.default.moveItem(at: original, to: moved)
        let loaded = try QwenRuntimeConfiguration.load(from: moved.appendingPathComponent("qwen-runtime.json"))
        #expect(loaded.pythonPath == moved.appendingPathComponent("python").path)
        #expect(loaded.modelPath == moved.appendingPathComponent("model").path)
    }
#endif
