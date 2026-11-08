import Foundation

struct QwenRuntimeConfiguration: Codable {
    let pythonPath: String
    let modelPath: String
    let modelSHA256: String

    static var url: URL {
        AppPaths.dataDirectory().appendingPathComponent("qwen-runtime.json")
    }
    static var isConfigured: Bool { FileManager.default.fileExists(atPath: url.path) }

    static func load(from fileURL: URL = url) throws -> Self {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw BridgeError.transcription("尚未配置 Qwen 模型，请点击配置模型选择已安装的模型与运行环境")
        }
        let stored = try JSONDecoder().decode(Self.self, from: Data(contentsOf: fileURL))
        func resolve(_ path: String) -> String {
            let expanded = NSString(string: path).expandingTildeInPath
            return expanded.hasPrefix("/")
                ? expanded
                : fileURL.deletingLastPathComponent()
                    .appendingPathComponent(expanded).standardizedFileURL.path
        }
        let config = Self(
            pythonPath: resolve(stored.pythonPath), modelPath: resolve(stored.modelPath),
            modelSHA256: stored.modelSHA256)
        guard config.modelSHA256.count == 64,
            config.modelSHA256.allSatisfy({ $0.isHexDigit }),
            FileManager.default.isExecutableFile(atPath: config.pythonPath),
            FileManager.default.fileExists(atPath: config.modelPath + "/model.safetensors")
        else { throw BridgeError.transcription("Qwen运行环境或模型不可用，请在设置中重新选择模型文件夹与 Python 运行环境") }
        #if !arch(arm64)
            throw BridgeError.transcription("Qwen MLX 引擎需要 Apple Silicon；Intel Mac 请使用 Whisper")
        #else
            return config
        #endif
    }

}

// SpeechJobQueue serializes calls; the lock also protects future callers.
final class QwenTranscriber: @unchecked Sendable {
    private let configuration: QwenRuntimeConfiguration
    private let lock = NSLock()
    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var pending = Data()

    init() throws { configuration = try QwenRuntimeConfiguration.load() }
    deinit { if process?.isRunning == true { process?.terminate() } }

    func warmUp() throws {
        lock.lock()
        defer { lock.unlock() }
        do {
            if process?.isRunning != true { try start() }
        } catch {
            resetWorker()
            throw error
        }
    }

    func transcribe(wavURL: URL) throws -> String {
        lock.lock()
        defer { lock.unlock() }
        do {
            if process?.isRunning != true { try start() }
            let id = UUID().uuidString
            var request = try JSONSerialization.data(withJSONObject: ["id": id, "audio": wavURL.path])
            request.append(10)
            try input?.write(contentsOf: request)
            let response = try readResponse()
            guard response["id"] as? String == id, let text = response["text"] as? String else {
                throw BridgeError.transcription(response["error"] as? String ?? "Qwen返回格式无效")
            }
            return text
        } catch {
            resetWorker()
            throw error
        }
    }

    private func resetWorker() {
        if process?.isRunning == true { process?.terminate() }
        process = nil
        input = nil
        output = nil
        pending.removeAll()
    }

    private func start() throws {
        guard let worker = Bundle.main.resourceURL?.appendingPathComponent("Runtime/scripts/qwen_worker.py"),
            FileManager.default.fileExists(atPath: worker.path)
        else { throw BridgeError.transcription("当前遥声缺少Qwen运行组件，请重新安装") }
        let task = Process()
        let stdin = Pipe()
        let stdout = Pipe()
        task.executableURL = URL(fileURLWithPath: configuration.pythonPath)
        task.arguments = ["-u", worker.path, QwenRuntimeConfiguration.url.path]
        task.standardInput = stdin
        task.standardOutput = stdout
        let log = QwenRuntimeConfiguration.url.deletingLastPathComponent().appendingPathComponent("qwen-worker.log")
        if !FileManager.default.fileExists(atPath: log.path) {
            FileManager.default.createFile(atPath: log.path, contents: nil, attributes: [.posixPermissions: 0o600])
        }
        let logHandle = try FileHandle(forWritingTo: log)
        try logHandle.seekToEnd()
        task.standardError = logHandle
        try task.run()
        process = task
        input = stdin.fileHandleForWriting
        output = stdout.fileHandleForReading
        let ready = try readResponse()
        guard ready["ready"] as? Bool == true else {
            throw BridgeError.transcription(ready["error"] as? String ?? "Qwen加载失败")
        }
    }

    private func readResponse() throws -> [String: Any] {
        guard let output, let process else { throw BridgeError.transcription("Qwen进程未启动") }
        let timeout = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 90, execute: timeout)
        defer { timeout.cancel() }
        while true {
            if let end = pending.firstIndex(of: 10) {
                let line = pending.prefix(upTo: end)
                pending.removeSubrange(...end)
                guard let value = try JSONSerialization.jsonObject(with: line) as? [String: Any] else {
                    throw BridgeError.transcription("Qwen返回格式无效")
                }
                return value
            }
            let chunk = output.availableData
            guard !chunk.isEmpty else { throw BridgeError.transcription("Qwen进程退出或识别超时，请查看 qwen-worker.log") }
            pending.append(chunk)
            guard pending.count < 1_000_000 else { throw BridgeError.transcription("Qwen返回数据过大") }
        }
    }
}
