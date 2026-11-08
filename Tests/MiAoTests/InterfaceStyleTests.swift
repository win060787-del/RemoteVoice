import Testing

@testable import MiAo

@Test func interfaceLanguagesTranslateControlsAndKeepDeviceNames() {
    #expect(InterfaceStyle.text("设备选择", language: "en") == "Device")
    #expect(InterfaceStyle.text("启动语音服务", language: "en") == "Start dictation")
    #expect(InterfaceStyle.text("启动语音服务", language: "zh") == "启动语音服务")
    #expect(InterfaceStyle.text("Qwen3-ASR-1.7B", language: "en") == "Qwen3-ASR-1.7B")
    #expect(InterfaceStyle.text("● 已连接", language: "en") == "● Connected")
}
