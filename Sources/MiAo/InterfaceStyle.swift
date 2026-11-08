import AppKit

enum InterfaceStyle {
    static var theme: String { UserDefaults.standard.string(forKey: "RemoteVoice.theme") ?? "system" }
    static var language: String { UserDefaults.standard.string(forKey: "RemoteVoice.language") ?? "zh" }
    static var dark: Bool {
        theme == "dark" || (theme == "system" && UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark")
    }
    static var appearance: NSAppearance? { NSAppearance(named: dark ? .darkAqua : .aqua) }
    static var background: NSColor { NSColor(white: dark ? 0.085 : 0.965, alpha: 1) }
    static var surface: NSColor { NSColor(white: dark ? 0.13 : 1, alpha: 1) }
    static var textColor: NSColor { NSColor(white: dark ? 0.91 : 0.14, alpha: 1) }
    static func text(_ source: String, language: String = language) -> String {
        guard language == "en" else { return source }
        if let value = translations[source] { return value }
        if source.hasPrefix("扫描中 · 发现 ") {
            return source.replacingOccurrences(of: "扫描中 · 发现 ", with: "Scanning · ")
                .replacingOccurrences(of: " 台设备", with: " devices found")
        }
        if source.hasPrefix("发现 ") {
            return source.replacingOccurrences(of: "发现 ", with: "Found ")
                .replacingOccurrences(of: " 台设备；请选择兼容遥控器。", with: " devices. Select a compatible remote.")
        }
        let fragments = [
            "系统保留按键": "Reserved system button",
            "Qwen Qwen3-ASR-1.7B · 8 位 · Mac 本地识别": "Qwen3-ASR-1.7B · 8-bit · Local inference",
            "满足 macOS 14+": "macOS 14+ supported",
            "App 内置门禁与恢复组件可用": "Bundled runtime and recovery components available",
            "Codex 已运行；遥声会启用运行时辅助功能，并在填入前核验输入框，无需重启":
                "Codex is running. RemoteVoice checks editor focus before inserting text; no restart required.",
        ]
        var result = source
        for (key, value) in fragments { result = result.replacingOccurrences(of: key, with: value) }
        return result.replacingOccurrences(of: "● 已连接", with: "● Connected").replacingOccurrences(
            of: "● 未连接", with: "● Disconnected")
    }
    @MainActor
    static func apply(_ view: NSView) {
        if let popup = view as? NSPopUpButton {
            for item in popup.itemArray { item.title = text(item.title) }
        } else if let button = view as? NSButton, button.imagePosition != .imageOnly {
            button.title = text(button.title)
        }
        if let label = view as? NSTextField { label.stringValue = text(label.stringValue) }
        if let segments = view as? NSSegmentedControl {
            for index in 0..<segments.segmentCount {
                segments.setLabel(text(segments.label(forSegment: index) ?? ""), forSegment: index)
            }
        }
        if let label = view.accessibilityLabel() { view.setAccessibilityLabel(text(label)) }
        if let tip = view.toolTip { view.toolTip = text(tip) }
        view.subviews.forEach(apply)
    }
    private static let translations: [String: String] = [
        "尚未扫描": "Not scanned yet", "正在准备蓝牙扫描…": "Preparing Bluetooth scan…",
        "正在等待蓝牙状态或系统授权…": "Waiting for Bluetooth or system permission…",
        "未发现正在广播的 BLE 设备，请唤醒遥控器后重新扫描。": "No advertising BLE devices found. Wake the remote and scan again.",
        "电池状态未知": "Battery status unknown", "独立读取遥控器电量，点击刷新": "Read battery independently. Click to refresh.",
        "遥控器连接状态，点击显示配置指南": "Remote connection. Click for connection and permissions.",
        "更换遥控器在下次启动语音服务时生效": "Restart dictation after selecting another remote.",
        "放大": "Zoom in", "缩小": "Zoom out",
        "三维遥控器，可拖动旋转和缩放": "3D remote. Drag to rotate; use the zoom buttons to resize.",
        "选择 Qwen3-ASR 的 MLX 模型文件夹": "Choose the Qwen3-ASR MLX model folder",
        "选择已安装 mlx-audio 的 Python 可执行文件": "Choose Python with mlx-audio installed",
        "设备 · 兼容性 · 信号": "Device · Compatibility · Signal", "兼容": "Compatible", "不支持": "Unsupported",
        "已连接": "Connected",
        "语音输入": "Dictation", "遥控器": "Remote", "模型与系统": "Models & System",
        "启动语音服务": "Start dictation", "停止语音服务": "Stop dictation", "转录方式": "Transcription",
        "整段": "On release", "逐句": "Live", "填入输入框": "Insert into editor", "自动发送": "Send automatically",
        "设备选择": "Device", "扫描": "Scan", "控制模式": "Control mode", "鼠标": "Pointer", "聚焦": "Focus",
        "按键控制": "Remote controls", "语音连接": "Voice connection", "随时就绪": "Always ready", "智能休眠": "Smart sleep",
        "本机引擎": "Local engine", "配置 Qwen…": "Configure Qwen…", "修复 Whisper": "Repair Whisper",
        "登录时启动": "Launch at login", "辅助功能 · 去授权": "Allow Accessibility…", "辅助功能 · 已授权": "Accessibility enabled",
        "外观": "Appearance", "跟随系统": "System", "浅色": "Light", "深色": "Dark", "界面语言": "Language",
        "自动选择遥控器": "Automatic selection", "已保存的遥控器": "Saved remote", "重新扫描": "Scan again",
        "附近蓝牙设备": "Nearby Bluetooth devices", "选择遥控器": "Choose a remote", "取消": "Cancel", "使用设备": "Use device",
        "连接与权限": "Connection & Permissions", "macOS 版本": "macOS", "本地语音引擎": "Local speech engine",
        "遥声辅助功能": "Accessibility", "蓝牙权限": "Bluetooth", "Codex 输入区": "Codex editor", "启动组件": "Runtime",
        "配置模型…": "Configure…", "打开设置…": "Settings…", "允许蓝牙…": "Allow Bluetooth…", "蓝牙设置…": "Bluetooth…",
        "显示应用": "Show app", "重新检查": "Refresh", "完成": "Done", "保存": "Save", "关闭": "Close",
        "蓝牙已连接，语音服务尚未就绪": "Bluetooth connected; dictation is not running",
        "语音连接已建立": "Voice connection ready", "点击检查连接与权限": "Click to check connection and permissions",
        "逐句输入仅支持 Qwen；Whisper 在松开后整段识别": "Live dictation requires Qwen. Whisper transcribes on release.",
        "需要蓝牙权限；点击电池可重试或申请授权": "Bluetooth permission is required. Click to allow or retry.",
        "请在系统辅助功能设置中允许当前“遥声”应用": "Allow this RemoteVoice app in System Settings > Accessibility.",
        "已允许连接和读取语音遥控器": "Bluetooth access is allowed.",
        "尚未请求；点击后由 macOS 显示系统授权框": "Not requested. Click to show the macOS permission prompt.",
        "整段：松开后一次转录。逐句：说话时分段识别并更新输入框，目前仅支持 Qwen。":
            "On release transcribes the complete recording. Live updates the editor while speaking and requires Qwen.",
        "开启后把识别结果填入当前输入框；关闭后只保留本地转写。":
            "Insert recognized text into the current editor, or keep only the local transcript when disabled.",
        "默认关闭。开启后在最终转写完成、输入焦点核验成功时发送。":
            "Off by default. Send only after the final transcript is inserted and editor focus is verified.",
        "鼠标模式移动指针、确认键为左键；聚焦模式使用方向键、确认键为回车。TV 键也可切换。":
            "Pointer moves the cursor and confirms with a click. Focus sends arrow keys and Return. TV also switches modes.",
        "使用遥控器控制鼠标和键盘。此项在重启语音服务后生效。":
            "Control the pointer and keyboard using the remote. Restart dictation to apply this change.",
        "随时就绪会自动恢复连接；智能休眠在连续失败后等待按键唤醒。":
            "Always ready reconnects automatically. Smart sleep waits for a button press after repeated failures.",
        "Whisper 使用整段转录；Qwen 支持分段输入，需要已配置本地模型。切换后重启服务生效。":
            "Whisper transcribes on release. Qwen supports live updates and needs a configured local model. Restart dictation after switching.",
        "登录 macOS 后自动启动遥声，由系统登录项管理。": "Start RemoteVoice when you sign in to macOS, managed by Login Items.",
        "扫描并选择已配对的兼容遥控器，更换设备后重启语音服务生效。":
            "Scan for a compatible paired remote. Restart dictation after choosing another device.",
        "选择本机 Qwen 模型文件夹和 Python 运行环境。": "Select the local Qwen model folder and Python environment.",
        "安装或修复 Whisper 及其本地识别模型。": "Install or repair Whisper and its local model.",
        "打开 macOS 辅助功能授权设置。": "Open macOS Accessibility permissions.",
        "检查环境并启动语音与按键服务。": "Check requirements and start dictation and remote controls.",
        "中间确认": "Confirm", "返回": "Back", "电源": "Power", "语音": "Voice", "菜单": "Menu",
        "系统原生鼠标右键": "Native secondary click", "系统保留按键": "Reserved system button",
        "点击编辑映射  ›": "Click to edit mapping  ›",
    ]
}
