import Foundation

/// All mutable files belong to the current user, never to the source checkout or app bundle.
enum AppPaths {
    static func dataDirectory(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        directory(
            override: environment["VOICE_BRIDGE_DATA_DIR"], home: home,
            fallback: "Library/Application Support/RemoteVoice")
    }

    static func modelDirectory(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        directory(
            override: environment["VOICE_BRIDGE_MODEL_DIR"], home: home,
            fallback: ".cache/RemoteVoice")
    }

    private static func directory(override: String?, home: URL, fallback: String) -> URL {
        guard let value = override, !value.isEmpty else {
            return home.appendingPathComponent(fallback, isDirectory: true)
        }
        if value == "~" { return home }
        if value.hasPrefix("~/") {
            return home.appendingPathComponent(String(value.dropFirst(2)), isDirectory: true)
        }
        return URL(fileURLWithPath: value, isDirectory: true)
    }
}
