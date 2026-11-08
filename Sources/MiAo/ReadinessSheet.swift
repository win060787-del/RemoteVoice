import AppKit
import CoreBluetooth

@MainActor
final class ReadinessSheet: NSObject {
    private var sheet: NSWindow?
    private var action: ((Int) -> Void)?
    func show(on parent: NSWindow, report: SetupEnvironmentReport, qwen: Bool, action: @escaping (Int) -> Void) {
        self.action = action
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 600), styleMask: [.titled], backing: .buffered,
            defer: false)
        sheet = window
        window.title = InterfaceStyle.text("连接与权限")
        window.appearance = InterfaceStyle.appearance
        window.isReleasedWhenClosed = false
        window.backgroundColor = InterfaceStyle.background
        let title = NSTextField(labelWithString: "连接与权限")
        title.font = RemoteTypography.font(ofSize: 22, weight: .medium)
        let rows = NSStackView()
        rows.orientation = .vertical; rows.alignment = .leading; rows.spacing = 10
        for check in report.checks {
            let name = NSTextField(labelWithString: check.title)
            let icon = NSImageView(
                image: NSImage(
                    systemSymbolName: check.state == .ready ? "checkmark.circle.fill" : "circle",
                    accessibilityDescription: check.state == .ready ? "Ready" : "Needs attention")!)
            icon.contentTintColor = check.state == .ready ? .systemGreen : .secondaryLabelColor
            icon.widthAnchor.constraint(equalToConstant: 18).isActive = true
            let header = NSStackView(views: [icon, name]); header.spacing = 8
            name.font = RemoteTypography.font(ofSize: 13, weight: .medium)
            let detail = NSTextField(wrappingLabelWithString: check.detail)
            detail.font = RemoteTypography.font(ofSize: 11); detail.textColor = .secondaryLabelColor
            let text = NSStackView(views: [header, detail]); text.orientation = .vertical; text.alignment = .leading;
            text.spacing = 5
            detail.widthAnchor.constraint(equalTo: text.widthAnchor).isActive = true
            text.setContentHuggingPriority(.defaultLow, for: .horizontal)
            let row = NSStackView(views: [text]); row.spacing = 14; row.alignment = .centerY
            let destination: Int?
            let label: String
            switch check.id {
            case .speechEngine: destination = qwen ? 10 : 14; label = "配置模型…"
            case .accessibility: destination = 11; label = "打开设置…"
            case .bluetooth: destination = 1; label = CBManager.authorization == .notDetermined ? "允许蓝牙…" : "蓝牙设置…"
            case .source: destination = 2; label = "显示应用"
            default: destination = nil; label = ""
            }
            if let destination {
                let button = SurfaceActionButton(title: label, target: self, action: #selector(navigate(_:)))
                button.tag = destination; button.bezelStyle = .rounded
                button.primary = true
                button.isBordered = false
                button.heightAnchor.constraint(equalToConstant: 32).isActive = true
                button.font = RemoteTypography.font(ofSize: 12)
                button.widthAnchor.constraint(equalToConstant: 106).isActive = true
                row.addArrangedSubview(button)
            } else {
                let placeholder = NSView()
                placeholder.widthAnchor.constraint(equalToConstant: 106).isActive = true
                row.addArrangedSubview(placeholder)
            }
            text.widthAnchor.constraint(equalTo: rows.widthAnchor, constant: -152).isActive = true
            row.translatesAutoresizingMaskIntoConstraints = false
            let card = NSView(); card.wantsLayer = true; card.layer?.backgroundColor = InterfaceStyle.surface.cgColor;
            card.layer?.cornerRadius = 14
            card.addSubview(row)
            NSLayoutConstraint.activate([
                row.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
                row.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
                row.topAnchor.constraint(equalTo: card.topAnchor, constant: 13),
                row.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -13),
            ])
            rows.addArrangedSubview(card)
            card.widthAnchor.constraint(equalTo: rows.widthAnchor).isActive = true
        }
        let refresh = SurfaceActionButton(title: "重新检查", target: self, action: #selector(navigate(_:))); refresh.tag = 0
        let done = SurfaceActionButton(title: "完成", target: self, action: #selector(close))
        for button in [refresh, done] {
            button.primary = true
            button.isBordered = false
            button.widthAnchor.constraint(equalToConstant: 106).isActive = true
            button.heightAnchor.constraint(equalToConstant: 32).isActive = true
        }
        let footer = NSStackView(views: [NSView(), refresh, done]); footer.spacing = 10
        let footerHost = NSView()
        footer.translatesAutoresizingMaskIntoConstraints = false
        footerHost.addSubview(footer)
        NSLayoutConstraint.activate([
            footer.leadingAnchor.constraint(equalTo: footerHost.leadingAnchor, constant: 16),
            footer.trailingAnchor.constraint(equalTo: footerHost.trailingAnchor, constant: -16),
            footer.topAnchor.constraint(equalTo: footerHost.topAnchor),
            footer.bottomAnchor.constraint(equalTo: footerHost.bottomAnchor),
        ])
        let content = NSStackView(views: [title, rows, footerHost]); content.orientation = .vertical;
        content.alignment = .leading; content.spacing = 18
        content.translatesAutoresizingMaskIntoConstraints = false
        window.contentView!.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 24),
            content.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -24),
            content.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 24),
            content.bottomAnchor.constraint(equalTo: window.contentView!.bottomAnchor, constant: -24),
            rows.widthAnchor.constraint(equalTo: content.widthAnchor),
            footerHost.widthAnchor.constraint(equalTo: content.widthAnchor),
        ])
        InterfaceStyle.apply(content)
        parent.beginSheet(window)
    }
    @objc private func navigate(_ sender: NSButton) {
        let destination = sender.tag
        close()
        DispatchQueue.main.async { [weak self] in self?.action?(destination) }
    }
    @objc private func close() {
        guard let sheet else { return }; sheet.sheetParent?.endSheet(sheet); sheet.orderOut(nil)
    }
}
