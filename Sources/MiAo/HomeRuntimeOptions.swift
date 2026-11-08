import AppKit
import ApplicationServices

struct HomeRuntimeOptions: Codable {
    var speechEngine: String? = nil
    var streaming = true
    var automaticSend = false
    var showGuide = false
    static var url: URL { AppPaths.dataDirectory().appendingPathComponent("input-options.json") }
    static func load(from fileURL: URL = url) -> Self {
        (try? JSONDecoder().decode(Self.self, from: Data(contentsOf: fileURL))) ?? Self()
    }
    func save(to fileURL: URL = Self.url) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        try JSONEncoder().encode(self).write(to: fileURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }
    static func finish(_ result: Result<Void, Error>, final: Bool = true) -> Result<Void, Error> {
        guard final, load().automaticSend, case .success = result else { return result }
        guard let app = NSWorkspace.shared.frontmostApplication, app.bundleIdentifier == "com.openai.codex" else {
            return .failure(BridgeError.submission("焦点已离开输入应用，已取消自动发送"))
        }
        var focused: CFTypeRef?
        let element = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementCopyAttributeValue(element, kAXFocusedUIElementAttribute as CFString, &focused)
        guard let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else {
            return .failure(BridgeError.submission("无法确认输入框，已取消自动发送"))
        }
        var role: CFTypeRef?
        AXUIElementCopyAttributeValue(focused as! AXUIElement, kAXRoleAttribute as CFString, &role)
        guard [kAXTextAreaRole, kAXTextFieldRole].contains(role as? String ?? "") else {
            return .failure(BridgeError.submission("焦点不是文本框，已取消自动发送"))
        }
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: nil, virtualKey: 36, keyDown: down)
            event?.flags = []
            event?.post(tap: .cghidEventTap)
        }
        return result
    }
}
