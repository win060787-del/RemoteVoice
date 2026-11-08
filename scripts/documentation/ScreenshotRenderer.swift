import AppKit
import SceneKit

@main
struct ScreenshotRenderer {
    @MainActor static func main() throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        app.finishLaunching()
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for (name, theme, language) in [
            ("home-light", "light", "zh"), ("home-dark", "dark", "zh"), ("home-english", "light", "en"),
            ("home-dark-english", "dark", "en"),
        ] {
            UserDefaults.standard.setVolatileDomain(
                ["RemoteVoice.theme": theme, "RemoteVoice.language": language], forName: UserDefaults.argumentDomain)
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 1120, height: 920), styleMask: [.borderless], backing: .buffered,
                defer: false)
            window.appearance = InterfaceStyle.appearance
            let view = RemoteHomeView(
                frame: NSRect(x: 0, y: 0, width: 1120, height: 920), running: false, open: { _ in })
            window.contentView = view
            view.layoutSubtreeIfNeeded()
            view.displayIfNeeded()
            let image = NSImage(size: view.bounds.size)
            image.lockFocus()
            InterfaceStyle.background.setFill()
            view.bounds.fill()
            view.layer?.render(in: NSGraphicsContext.current!.cgContext)
            if let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                view.cacheDisplay(in: view.bounds, to: bitmap)
                bitmap.draw(in: view.bounds)
            }
            for scene in descendants(view).compactMap({ $0 as? SCNView }) {
                let rect = scene.convert(scene.bounds, to: view)
                scene.snapshot().draw(in: rect)
            }
            image.unlockFocus()
            try save(image, output.appendingPathComponent(name + ".png"))
            if name == "home-light" {
                if let scene = descendants(view).compactMap({ $0 as? SCNView }).first {
                    try save(scene.snapshot(), output.appendingPathComponent("remote-model.png"))
                }
                let detail = NSImage(size: NSSize(width: 480, height: 920))
                detail.lockFocus()
                image.draw(
                    at: .zero, from: NSRect(x: 640, y: 0, width: 480, height: 920), operation: .copy, fraction: 1)
                detail.unlockFocus()
                try save(detail, output.appendingPathComponent("controls.png"))
            }
            window.contentView = nil
        }
    }
    @MainActor static func descendants(_ view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants($0) }
    }
    static func save(_ image: NSImage, _ url: URL) throws {
        let flattened = NSImage(size: image.size)
        flattened.lockFocus()
        InterfaceStyle.background.setFill()
        NSRect(origin: .zero, size: image.size).fill()
        image.draw(at: .zero, from: NSRect(origin: .zero, size: image.size), operation: .sourceOver, fraction: 1)
        flattened.unlockFocus()
        let rep = NSBitmapImageRep(data: flattened.tiffRepresentation!)!
        try rep.representation(using: .png, properties: [:])!.write(to: url)
        print(url.lastPathComponent)
    }
}
