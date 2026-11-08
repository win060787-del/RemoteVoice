import Foundation

struct DirectButtonMapping {
    static func edited(_ original: ButtonPreset, button: RemoteButton, binding: ButtonBinding) throws -> ButtonPreset {
        guard button.isUserEditable else { throw BridgeError.configuration("语音与菜单为保留按键") }
        var bindings = original.bindings
        bindings[button] = binding
        return ButtonPreset(
            id: original.isBuiltIn ? "user." + UUID().uuidString.lowercased() : original.id,
            name: original.isBuiltIn ? "我的遥控器" : original.name,
            bindings: bindings, requiredButtons: original.requiredButtons, isBuiltIn: false)
    }
}
