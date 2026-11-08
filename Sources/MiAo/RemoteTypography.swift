import AppKit

enum RemoteTypography {
    static func font(ofSize size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        let name =
            weight >= .semibold ? "PingFangSC-Semibold" : weight >= .medium ? "PingFangSC-Medium" : "PingFangSC-Regular"
        return NSFont(name: name, size: size) ?? NSFont.systemFont(ofSize: size, weight: weight)
    }
}
