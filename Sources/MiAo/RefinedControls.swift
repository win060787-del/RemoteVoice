import AppKit

final class RefinedSwitch: NSButton {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setButtonType(.switch)
        title = ""
        isBordered = false
    }
    required init?(coder: NSCoder) { nil }
    override var intrinsicContentSize: NSSize { NSSize(width: 40, height: 24) }

    override func draw(_ dirtyRect: NSRect) {
        let track = NSRect(x: bounds.midX - 18, y: bounds.midY - 10, width: 36, height: 20)
        let enabled = isEnabled ? CGFloat(1) : 0.4
        NSColor(
            white: state == .on ? (InterfaceStyle.dark ? 0.85 : 0.16) : (InterfaceStyle.dark ? 0.28 : 0.84),
            alpha: enabled
        ).setFill()
        NSBezierPath(roundedRect: track, xRadius: 10, yRadius: 10).fill()
        let thumb = NSRect(x: state == .on ? track.maxX - 18 : track.minX + 2, y: track.minY + 2, width: 16, height: 16)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.12);
        shadow.shadowBlurRadius = 2; shadow.shadowOffset = NSSize(width: 0, height: -1); shadow.set()
        NSColor(white: InterfaceStyle.dark && state == .on ? 0.13 : 1, alpha: enabled).setFill()
        NSBezierPath(ovalIn: thumb).fill()
        NSGraphicsContext.restoreGraphicsState()
        if window?.firstResponder === self {
            NSColor.keyboardFocusIndicatorColor.setStroke()
            NSBezierPath(roundedRect: track.insetBy(dx: -2, dy: -2), xRadius: 12, yRadius: 12).stroke()
        }
    }
}

final class RefinedSegments: NSSegmentedControl {
    override var intrinsicContentSize: NSSize {
        let widest =
            (0..<segmentCount).map {
                NSAttributedString(
                    string: label(forSegment: $0) ?? "", attributes: [.font: RemoteTypography.font(ofSize: 12)]
                ).size().width
            }.max() ?? 40
        return NSSize(width: CGFloat(segmentCount) * max(58, ceil(widest) + 20), height: 28)
    }
    override func layout() {
        super.layout()
        guard segmentCount > 0 else { return }
        let width = bounds.width / CGFloat(segmentCount)
        for index in 0..<segmentCount where abs(self.width(forSegment: index) - width) > 0.5 {
            setWidth(width, forSegment: index)
        }
    }
    override func draw(_ dirtyRect: NSRect) {
        NSColor(white: InterfaceStyle.dark ? 0.19 : 0.94, alpha: 1).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8).fill()
        guard segmentCount > 0 else { return }
        let width = bounds.width / CGFloat(segmentCount)
        for index in 0..<segmentCount {
            let cell = NSRect(x: CGFloat(index) * width + 2, y: 2, width: width - 4, height: bounds.height - 4)
            if index == selectedSegment {
                NSColor(white: InterfaceStyle.dark ? 0.29 : 1, alpha: isEnabled ? 1 : 0.5).setFill()
                NSBezierPath(roundedRect: cell, xRadius: 6, yRadius: 6).fill()
                NSColor.black.withAlphaComponent(0.05).setStroke()
                NSBezierPath(roundedRect: cell.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6).stroke()
            }
            let text = NSAttributedString(
                string: label(forSegment: index) ?? "",
                attributes: [
                    .font: RemoteTypography.font(ofSize: 12, weight: index == selectedSegment ? .medium : .regular),
                    .foregroundColor: NSColor(
                        white: InterfaceStyle.dark
                            ? (index == selectedSegment ? 0.96 : 0.70)
                            : (index == selectedSegment ? 0.12 : 0.42),
                        alpha: isEnabled ? 1 : 0.4),
                ])
            text.draw(at: NSPoint(x: cell.midX - text.size().width / 2, y: cell.midY - text.size().height / 2))
        }
        if window?.firstResponder === self {
            NSColor.keyboardFocusIndicatorColor.setStroke();
            NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 8, yRadius: 8).stroke()
        }
    }
}
