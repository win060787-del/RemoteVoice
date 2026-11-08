import Darwin
import Foundation

struct RemoteDeviceStatus: Codable {
    var connected: Bool
    var processID: Int32
    var battery: Int?
    static var url: URL { AppPaths.dataDirectory().appendingPathComponent("device-status.json") }
    static var runtimeActive: Bool {
        let file = AppPaths.dataDirectory().appendingPathComponent("runtime.lock/pid")
        guard let value = try? String(contentsOf: file, encoding: .utf8),
            let pid = Int32(value.trimmingCharacters(in: .whitespacesAndNewlines)), pid > 0
        else { return false }
        return kill(pid, 0) == 0
    }
    static func update(connected: Bool) {
        let value = Self(connected: connected, processID: getpid(), battery: nil)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(value).write(to: url, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    static func updateBattery(_ level: UInt8) {
        guard level <= 100 else { return }
        let value = Self(connected: true, processID: getpid(), battery: Int(level))
        try? JSONEncoder().encode(value).write(to: url, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    static func load() -> Self {
        guard let data = try? Data(contentsOf: url), let value = try? JSONDecoder().decode(Self.self, from: data),
            kill(value.processID, 0) == 0
        else {
            return Self(connected: false, processID: 0, battery: nil)
        }
        return value
    }
}
