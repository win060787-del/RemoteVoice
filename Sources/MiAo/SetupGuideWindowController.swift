// Copyright (c) 2026 FanXeon@Poemcoder with Codex
import AppKit
import ApplicationServices
@preconcurrency import CoreBluetooth
import Foundation
import UniformTypeIdentifiers

@MainActor
private enum SetupInterfaceStyle {
    static func applyActionStyle(to button: NSButton, primary: Bool, compact: Bool = false) {
        button.isBordered = true
        button.bezelStyle = .rounded
        button.controlSize = compact ? .small : .regular
        let font = RemoteTypography.font(ofSize: compact ? 12 : 13, weight: .semibold)
        button.font = font
        button.bezelColor = primary ? .controlAccentColor : nil
        button.contentTintColor = primary ? .white : .labelColor
        button.attributedTitle = NSAttributedString(
            string: button.title,
            attributes: [
                .font: font,
                .foregroundColor: primary ? NSColor.white : NSColor.labelColor,
            ]
        )
    }

    static func requirementTextColor(_ requirement: SetupRequirement) -> NSColor {
        switch requirement {
        case .required:
            return .systemBlue
        case .featureRequired:
            return .systemOrange
        case .optional:
            return .secondaryLabelColor
        }
    }
}

/// A system-appearance-aware surface. AppKit dynamic colors must be resolved again
/// when macOS switches between light and dark appearances; a one-off CGColor does not
/// redraw itself after that change.
private class SetupSurfaceView: NSView {
    private let surfaceRadius: CGFloat
    private let emphasized: Bool
    private var highlighted = false

    init(radius: CGFloat = 20, emphasized: Bool = false) {
        surfaceRadius = radius
        self.emphasized = emphasized
        super.init(frame: .zero)
        configureSurface()
    }

    override init(frame frameRect: NSRect) {
        surfaceRadius = 20
        emphasized = false
        super.init(frame: frameRect)
        configureSurface()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    private func configureSurface() {
        wantsLayer = true
        layer?.cornerRadius = surfaceRadius
        layer?.masksToBounds = true
        needsDisplay = true
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        let appearance = effectiveAppearance
        appearance.performAsCurrentDrawingAppearance {
            self.layer?.backgroundColor =
                (self.highlighted
                ? NSColor.controlAccentColor.withAlphaComponent(0.18)
                : NSColor.labelColor.withAlphaComponent(self.emphasized ? 0.085 : 0.055))
                .cgColor
            self.layer?.borderWidth = self.highlighted ? 1.5 : 0
            self.layer?.borderColor =
                NSColor.controlAccentColor.withAlphaComponent(self.highlighted ? 0.55 : 0)
                .cgColor
        }
    }

    func setSurfaceHighlighted(_ highlighted: Bool) {
        self.highlighted = highlighted
        needsDisplay = true
    }
}

private class FlippedLayoutView: NSView {
    override var isFlipped: Bool { true }
}

private final class SetupTabViewController: NSViewController {
    var onSelectionChanged: (() -> Void)?
    private let segmentedControl = NSSegmentedControl()
    private let contentContainer = NSView()
    private var pages: [NSViewController] = []
    private var selectedIndex = 0

    var selectedTabViewItemIndex: Int {
        get { selectedIndex }
        set { selectPage(at: newValue, notify: true) }
    }

    override func loadView() {
        let root = NSView()
        segmentedControl.translatesAutoresizingMaskIntoConstraints = false
        segmentedControl.segmentStyle = .automatic
        segmentedControl.trackingMode = .selectOne
        segmentedControl.target = self
        segmentedControl.action = #selector(selectionChanged)
        segmentedControl.setAccessibilityLabel("遥声设置分类")
        contentContainer.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(segmentedControl)
        root.addSubview(contentContainer)
        NSLayoutConstraint.activate([
            segmentedControl.topAnchor.constraint(equalTo: root.topAnchor),
            segmentedControl.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            segmentedControl.leadingAnchor.constraint(greaterThanOrEqualTo: root.leadingAnchor),
            segmentedControl.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor),
            contentContainer.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            contentContainer.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            contentContainer.topAnchor.constraint(equalTo: segmentedControl.bottomAnchor, constant: 12),
            contentContainer.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])
        view = root
    }

    func addPage(_ page: NSViewController) {
        loadViewIfNeeded()
        addChild(page)
        pages.append(page)
        segmentedControl.segmentCount = pages.count
        segmentedControl.setLabel(page.title ?? "", forSegment: pages.count - 1)
        if pages.count == 1 {
            segmentedControl.selectedSegment = 0
            displayPage(at: 0)
        }
    }

    private func selectPage(at index: Int, notify: Bool) {
        guard pages.indices.contains(index) else { return }
        selectedIndex = index
        segmentedControl.selectedSegment = index
        displayPage(at: index)
        if notify { onSelectionChanged?() }
    }

    private func displayPage(at index: Int) {
        contentContainer.subviews.forEach { $0.removeFromSuperview() }
        let pageView = pages[index].view
        pageView.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.addSubview(pageView)
        NSLayoutConstraint.activate([
            pageView.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            pageView.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            pageView.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            pageView.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor),
        ])
    }

    @objc private func selectionChanged() {
        selectPage(at: segmentedControl.selectedSegment, notify: true)
    }

}

private final class SetupToggleRowView: SetupSurfaceView {
    init(title: String, detail: String, toggle: NSSwitch) {
        super.init(radius: 18)

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = RemoteTypography.font(ofSize: 14, weight: .semibold)

        let detailLabel = NSTextField(wrappingLabelWithString: detail)
        detailLabel.translatesAutoresizingMaskIntoConstraints = false
        detailLabel.font = RemoteTypography.font(ofSize: 11)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.maximumNumberOfLines = 2

        toggle.translatesAutoresizingMaskIntoConstraints = false
        toggle.controlSize = .regular
        toggle.setAccessibilityLabel(title)

        addSubview(titleLabel)
        addSubview(detailLabel)
        addSubview(toggle)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(greaterThanOrEqualToConstant: 72),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 15),
            titleLabel.trailingAnchor.constraint(equalTo: toggle.leadingAnchor, constant: -16),
            detailLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            detailLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            detailLabel.trailingAnchor.constraint(equalTo: toggle.leadingAnchor, constant: -16),
            detailLabel.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -13),
            toggle.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
            toggle.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }
}

private final class SetupSegmentedRowView: SetupSurfaceView {
    init(title: String, detail: String, control: NSSegmentedControl) {
        super.init(radius: 18)

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = RemoteTypography.font(ofSize: 14, weight: .semibold)

        let detailLabel = NSTextField(wrappingLabelWithString: detail)
        detailLabel.translatesAutoresizingMaskIntoConstraints = false
        detailLabel.font = RemoteTypography.font(ofSize: 11)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.maximumNumberOfLines = 2

        control.translatesAutoresizingMaskIntoConstraints = false
        control.controlSize = .regular
        control.setAccessibilityLabel(title)

        addSubview(titleLabel)
        addSubview(detailLabel)
        addSubview(control)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(greaterThanOrEqualToConstant: 104),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 15),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
            detailLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            detailLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            detailLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            control.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            control.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            control.topAnchor.constraint(equalTo: detailLabel.bottomAnchor, constant: 10),
            control.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -14),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }
}

private final class SetupCheckRowView: SetupSurfaceView {
    private let iconPlate = NSView()
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let requirementLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(wrappingLabelWithString: "")
    private let actionButton = NSButton()
    private var actionWidthConstraint: NSLayoutConstraint!

    override init(frame frameRect: NSRect) {
        super.init(radius: 20)

        iconPlate.translatesAutoresizingMaskIntoConstraints = false
        iconPlate.wantsLayer = true
        iconPlate.layer?.cornerRadius = 20
        iconPlate.layer?.masksToBounds = true

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
        iconView.contentTintColor = .secondaryLabelColor

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = RemoteTypography.font(ofSize: 15, weight: .semibold)

        requirementLabel.translatesAutoresizingMaskIntoConstraints = false
        requirementLabel.font = RemoteTypography.font(ofSize: 11, weight: .semibold)
        requirementLabel.setContentHuggingPriority(.required, for: .horizontal)
        requirementLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        detailLabel.translatesAutoresizingMaskIntoConstraints = false
        detailLabel.font = RemoteTypography.font(ofSize: 12)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.maximumNumberOfLines = 2

        actionButton.translatesAutoresizingMaskIntoConstraints = false
        actionButton.isHidden = true
        actionButton.setAccessibilityIdentifier("setup-check-action")

        addSubview(iconPlate)
        iconPlate.addSubview(iconView)
        addSubview(titleLabel)
        addSubview(requirementLabel)
        addSubview(detailLabel)
        addSubview(actionButton)

        actionWidthConstraint = actionButton.widthAnchor.constraint(equalToConstant: 0)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(greaterThanOrEqualToConstant: 88),
            iconPlate.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            iconPlate.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconPlate.widthAnchor.constraint(equalToConstant: 40),
            iconPlate.heightAnchor.constraint(equalToConstant: 40),
            iconView.centerXAnchor.constraint(equalTo: iconPlate.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconPlate.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 22),
            iconView.heightAnchor.constraint(equalToConstant: 22),
            titleLabel.leadingAnchor.constraint(equalTo: iconPlate.trailingAnchor, constant: 14),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 18),
            titleLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: requirementLabel.leadingAnchor,
                constant: -8
            ),
            requirementLabel.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 8),
            requirementLabel.firstBaselineAnchor.constraint(equalTo: titleLabel.firstBaselineAnchor),
            requirementLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: actionButton.leadingAnchor,
                constant: -10
            ),
            detailLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            detailLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 6),
            detailLabel.trailingAnchor.constraint(equalTo: actionButton.leadingAnchor, constant: -12),
            detailLabel.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -15),
            actionButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
            actionButton.centerYAnchor.constraint(equalTo: iconPlate.centerYAnchor),
            actionButton.heightAnchor.constraint(equalToConstant: 34),
            actionWidthConstraint,
        ])
    }

    convenience init() {
        self.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func update(check: SetupCheck, target: AnyObject, action: Selector) {
        titleLabel.stringValue = check.title
        detailLabel.stringValue = check.detail
        requirementLabel.stringValue = check.requirement.title
        requirementLabel.textColor = SetupInterfaceStyle.requirementTextColor(check.requirement)
        let symbolName: String
        let color: NSColor
        switch check.state {
        case .ready:
            symbolName = "checkmark.circle.fill"
            color = .systemGreen
        case .actionRequired:
            symbolName = "exclamationmark.circle.fill"
            color = .systemOrange
        case .blocked:
            symbolName = "xmark.circle.fill"
            color = .systemRed
        }
        iconView.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: check.title)
        iconView.contentTintColor = color
        iconPlate.layer?.backgroundColor = color.withAlphaComponent(0.14).cgColor

        if let actionTitle = check.actionTitle, check.action != nil {
            actionButton.title = actionTitle
            actionButton.target = target
            actionButton.action = action
            actionButton.identifier = NSUserInterfaceItemIdentifier(check.id.rawValue)
            actionButton.isHidden = false
            actionWidthConstraint.constant = 116
            SetupInterfaceStyle.applyActionStyle(to: actionButton, primary: false, compact: true)
        } else {
            actionButton.isHidden = true
            actionButton.identifier = nil
            actionWidthConstraint.constant = 0
        }
    }
}

private final class ShortcutRecorderView: NSView {
    var recordedShortcut: KeyboardShortcutSpec?

    private let prompt = NSTextField(wrappingLabelWithString: "")

    override var acceptsFirstResponder: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.10).cgColor

        prompt.translatesAutoresizingMaskIntoConstraints = false
        prompt.font = RemoteTypography.font(ofSize: 13, weight: .medium)
        prompt.alignment = .center
        prompt.textColor = .secondaryLabelColor
        prompt.stringValue = "请按下要发送的按键组合"
        addSubview(prompt)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 320),
            heightAnchor.constraint(equalToConstant: 74),
            prompt.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            prompt.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            prompt.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        var modifiers: Set<ShortcutModifier> = []
        if event.modifierFlags.contains(.command) { modifiers.insert(.command) }
        if event.modifierFlags.contains(.option) { modifiers.insert(.option) }
        if event.modifierFlags.contains(.shift) { modifiers.insert(.shift) }
        if event.modifierFlags.contains(.control) { modifiers.insert(.control) }
        let keyLabel = event.charactersIgnoringModifiers?.uppercased() ?? "Key \(event.keyCode)"
        do {
            recordedShortcut = try KeyboardShortcutSpec(
                keyCode: event.keyCode,
                modifiers: modifiers,
                keyLabel: keyLabel
            )
            prompt.stringValue = "已记录：\(recordedShortcut?.displayName ?? "")"
            prompt.textColor = .controlAccentColor
        } catch {
            recordedShortcut = nil
            prompt.stringValue = error.localizedDescription
            prompt.textColor = .systemRed
        }
    }
}

private final class ButtonMappingRowView: SetupSurfaceView {
    private enum Choice {
        static let shortcut = "shortcut"
        static let presetSwitch = "preset_switch"
        static let actionPrefix = "action:"
    }

    let button: RemoteButton
    var onBindingChanged: ((ButtonBinding) -> Void)?
    var onShortcutRequested: (() -> Void)?
    var onTestRequested: (() -> Void)?

    private let titleLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(wrappingLabelWithString: "")
    private let actionPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let testButton = NSButton(title: "测试", target: nil, action: nil)
    private let targetLabel = NSTextField(labelWithString: "TV 切换至")
    private let targetPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let targetRow = NSStackView()
    private var currentBinding: ButtonBinding = .action(.unmapped)
    private var rowHeightConstraint: NSLayoutConstraint!

    init(button: RemoteButton) {
        self.button = button
        super.init(radius: 18)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = RemoteTypography.font(ofSize: 14, weight: .semibold)
        titleLabel.stringValue = button.displayName

        detailLabel.translatesAutoresizingMaskIntoConstraints = false
        detailLabel.font = RemoteTypography.font(ofSize: 11)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.maximumNumberOfLines = 2

        actionPopup.translatesAutoresizingMaskIntoConstraints = false
        actionPopup.target = self
        actionPopup.action = #selector(actionChanged)
        actionPopup.setAccessibilityLabel("\(button.displayName) 的动作")
        testButton.translatesAutoresizingMaskIntoConstraints = false
        testButton.target = self
        testButton.action = #selector(testAction)
        testButton.setAccessibilityLabel("测试 \(button.displayName) 当前动作一次")
        SetupInterfaceStyle.applyActionStyle(to: testButton, primary: false, compact: true)

        targetLabel.font = RemoteTypography.font(ofSize: 11, weight: .medium)
        targetLabel.textColor = .secondaryLabelColor
        targetPopup.target = self
        targetPopup.action = #selector(targetChanged)
        targetPopup.setAccessibilityLabel("TV 的目标配置")
        targetRow.orientation = .horizontal
        targetRow.alignment = .centerY
        targetRow.spacing = 8
        targetRow.translatesAutoresizingMaskIntoConstraints = false
        targetRow.addArrangedSubview(targetLabel)
        targetRow.addArrangedSubview(targetPopup)
        targetRow.isHidden = true

        addSubview(titleLabel)
        addSubview(detailLabel)
        addSubview(actionPopup)
        addSubview(testButton)
        addSubview(targetRow)

        rowHeightConstraint = heightAnchor.constraint(greaterThanOrEqualToConstant: 112)
        NSLayoutConstraint.activate([
            rowHeightConstraint,
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -16),
            detailLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            detailLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            detailLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            actionPopup.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            actionPopup.trailingAnchor.constraint(equalTo: testButton.leadingAnchor, constant: -8),
            actionPopup.topAnchor.constraint(equalTo: detailLabel.bottomAnchor, constant: 9),
            actionPopup.widthAnchor.constraint(greaterThanOrEqualToConstant: 140),
            testButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            testButton.centerYAnchor.constraint(equalTo: actionPopup.centerYAnchor),
            testButton.widthAnchor.constraint(equalToConstant: 50),
            targetRow.leadingAnchor.constraint(equalTo: detailLabel.leadingAnchor),
            targetRow.topAnchor.constraint(equalTo: actionPopup.bottomAnchor, constant: 8),
            targetRow.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -16),
            targetRow.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -12),
            actionPopup.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -13),
            targetPopup.widthAnchor.constraint(greaterThanOrEqualToConstant: 140),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func update(
        binding: ButtonBinding,
        targetPresets: [ButtonPreset],
        editable: Bool
    ) {
        currentBinding = binding
        actionPopup.removeAllItems()
        for action in availableActions {
            addActionItem(action)
        }
        if button.isUserEditable {
            actionPopup.menu?.addItem(.separator())
            addItem(title: "录制自定义快捷键…", identifier: Choice.shortcut)
        }
        if button == .tv {
            actionPopup.menu?.addItem(.separator())
            let switchItem = NSMenuItem(title: "切换到另一配置", action: nil, keyEquivalent: "")
            switchItem.representedObject = Choice.presetSwitch
            switchItem.isEnabled = !targetPresets.isEmpty
            actionPopup.menu?.addItem(switchItem)
        }

        targetPopup.removeAllItems()
        for target in targetPresets {
            let item = NSMenuItem(title: target.name, action: nil, keyEquivalent: "")
            item.representedObject = target.id
            targetPopup.menu?.addItem(item)
        }

        let selectedIdentifier: String
        switch binding {
        case .action(let action):
            selectedIdentifier = Choice.actionPrefix + action.rawValue
            detailLabel.stringValue = ""
        case .keyboardShortcut(let shortcut):
            selectedIdentifier = Choice.shortcut
            detailLabel.stringValue = "将发送 \(shortcut.displayName)；再次选择“录制自定义快捷键”可更换。"
        case .presetSwitch(let targetID):
            selectedIdentifier = Choice.presetSwitch
            detailLabel.stringValue = "按下 TV 会立即切换整个配置，其他按钮随之改变。"
            selectTarget(id: targetID)
        }
        selectAction(identifier: selectedIdentifier)
        targetRow.isHidden = button != .tv || selectedIdentifier != Choice.presetSwitch
        let isPlainAction: Bool
        if case .action = binding { isPlainAction = true } else { isPlainAction = false }
        rowHeightConstraint.constant = targetRow.isHidden ? (isPlainAction ? 92 : 112) : 148
        actionPopup.isEnabled = editable
        targetPopup.isEnabled = editable && !targetPresets.isEmpty
        alphaValue = editable ? 1 : 0.72
        switch binding {
        case .action(.voicePushToTalk):
            testButton.isEnabled = false
            testButton.toolTip = "语音键必须由真实遥控器按住测试"
        case .action(.unmapped):
            testButton.isEnabled = false
            testButton.toolTip = "当前动作是不执行任何操作"
        case .action, .keyboardShortcut, .presetSwitch:
            testButton.isEnabled = true
            testButton.toolTip = "执行当前动作一次"
        }
    }

    func setActive(_ isActive: Bool) {
        titleLabel.textColor = isActive ? .controlAccentColor : .labelColor
        setSurfaceHighlighted(isActive)
        setAccessibilityValue(isActive ? "按键已按下" : "")
    }

    private var availableActions: [ButtonAction] {
        let common: [ButtonAction] = [
            .keyboardReturn,
            .keyboardEscape,
            .keyboardDelete,
            .pointerLeftClick,
            .keyboardPageUp,
            .keyboardPageDown,
            .codexFocus,
            .codexLaunchOrFocus,
            .codexPreviousTask,
            .codexNextTask,
            .unmapped,
        ]
        switch button {
        case .dpadUp:
            return [.pointerMoveUp, .keyboardArrowUp, .pointerScrollUp] + common
        case .dpadDown:
            return [.pointerMoveDown, .keyboardArrowDown, .pointerScrollDown] + common
        case .dpadLeft:
            return [.pointerMoveLeft, .keyboardArrowLeft] + common
        case .dpadRight:
            return [.pointerMoveRight, .keyboardArrowRight] + common
        case .home:
            return [.homePageNavigation] + common
        case .tv:
            return [.modeTogglePointerDirectional] + common
        case .voice:
            return [.voicePushToTalk]
        case .menu:
            return [.unmapped]
        case .back:
            return [.backPointerDeleteOrEscape, .backEscapeOrDelete] + common
        case .center:
            return [.centerPointerOrReturn] + common
        case .volumeUp, .volumeDown, .power:
            return common
        }
    }

    private func addActionItem(_ action: ButtonAction) {
        addItem(title: action.displayName, identifier: Choice.actionPrefix + action.rawValue)
    }

    private func addItem(title: String, identifier: String) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.representedObject = identifier
        actionPopup.menu?.addItem(item)
    }

    private func selectAction(identifier: String) {
        guard let menu = actionPopup.menu else { return }
        let index = menu.items.firstIndex { ($0.representedObject as? String) == identifier }
        actionPopup.selectItem(at: index ?? 0)
    }

    private func selectTarget(id: String) {
        guard let menu = targetPopup.menu else { return }
        let index = menu.items.firstIndex { ($0.representedObject as? String) == id }
        targetPopup.selectItem(at: index ?? 0)
    }

    @objc private func actionChanged() {
        guard let identifier = actionPopup.selectedItem?.representedObject as? String else { return }
        if identifier == Choice.shortcut {
            onShortcutRequested?()
            return
        }
        if identifier == Choice.presetSwitch {
            guard let targetID = targetPopup.selectedItem?.representedObject as? String else { return }
            onBindingChanged?(.presetSwitch(targetID))
            return
        }
        guard let rawValue = identifier.stripPrefix(Choice.actionPrefix),
            let action = ButtonAction(rawValue: rawValue)
        else { return }
        onBindingChanged?(.action(action))
    }

    @objc private func targetChanged() {
        guard case .presetSwitch = currentBinding,
            let targetID = targetPopup.selectedItem?.representedObject as? String
        else { return }
        onBindingChanged?(.presetSwitch(targetID))
    }

    @objc private func testAction() {
        onTestRequested?()
    }
}

private extension String {
    func stripPrefix(_ prefix: String) -> String? {
        guard hasPrefix(prefix) else { return nil }
        return String(dropFirst(prefix.count))
    }
}

@MainActor
final class SetupGuideWindowController: NSWindowController, NSWindowDelegate, NSTextFieldDelegate {
    private var configuration: Configuration
    private let standalone: Bool
    private let preferencesStore: AppPreferencesStore
    private let presetStore: ButtonPresetStore
    private let loginItemController: LoginItemController
    private let inspector = SetupEnvironmentInspector()
    private let rows = Dictionary(
        uniqueKeysWithValues: SetupCheckID.allCases.map { ($0, SetupCheckRowView()) }
    )
    private let summaryLabel = NSTextField(wrappingLabelWithString: "")
    private let preferenceStateLabel = NSTextField(wrappingLabelWithString: "")
    private let loginItemStateLabel = NSTextField(wrappingLabelWithString: "")
    private let automaticSubmitCheckbox = NSSwitch()
    private let buttonControlCheckbox = NSSwitch()
    private let voiceConnectionModeControl = NSSegmentedControl(
        labels: VoiceConnectionMode.allCases.map(\.displayName),
        trackingMode: .selectOne,
        target: nil,
        action: nil
    )
    private let loginAtStartupCheckbox = NSSwitch()
    private let devicePicker = NSPopUpButton(frame: .zero, pullsDown: false)
    private let scanDevicesButton = NSButton(title: "扫描遥控器", target: nil, action: nil)
    private let deviceStateLabel = NSTextField(wrappingLabelWithString: "")
    private let deviceDiscoveryController = RemoteDeviceDiscoveryController()
    private let openLoginItemsButton = NSButton(title: "打开登录项设置", target: nil, action: nil)
    private let refreshButton = NSButton(title: "重新检查", target: nil, action: nil)
    private let startButton = NSButton(title: "连接遥控器并开始", target: nil, action: nil)
    private let pageTabs = SetupTabViewController()
    private let presetPicker = NSPopUpButton(frame: .zero, pullsDown: false)
    private let presetNameField = NSTextField(string: "")
    private let createPresetButton = NSButton(title: "新建", target: nil, action: nil)
    private let duplicatePresetButton = NSButton(title: "复制", target: nil, action: nil)
    private let deletePresetButton = NSButton(title: "删除", target: nil, action: nil)
    private let savePresetButton = NSButton(title: "保存配置", target: nil, action: nil)
    private let importPresetsButton = NSButton(title: "导入 JSON…", target: nil, action: nil)
    private let exportPresetsButton = NSButton(title: "导出 JSON…", target: nil, action: nil)
    private let presetStateLabel = NSTextField(wrappingLabelWithString: "")
    private var mappingRows: [RemoteButton: ButtonMappingRowView] = [:]
    private var report: SetupEnvironmentReport?
    private var bluetoothRequester: BluetoothAuthorizationRequester?
    private var process: Process?
    private var refreshTimer: Timer?
    private var preferences: AppPreferences
    private var preferencesLoadState: AppPreferencesLoadState
    private var presetCatalog: ButtonPresetCatalog
    private var presetCatalogLoadState: ButtonPresetCatalogLoadState
    private var selectedPresetID: String
    private var draftPreset: ButtonPreset
    private var hasUnsavedPresetChanges = false
    private var discoveredDevices: [RemoteDeviceRecord] = []
    private var deviceDiscoveryState: RemoteDeviceDiscoveryState = .idle
    private var isObservingButtonActivity = false
    private var buttonHighlightTimers: [RemoteButton: Timer] = [:]
    private var testExecutor: ButtonActionExecutor?
    private var testButton: RemoteButton?
    private var testFeedbackReceived = false

    init(
        configuration: Configuration,
        standalone: Bool,
        preferencesStore: AppPreferencesStore = AppPreferencesStore(),
        presetStore: ButtonPresetStore = ButtonPresetStore(),
        loginItemController: LoginItemController = LoginItemController()
    ) {
        self.configuration = configuration
        self.standalone = standalone
        self.preferencesStore = preferencesStore
        self.presetStore = presetStore
        self.loginItemController = loginItemController
        let snapshot = preferencesStore.load()
        preferences = snapshot.preferences
        preferencesLoadState = snapshot.state
        let presetSnapshot = presetStore.load()
        presetCatalog = presetSnapshot.catalog
        presetCatalogLoadState = presetSnapshot.state
        selectedPresetID = snapshot.preferences.selectedPresetID
        if (try? presetSnapshot.catalog.preset(id: selectedPresetID)) == nil {
            selectedPresetID = ButtonPreset.pointer.id
        }
        draftPreset = (try? presetSnapshot.catalog.preset(id: selectedPresetID)) ?? .pointer
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 780),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "遥声"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        // nil means inherit the current macOS appearance and keep following it.
        window.appearance = nil
        window.backgroundColor = .windowBackgroundColor
        window.minSize = NSSize(width: 1000, height: 900)
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        installRemoteHome()
        deviceDiscoveryController.onUpdate = { [weak self] state, devices in
            self?.deviceDiscoveryState = state
            self?.discoveredDevices = devices
            self?.updateDeviceControls()
        }
        refresh()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func showWindow(_ sender: Any?) {
        if standalone {
            NSApplication.shared.setActivationPolicy(.regular)
        }
        super.showWindow(sender)
        window?.center()
        window?.makeKeyAndOrderFront(sender)
        NSApplication.shared.activate(ignoringOtherApps: true)
        startObservingButtonActivity()
        refresh()
        startAutoRefresh()
    }

    func windowWillClose(_ notification: Notification) {
        refreshTimer?.invalidate()
        refreshTimer = nil
        deviceDiscoveryController.stop()
        stopObservingButtonActivity()
        stopActionTest()
        if standalone { NSApplication.shared.terminate(nil) }
    }

    private var readinessSheet: ReadinessSheet?
    private var settingsContent: NSView?
    private weak var homeBackButton: NSButton?

    private func installRemoteHome() {
        window?.contentView = makeRemoteHome()
    }

    private func makeRemoteHome() -> RemoteHomeView {
        RemoteHomeView(frame: window?.contentView?.bounds ?? .zero, running: report?.runtimeActive ?? false) {
            [weak self] index in
            guard let self else { return }
            switch index {
            case 14: self.runSetupRepair()
            case 12:
                if RemoteDeviceStatus.runtimeActive, let context = MiAoInstallationContext.load() {
                    self.runScript(
                        context.runtimeURL.appendingPathComponent("scripts/stop.sh"), arguments: [],
                        progress: "正在停止语音服务…"
                    ) { [weak self] result in
                        if case .failure(let error) = result {
                            self?.showError(title: "停止失败", message: error.localizedDescription)
                        }
                        self?.refresh()
                    }
                } else {
                    self.startPressed()
                }
            case 10: self.configureQwen()
            default: self.showReadinessSheet()
            }
        }
    }

    private func showReadinessSheet() {
        refresh()
        guard let window, let report else { return }
        let sheet = ReadinessSheet()
        readinessSheet = sheet
        sheet.show(on: window, report: report, qwen: configuration.speechEngine == "qwen") { [weak self] destination in
            guard let self else { return }
            switch destination {
            case 10: self.configureQwen()
            case 14: self.runSetupRepair()
            case 11: self.openPrivacyPane(anchor: "Privacy_Accessibility")
            case 1:
                if CBManager.authorization == .notDetermined {
                    self.bluetoothRequester = BluetoothAuthorizationRequester { [weak self] in self?.scheduleRefresh() }
                    self.bluetoothRequester?.start()
                } else if CBManager.authorization == .denied {
                    self.openPrivacyPane(anchor: "Privacy_Bluetooth")
                } else {
                    self.openBluetoothSettings()
                }
            case 2: NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
            default: self.showReadinessSheet()
            }
        }
    }

    @objc private func returnToRemoteHome() {
        homeBackButton?.isHidden = true
        window?.contentView = makeRemoteHome()
    }

    private func buildInterface() {
        guard let contentView = window?.contentView else { return }
        let horizontalInset: CGFloat = 16

        let heroView = buildSectionHeader(title: "设备设置", detail: "")
        heroView.translatesAutoresizingMaskIntoConstraints = false

        let checksStack = NSStackView(
            views: SetupCheckID.allCases.compactMap { rows[$0] }
        )
        checksStack.orientation = .vertical
        checksStack.alignment = .leading
        checksStack.spacing = 10

        let checksHeader = buildSectionHeader(
            title: "设备与权限检查",
            detail: "只需处理标注为“必须”或“当前功能必需”的项目。"
        )
        let checksSection = NSStackView(views: [checksHeader, checksStack])
        checksSection.orientation = .vertical
        checksSection.alignment = .leading
        checksSection.spacing = 12
        checksHeader.widthAnchor.constraint(equalTo: checksSection.widthAnchor).isActive = true
        checksStack.widthAnchor.constraint(equalTo: checksSection.widthAnchor).isActive = true

        pageTabs.addPage(makeTabPage(title: "设备与权限", content: checksSection))
        pageTabs.onSelectionChanged = { [weak self] in self?.refresh() }
        pageTabs.view.translatesAutoresizingMaskIntoConstraints = false
        pageTabs.view.setAccessibilityLabel("遥声设置分类")

        summaryLabel.font = RemoteTypography.font(ofSize: 12, weight: .medium)
        summaryLabel.textColor = .secondaryLabelColor
        let summaryView = SetupSurfaceView(radius: 16)
        summaryView.translatesAutoresizingMaskIntoConstraints = false
        let summaryIcon = NSImageView()
        summaryIcon.translatesAutoresizingMaskIntoConstraints = false
        summaryIcon.image = NSImage(systemSymbolName: "info.circle.fill", accessibilityDescription: nil)
        summaryIcon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
        summaryIcon.contentTintColor = .secondaryLabelColor
        summaryLabel.translatesAutoresizingMaskIntoConstraints = false
        let summaryContent = NSStackView(views: [summaryIcon, summaryLabel])
        summaryContent.translatesAutoresizingMaskIntoConstraints = false
        summaryContent.orientation = .horizontal
        summaryContent.alignment = .centerY
        summaryContent.spacing = 10
        summaryView.addSubview(summaryContent)
        NSLayoutConstraint.activate([
            summaryView.heightAnchor.constraint(equalToConstant: 56),
            summaryContent.leadingAnchor.constraint(equalTo: summaryView.leadingAnchor, constant: 17),
            summaryContent.trailingAnchor.constraint(equalTo: summaryView.trailingAnchor, constant: -17),
            summaryContent.centerYAnchor.constraint(equalTo: summaryView.centerYAnchor),
            summaryContent.topAnchor.constraint(greaterThanOrEqualTo: summaryView.topAnchor, constant: 12),
            summaryContent.bottomAnchor.constraint(lessThanOrEqualTo: summaryView.bottomAnchor, constant: -12),
            summaryIcon.widthAnchor.constraint(equalToConstant: 18),
            summaryIcon.heightAnchor.constraint(equalToConstant: 18),
        ])

        refreshButton.target = self
        refreshButton.action = #selector(refreshPressed)
        refreshButton.setAccessibilityLabel("重新检查环境")

        startButton.target = self
        startButton.action = #selector(startPressed)
        startButton.keyEquivalent = "\r"
        startButton.setAccessibilityLabel("连接遥控器并开始")

        let buttonSpacer = NSView()
        let buttons = NSStackView(views: [refreshButton, buttonSpacer, startButton])
        buttons.orientation = .horizontal
        buttons.alignment = .centerY
        buttons.spacing = 12

        buttons.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(heroView)
        contentView.addSubview(pageTabs.view)
        contentView.addSubview(summaryView)
        contentView.addSubview(buttons)

        let rowWidthConstraints = SetupCheckID.allCases.compactMap { rows[$0] }.map {
            $0.widthAnchor.constraint(equalTo: checksStack.widthAnchor)
        }

        NSLayoutConstraint.activate(
            [
                heroView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: horizontalInset),
                heroView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -horizontalInset),
                heroView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 22),
                heroView.heightAnchor.constraint(equalToConstant: 92),
                pageTabs.view.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: horizontalInset),
                pageTabs.view.trailingAnchor.constraint(
                    equalTo: contentView.trailingAnchor,
                    constant: -horizontalInset
                ),
                pageTabs.view.topAnchor.constraint(equalTo: heroView.bottomAnchor, constant: 14),
                pageTabs.view.bottomAnchor.constraint(equalTo: summaryView.topAnchor, constant: -18),
                summaryView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: horizontalInset),
                summaryView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -horizontalInset),
                buttons.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: horizontalInset),
                buttons.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -horizontalInset),
                buttons.topAnchor.constraint(equalTo: summaryView.bottomAnchor, constant: 12),
                buttons.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -22),
                buttonSpacer.widthAnchor.constraint(greaterThanOrEqualToConstant: 1),
                refreshButton.widthAnchor.constraint(equalToConstant: 124),
                refreshButton.heightAnchor.constraint(equalToConstant: 44),
                startButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 202),
                startButton.heightAnchor.constraint(equalToConstant: 44),
            ] + rowWidthConstraints)
    }

    private func makeTabPage(title: String, content: NSView) -> NSViewController {
        let controller = NSViewController()
        controller.title = title

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay

        let documentView = FlippedLayoutView()
        documentView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = documentView
        content.translatesAutoresizingMaskIntoConstraints = false
        documentView.addSubview(content)
        NSLayoutConstraint.activate([
            documentView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
            content.leadingAnchor.constraint(equalTo: documentView.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: documentView.trailingAnchor),
            content.topAnchor.constraint(equalTo: documentView.topAnchor, constant: 12),
            content.bottomAnchor.constraint(equalTo: documentView.bottomAnchor, constant: -12),
        ])
        controller.view = scrollView
        return controller
    }

    private func buildButtonMappingsView() -> NSView {
        let sectionHeader = buildSectionHeader(
            title: "按键配置",
            detail: "创建自己的配置并保存。TV 可从当前配置跳转到另一套配置；语音键与菜单键为安全保留项。"
        )

        presetPicker.target = self
        presetPicker.action = #selector(presetSelectionChanged)
        presetPicker.setAccessibilityLabel("当前按键配置")

        presetNameField.placeholderString = "配置名称"
        presetNameField.font = RemoteTypography.font(ofSize: 13, weight: .medium)
        presetNameField.delegate = self
        presetNameField.setAccessibilityLabel("按键配置名称")

        createPresetButton.target = self
        createPresetButton.action = #selector(createPreset)
        duplicatePresetButton.target = self
        duplicatePresetButton.action = #selector(duplicatePreset)
        deletePresetButton.target = self
        deletePresetButton.action = #selector(deletePreset)
        savePresetButton.target = self
        savePresetButton.action = #selector(savePreset)
        importPresetsButton.target = self
        importPresetsButton.action = #selector(importPresets)
        exportPresetsButton.target = self
        exportPresetsButton.action = #selector(exportPresets)
        [
            createPresetButton, duplicatePresetButton, deletePresetButton, savePresetButton,
            importPresetsButton, exportPresetsButton,
        ].forEach {
            SetupInterfaceStyle.applyActionStyle(to: $0, primary: $0 === savePresetButton, compact: true)
        }

        let pickerTitle = NSTextField(labelWithString: "当前配置")
        pickerTitle.font = RemoteTypography.font(ofSize: 13, weight: .semibold)
        let pickerRow = NSStackView(views: [pickerTitle, presetPicker])
        pickerRow.orientation = .horizontal
        pickerRow.alignment = .centerY
        pickerRow.spacing = 10
        pickerTitle.widthAnchor.constraint(equalToConstant: 66).isActive = true
        presetPicker.widthAnchor.constraint(greaterThanOrEqualToConstant: 150).isActive = true
        let presetPickerMaximumWidth = presetPicker.widthAnchor.constraint(lessThanOrEqualToConstant: 260)
        presetPickerMaximumWidth.priority = .defaultHigh
        presetPickerMaximumWidth.isActive = true

        let nameTitle = NSTextField(labelWithString: "名称")
        nameTitle.font = RemoteTypography.font(ofSize: 13, weight: .semibold)
        let nameRow = NSStackView(views: [nameTitle, presetNameField])
        nameRow.orientation = .horizontal
        nameRow.alignment = .centerY
        nameRow.spacing = 10
        nameTitle.widthAnchor.constraint(equalToConstant: 66).isActive = true
        presetNameField.widthAnchor.constraint(greaterThanOrEqualToConstant: 150).isActive = true
        let presetNameMaximumWidth = presetNameField.widthAnchor.constraint(lessThanOrEqualToConstant: 260)
        presetNameMaximumWidth.priority = .defaultHigh
        presetNameMaximumWidth.isActive = true

        let configurationCard = SetupSurfaceView(radius: 20, emphasized: true)
        let buttonSpacer = NSView()
        let buttonRow = NSStackView(
            views: [createPresetButton, duplicatePresetButton, deletePresetButton, buttonSpacer, savePresetButton]
        )
        buttonRow.orientation = .horizontal
        buttonRow.alignment = .centerY
        buttonRow.spacing = 8
        buttonSpacer.widthAnchor.constraint(greaterThanOrEqualToConstant: 1).isActive = true

        let transferSpacer = NSView()
        let transferHint = NSTextField(
            wrappingLabelWithString: "导入会先安全校验，确认后替换自定义配置"
        )
        transferHint.font = RemoteTypography.font(ofSize: 10)
        transferHint.textColor = .tertiaryLabelColor
        transferHint.maximumNumberOfLines = 2
        let transferRow = NSStackView(
            views: [importPresetsButton, exportPresetsButton, transferSpacer, transferHint]
        )
        transferRow.orientation = .horizontal
        transferRow.alignment = .centerY
        transferRow.spacing = 8
        transferSpacer.widthAnchor.constraint(greaterThanOrEqualToConstant: 1).isActive = true

        presetStateLabel.font = RemoteTypography.font(ofSize: 11)
        presetStateLabel.textColor = .secondaryLabelColor
        presetStateLabel.maximumNumberOfLines = 2

        let configurationStack = NSStackView(
            views: [pickerRow, nameRow, buttonRow, transferRow, presetStateLabel]
        )
        configurationStack.translatesAutoresizingMaskIntoConstraints = false
        configurationStack.orientation = .vertical
        configurationStack.alignment = .leading
        configurationStack.spacing = 10
        configurationCard.addSubview(configurationStack)
        NSLayoutConstraint.activate([
            configurationStack.leadingAnchor.constraint(equalTo: configurationCard.leadingAnchor, constant: 18),
            configurationStack.trailingAnchor.constraint(equalTo: configurationCard.trailingAnchor, constant: -18),
            configurationStack.topAnchor.constraint(equalTo: configurationCard.topAnchor, constant: 16),
            configurationStack.bottomAnchor.constraint(equalTo: configurationCard.bottomAnchor, constant: -16),
            pickerRow.widthAnchor.constraint(equalTo: configurationStack.widthAnchor),
            nameRow.widthAnchor.constraint(equalTo: configurationStack.widthAnchor),
            buttonRow.widthAnchor.constraint(equalTo: configurationStack.widthAnchor),
            transferRow.widthAnchor.constraint(equalTo: configurationStack.widthAnchor),
            presetStateLabel.widthAnchor.constraint(equalTo: configurationStack.widthAnchor),
        ])

        let retainedLabel = NSTextField(
            wrappingLabelWithString: "保留项：语音键始终用于按住说话；菜单键始终保留 macOS 原生鼠标右键。自定义快捷键只由已校准的目标遥控器触发。"
        )
        retainedLabel.font = RemoteTypography.font(ofSize: 11)
        retainedLabel.textColor = .secondaryLabelColor
        retainedLabel.maximumNumberOfLines = 3
        let retainedCard = SetupSurfaceView(radius: 16)
        retainedLabel.translatesAutoresizingMaskIntoConstraints = false
        retainedCard.addSubview(retainedLabel)
        NSLayoutConstraint.activate([
            retainedLabel.leadingAnchor.constraint(equalTo: retainedCard.leadingAnchor, constant: 16),
            retainedLabel.trailingAnchor.constraint(equalTo: retainedCard.trailingAnchor, constant: -16),
            retainedLabel.topAnchor.constraint(equalTo: retainedCard.topAnchor, constant: 12),
            retainedLabel.bottomAnchor.constraint(equalTo: retainedCard.bottomAnchor, constant: -12),
        ])

        let mappingsHeader = buildSectionHeader(
            title: "按钮映射",
            detail: "保存后会立即通知运行中的遥声热更新；按 TV 切换时也会同步记住目标配置。"
        )
        let mappingStack = NSStackView()
        mappingStack.orientation = .vertical
        mappingStack.alignment = .leading
        mappingStack.spacing = 8
        for button in RemoteButton.allCases where button.isUserEditable {
            let row = ButtonMappingRowView(button: button)
            row.onBindingChanged = { [weak self] binding in
                self?.updateDraftBinding(binding, for: button)
            }
            row.onShortcutRequested = { [weak self] in
                self?.recordShortcut(for: button)
            }
            row.onTestRequested = { [weak self] in
                self?.testBinding(for: button)
            }
            mappingRows[button] = row
            mappingStack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: mappingStack.widthAnchor).isActive = true
        }

        let stack = NSStackView(
            views: [sectionHeader, configurationCard, retainedCard, mappingsHeader, mappingStack]
        )
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        [sectionHeader, configurationCard, retainedCard, mappingsHeader, mappingStack].forEach {
            $0.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        refreshPresetEditor()
        return stack
    }

    private func refreshPresetEditor() {
        let allPresets = presetCatalog.allPresets
        presetPicker.removeAllItems()
        for preset in allPresets {
            let item = NSMenuItem(title: preset.name, action: nil, keyEquivalent: "")
            item.representedObject = preset.id
            presetPicker.menu?.addItem(item)
        }
        if let selectedIndex = presetPicker.itemArray.firstIndex(where: {
            ($0.representedObject as? String) == selectedPresetID
        }) {
            presetPicker.selectItem(at: selectedIndex)
        }

        let storageWritable: Bool
        if case .unsupportedVersion = presetCatalogLoadState {
            storageWritable = false
        } else {
            storageWritable = true
        }
        let editable = storageWritable && !draftPreset.isBuiltIn
        presetNameField.stringValue = draftPreset.name
        presetNameField.isEnabled = editable
        duplicatePresetButton.isEnabled = storageWritable
        createPresetButton.isEnabled = storageWritable
        deletePresetButton.isEnabled = editable
        savePresetButton.isEnabled = editable && hasUnsavedPresetChanges
        importPresetsButton.isEnabled = storageWritable
        exportPresetsButton.isEnabled = storageWritable && !presetCatalog.userPresets.isEmpty
        presetPicker.isEnabled = storageWritable

        let targets = allPresets.filter { $0.id != draftPreset.id }
        for (button, row) in mappingRows {
            row.update(
                binding: draftPreset.binding(for: button),
                targetPresets: targets,
                editable: editable
            )
        }

        switch presetCatalogLoadState {
        case .defaults:
            presetStateLabel.stringValue =
                draftPreset.isBuiltIn
                ? "官方默认配置为只读。点击“新建”或“复制”创建自己的配置。"
                : "新配置尚未写入本地文件。"
        case .loaded:
            if draftPreset.isBuiltIn {
                presetStateLabel.stringValue = "官方默认配置为只读。点击“新建”或“复制”创建自己的配置。"
            } else if hasUnsavedPresetChanges {
                presetStateLabel.stringValue = "有未保存修改。保存后会立即热更新并用于后续启动。"
            } else {
                presetStateLabel.stringValue = "已保存到本机私有配置，并通知运行中的遥声热更新。"
            }
        case .recoveredInvalid(let url):
            presetStateLabel.stringValue = "已隔离损坏配置并恢复默认：\(url.lastPathComponent)"
        case .unsupportedVersion(let version):
            presetStateLabel.stringValue = "检测到较新的按键配置 schema v\(version)，为避免覆盖，当前只读。"
        }
    }

    @objc private func presetSelectionChanged() {
        guard let nextID = presetPicker.selectedItem?.representedObject as? String,
            nextID != selectedPresetID
        else { return }
        if hasUnsavedPresetChanges {
            let alert = NSAlert()
            alert.messageText = "保存当前配置修改？"
            alert.informativeText = "切换配置前，需要决定是否保存当前编辑内容。"
            alert.addButton(withTitle: "保存并切换")
            alert.addButton(withTitle: "放弃修改")
            alert.addButton(withTitle: "取消")
            switch alert.runModal() {
            case .alertFirstButtonReturn:
                guard persistDraft() else {
                    refreshPresetEditor()
                    return
                }
            case .alertSecondButtonReturn:
                break
            default:
                refreshPresetEditor()
                return
            }
        }
        selectPreset(id: nextID)
    }

    @objc private func createPreset() {
        guard prepareForNewPreset() else { return }
        createUserPreset(from: .pointer, name: "新配置")
    }

    @objc private func duplicatePreset() {
        guard prepareForNewPreset() else { return }
        createUserPreset(from: draftPreset, name: "\(draftPreset.name) 副本")
    }

    @objc private func deletePreset() {
        guard !draftPreset.isBuiltIn else { return }
        let alert = NSAlert()
        alert.messageText = "删除“\(draftPreset.name)”？"
        alert.informativeText = "删除后不可恢复。若另一配置的 TV 正在跳转到它，删除会被安全拒绝。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "删除")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let remaining = presetCatalog.userPresets.filter { $0.id != draftPreset.id }
        let nextCatalog = ButtonPresetCatalog(userPresets: remaining)
        do {
            try nextCatalog.validate()
            try presetStore.save(nextCatalog)
            presetCatalog = nextCatalog
            presetCatalogLoadState = .loaded
            hasUnsavedPresetChanges = false
            selectPreset(id: ButtonPreset.pointer.id)
        } catch {
            showError(title: "配置没有删除", message: error.localizedDescription)
            refreshPresetEditor()
        }
    }

    @objc private func savePreset() {
        _ = persistDraft()
    }

    @objc private func importPresets() {
        guard prepareForNewPreset() else { return }
        let panel = NSOpenPanel()
        panel.title = "导入遥声按键配置"
        panel.prompt = "检查导入"
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let sourceURL = panel.url else { return }

        do {
            let imported = try presetStore.importCatalog(from: sourceURL)
            let alert = NSAlert()
            alert.messageText = "替换当前自定义配置？"
            alert.informativeText =
                "已验证 \(imported.userPresets.count) 套配置的 schema、保留键、TV 目标与快捷键安全性。确认后会替换本机自定义配置，官方默认不受影响。"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "替换并立即生效")
            alert.addButton(withTitle: "取消")
            guard alert.runModal() == .alertFirstButtonReturn else { return }

            try presetStore.save(imported)
            presetCatalog = imported
            presetCatalogLoadState = .loaded
            let nextID =
                (try? imported.preset(id: selectedPresetID)) == nil
                ? ButtonPreset.pointer.id : selectedPresetID
            selectedPresetID = nextID
            draftPreset = (try? imported.preset(id: nextID)) ?? .pointer
            hasUnsavedPresetChanges = false
            try persistSelectedPresetID(nextID)
            refreshPresetEditor()
            presetStateLabel.stringValue = "已导入并通知运行时热更新。"
        } catch {
            showError(title: "按键配置未导入", message: error.localizedDescription)
        }
    }

    @objc private func exportPresets() {
        guard !presetCatalog.userPresets.isEmpty else { return }
        let panel = NSSavePanel()
        panel.title = "导出遥声按键配置"
        panel.prompt = "导出"
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "遥声按键配置.json"
        guard panel.runModal() == .OK, let destinationURL = panel.url else { return }
        do {
            try presetStore.export(presetCatalog, to: destinationURL)
            presetStateLabel.stringValue = "已导出 \(presetCatalog.userPresets.count) 套自定义配置。"
        } catch {
            showError(title: "按键配置未导出", message: error.localizedDescription)
        }
    }

    func controlTextDidChange(_ obj: Notification) {
        guard obj.object as? NSTextField === presetNameField,
            !draftPreset.isBuiltIn
        else { return }
        draftPreset = ButtonPreset(
            id: draftPreset.id,
            name: presetNameField.stringValue,
            bindings: draftPreset.bindings,
            requiredButtons: draftPreset.requiredButtons,
            isBuiltIn: false
        )
        hasUnsavedPresetChanges = true
        savePresetButton.isEnabled = true
        presetStateLabel.stringValue = "有未保存修改。保存后会立即热更新并用于后续启动。"
    }

    private func updateDraftBinding(_ binding: ButtonBinding, for button: RemoteButton) {
        guard !draftPreset.isBuiltIn else { return }
        var bindings = draftPreset.bindings
        bindings[button] = binding
        draftPreset = ButtonPreset(
            id: draftPreset.id,
            name: presetNameField.stringValue,
            bindings: bindings,
            requiredButtons: draftPreset.requiredButtons,
            isBuiltIn: false
        )
        hasUnsavedPresetChanges = true
        refreshPresetEditor()
    }

    private func recordShortcut(for button: RemoteButton) {
        guard !draftPreset.isBuiltIn, button.isUserEditable else { return }
        let recorder = ShortcutRecorderView(frame: .zero)
        let alert = NSAlert()
        alert.messageText = "录制 \(button.displayName) 的快捷键"
        alert.informativeText = "按下组合后点“使用快捷键”。遥声会在松手和异常退出时主动释放全部修饰键。"
        alert.accessoryView = recorder
        alert.addButton(withTitle: "使用快捷键")
        alert.addButton(withTitle: "取消")
        alert.window.initialFirstResponder = recorder
        DispatchQueue.main.async { [weak recorder] in
            recorder?.window?.makeFirstResponder(recorder)
        }
        guard alert.runModal() == .alertFirstButtonReturn, let shortcut = recorder.recordedShortcut else {
            refreshPresetEditor()
            return
        }
        updateDraftBinding(.keyboardShortcut(shortcut), for: button)
    }

    private func testBinding(for button: RemoteButton) {
        let binding = draftPreset.binding(for: button)
        switch binding {
        case .action(.voicePushToTalk):
            presetStateLabel.stringValue = "语音键需由真实遥控器按住测试，界面不会伪造录音。"
            return
        case .action(.unmapped):
            presetStateLabel.stringValue = "当前是不执行任何操作，无可测试动作。"
            return
        case .action, .keyboardShortcut, .presetSwitch:
            break
        }
        guard AXIsProcessTrusted() else {
            showError(
                title: "无法测试按键动作",
                message: "请先在“设备与权限”中完成辅助功能授权。"
            )
            return
        }
        stopActionTest()
        var userPresets = presetCatalog.userPresets
        if !draftPreset.isBuiltIn {
            if let index = userPresets.firstIndex(where: { $0.id == draftPreset.id }) {
                userPresets[index] = draftPreset
            } else {
                userPresets.append(draftPreset)
            }
        }
        let testCatalog = ButtonPresetCatalog(userPresets: userPresets)
        do {
            try testCatalog.validate()
        } catch {
            showError(title: "当前动作无法测试", message: error.localizedDescription)
            return
        }

        testFeedbackReceived = false
        let executor = ButtonActionExecutor(
            preset: draftPreset,
            catalog: testCatalog,
            activityHandler: { [weak self] activity in
                self?.presentActionTestFeedback(activity, binding: binding)
            }
        )
        testExecutor = executor
        testButton = button
        mappingRows[button]?.setActive(true)
        presetStateLabel.stringValue = "正在测试“\(button.displayName)”当前动作…"
        executor.buttonDown(button)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) { [weak self, weak executor] in
            guard let self, let executor else { return }
            executor.buttonUp(button)
            self.mappingRows[button]?.setActive(false)
            if binding == .action(.homePageNavigation) {
                DispatchQueue.main.asyncAfter(
                    deadline: .now() + ButtonActionExecutor.homeDoubleClickInterval + 0.12
                ) { [weak self, weak executor] in
                    guard let self, let executor, self.testExecutor === executor else { return }
                    self.finishActionTest(executor: executor)
                }
            } else {
                self.finishActionTest(executor: executor)
            }
        }
    }

    private func presentActionTestFeedback(
        _ activity: MiAoCommandActivity,
        binding: ButtonBinding
    ) {
        testFeedbackReceived = true
        if case .presetSwitch = binding {
            presetStateLabel.stringValue =
                "测试通过：\(activity.presentation.label)；测试不会更改当前运行配置。"
            return
        }
        if binding == .action(.modeTogglePointerDirectional) {
            presetStateLabel.stringValue =
                "测试通过：\(activity.presentation.label)；测试不会更改当前运行模式。"
            return
        }
        switch activity.presentation.tone {
        case .failure:
            presetStateLabel.stringValue = "测试失败：\(activity.presentation.label)"
        case .success:
            presetStateLabel.stringValue = "测试成功：\(activity.presentation.label)"
        case .command:
            presetStateLabel.stringValue = "已触发测试：\(activity.presentation.label)"
        case .neutral, .ready, .warning, .recording, .processing:
            presetStateLabel.stringValue = "测试反馈：\(activity.presentation.label)"
        }
    }

    private func finishActionTest(executor: ButtonActionExecutor) {
        guard testExecutor === executor else { return }
        if !testFeedbackReceived {
            presetStateLabel.stringValue = "测试未产生可确认动作，请检查当前配置。"
        }
        testExecutor = nil
        testButton = nil
    }

    private func stopActionTest() {
        if let testButton { testExecutor?.buttonUp(testButton) }
        if let testButton { mappingRows[testButton]?.setActive(false) }
        testExecutor = nil
        testButton = nil
        testFeedbackReceived = false
    }

    private func prepareForNewPreset() -> Bool {
        guard !hasUnsavedPresetChanges else {
            let alert = NSAlert()
            alert.messageText = "请先保存当前配置"
            alert.informativeText = "创建或复制前，先保存或切换并放弃当前修改。"
            alert.addButton(withTitle: "保存")
            alert.addButton(withTitle: "取消")
            guard alert.runModal() == .alertFirstButtonReturn else { return false }
            return persistDraft()
        }
        return true
    }

    private func createUserPreset(from source: ButtonPreset, name: String) {
        let preset = ButtonPreset(
            id: "user.\(UUID().uuidString.lowercased())",
            name: name,
            bindings: source.bindings,
            requiredButtons: ButtonPreset.pointer.requiredButtons,
            isBuiltIn: false
        )
        let nextCatalog = ButtonPresetCatalog(userPresets: presetCatalog.userPresets + [preset])
        do {
            try nextCatalog.validate()
            try presetStore.save(nextCatalog)
            presetCatalog = nextCatalog
            presetCatalogLoadState = .loaded
            selectedPresetID = preset.id
            draftPreset = preset
            hasUnsavedPresetChanges = false
            try persistSelectedPresetID(preset.id)
            refreshPresetEditor()
        } catch {
            showError(title: "配置没有创建", message: error.localizedDescription)
        }
    }

    private func selectPreset(id: String) {
        guard let preset = try? presetCatalog.preset(id: id) else {
            refreshPresetEditor()
            return
        }
        do {
            try persistSelectedPresetID(id)
            selectedPresetID = id
            draftPreset = preset
            hasUnsavedPresetChanges = false
            refreshPresetEditor()
        } catch {
            showError(title: "当前配置没有保存", message: error.localizedDescription)
            refreshPresetEditor()
        }
    }

    private func persistDraft() -> Bool {
        guard !draftPreset.isBuiltIn else { return true }
        let name = presetNameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let savedPreset = ButtonPreset(
            id: draftPreset.id,
            name: name,
            bindings: draftPreset.bindings,
            requiredButtons: draftPreset.requiredButtons,
            isBuiltIn: false
        )
        var userPresets = presetCatalog.userPresets
        guard let index = userPresets.firstIndex(where: { $0.id == savedPreset.id }) else {
            showError(title: "配置没有保存", message: "找不到要保存的配置")
            return false
        }
        userPresets[index] = savedPreset
        let nextCatalog = ButtonPresetCatalog(userPresets: userPresets)
        do {
            try nextCatalog.validate()
            try presetStore.save(nextCatalog)
            presetCatalog = nextCatalog
            presetCatalogLoadState = .loaded
            draftPreset = savedPreset
            hasUnsavedPresetChanges = false
            refreshPresetEditor()
            return true
        } catch {
            showError(title: "配置没有保存", message: error.localizedDescription)
            return false
        }
    }

    private func persistSelectedPresetID(_ id: String) throws {
        if case .unsupportedVersion(let version) = preferencesLoadState {
            throw AppPreferencesError.unsupportedVersion(version)
        }
        var updated = preferences
        updated.selectedPresetID = id
        try preferencesStore.save(updated)
        preferences = updated
        preferencesLoadState = .loaded
        MiAoRuntimeNotifications.postButtonConfigurationChanged()
    }

    private func buildSectionHeader(title: String, detail: String) -> NSView {
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = RemoteTypography.font(ofSize: 17, weight: .bold)
        let detailLabel = NSTextField(wrappingLabelWithString: detail)
        detailLabel.font = RemoteTypography.font(ofSize: 12)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.maximumNumberOfLines = 2
        let stack = NSStackView(views: [titleLabel, detailLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        return stack
    }

    @objc private func refreshPressed() {
        refresh()
    }

    private func refresh() {
        let current = preferencesStore.load()
        preferences = current.preferences
        preferencesLoadState = current.state
        configuration.speechEngine = Configuration().speechEngine
        updatePreferenceControls()
        updateDeviceControls()
        let report = inspector.inspect(
            configuration: configuration,
            preferences: preferences
        )
        self.report = report
        for check in report.checks {
            rows[check.id]?.update(
                check: check,
                target: self,
                action: #selector(performCheckAction(_:))
            )
        }

        if report.runtimeActive {
            summaryLabel.stringValue = "遥声当前已经运行。这里可以复查环境；退出请使用菜单栏中的安全退出。"
        } else if report.canStart {
            summaryLabel.stringValue = "环境已就绪。请先在系统蓝牙中连接遥控器，然后开始使用。"
        } else {
            let blockingChecks = report.checks.filter {
                $0.requirement.blocksStart && $0.state != .ready
            }
            summaryLabel.stringValue = footerMessage(for: blockingChecks)
        }
        refreshButton.isEnabled = process == nil
        updateFooterPrimaryAction(for: report)
        SetupInterfaceStyle.applyActionStyle(to: refreshButton, primary: false)
        SetupInterfaceStyle.applyActionStyle(to: startButton, primary: true)
    }

    private func footerMessage(for blockingChecks: [SetupCheck]) -> String {
        let names = blockingChecks.map(\.title).joined(separator: "、")
        return "尚需完成：\(names)。状态会自动刷新。"
    }

    private func updateFooterPrimaryAction(for report: SetupEnvironmentReport) {
        guard !report.runtimeActive else {
            startButton.title = "遥声正在运行"
            startButton.target = nil
            startButton.action = nil
            startButton.setAccessibilityLabel("遥声正在运行")
            startButton.isEnabled = false
            return
        }

        configureFooterAction(
            title: report.canStart ? "启动遥声" : "完成必要检查后启动", accessibilityLabel: "启动遥声", action: #selector(startPressed),
            isEnabled: report.canStart && process == nil)
    }

    private func configureFooterAction(
        title: String,
        accessibilityLabel: String,
        action: Selector,
        isEnabled: Bool
    ) {
        startButton.title = title
        startButton.target = self
        startButton.action = action
        startButton.setAccessibilityLabel(accessibilityLabel)
        startButton.isEnabled = isEnabled
    }

    private func updatePreferenceControls() {
        automaticSubmitCheckbox.state =
            preferences.submissionMode == .codex ? .on : .off
        buttonControlCheckbox.state = preferences.buttonControlEnabled ? .on : .off
        voiceConnectionModeControl.selectedSegment =
            preferences.voiceConnectionMode == .alwaysReady ? 0 : 1
        let preferencesAreWritable: Bool
        if case .unsupportedVersion = preferencesLoadState {
            preferencesAreWritable = false
        } else {
            preferencesAreWritable = true
        }
        automaticSubmitCheckbox.isEnabled = preferencesAreWritable
        buttonControlCheckbox.isEnabled = preferencesAreWritable
        voiceConnectionModeControl.isEnabled = preferencesAreWritable

        let loginState = loginItemController.state
        switch loginState {
        case .disabled:
            loginAtStartupCheckbox.state = .off
            loginAtStartupCheckbox.isEnabled = true
            openLoginItemsButton.isHidden = true
        case .enabled:
            loginAtStartupCheckbox.state = .on
            loginAtStartupCheckbox.isEnabled = true
            openLoginItemsButton.isHidden = true
        case .requiresApproval:
            loginAtStartupCheckbox.state = .on
            loginAtStartupCheckbox.isEnabled = true
            openLoginItemsButton.isHidden = false
        case .unavailable:
            loginAtStartupCheckbox.state = .off
            loginAtStartupCheckbox.isEnabled = true
            openLoginItemsButton.isHidden = true
        }
        loginItemStateLabel.stringValue = loginState.detail

        switch preferencesLoadState {
        case .defaults, .loaded:
            preferenceStateLabel.stringValue = ""
        case .recoveredInvalid(let url):
            preferenceStateLabel.stringValue =
                "已隔离损坏配置并恢复默认：\(url.lastPathComponent)"
        case .unsupportedVersion(let version):
            preferenceStateLabel.stringValue =
                "检测到较新的配置 schema v\(version)，当前以安全默认值运行且未覆盖原文件"
        }
    }

    private func updateDeviceControls() {
        guard devicePicker.menu != nil else { return }
        let selectedID = preferences.preferredPeripheralIdentifier
        devicePicker.removeAllItems()

        let automaticItem = NSMenuItem(
            title: "自动选择最佳兼容遥控器",
            action: nil,
            keyEquivalent: ""
        )
        automaticItem.representedObject = "automatic"
        devicePicker.menu?.addItem(automaticItem)

        if let selectedID,
            !discoveredDevices.contains(where: { $0.identifier == selectedID })
        {
            let savedItem = NSMenuItem(
                title: "已保存遥控器 · \(selectedID.uuidString.suffix(8))",
                action: nil,
                keyEquivalent: ""
            )
            savedItem.representedObject = selectedID.uuidString
            devicePicker.menu?.addItem(savedItem)
        }

        for device in discoveredDevices {
            var parts = [device.name]
            if device.isConnected { parts.append("已连接") }
            if device.rssi != -127 { parts.append("\(device.rssi) dBm") }
            let item = NSMenuItem(
                title: parts.joined(separator: " · "),
                action: nil,
                keyEquivalent: ""
            )
            item.representedObject = device.identifier.uuidString
            devicePicker.menu?.addItem(item)
        }

        let representedSelection = selectedID?.uuidString ?? "automatic"
        if let item = devicePicker.itemArray.first(where: {
            $0.representedObject as? String == representedSelection
        }) {
            devicePicker.select(item)
        }

        let writable: Bool
        if case .unsupportedVersion = preferencesLoadState {
            writable = false
        } else {
            writable = true
        }
        devicePicker.isEnabled = writable
        scanDevicesButton.isEnabled = process == nil && deviceDiscoveryState != .scanning
        scanDevicesButton.title = deviceDiscoveryState == .scanning ? "正在扫描…" : "扫描遥控器"
        SetupInterfaceStyle.applyActionStyle(to: scanDevicesButton, primary: false, compact: true)

        switch deviceDiscoveryState {
        case .idle:
            deviceStateLabel.stringValue =
                selectedID == nil
                ? "当前由运行时自动仲裁；可扫描并固定设备。"
                : "已固定到保存的遥控器；下次连接会优先使用它。"
        case .waitingForBluetooth:
            deviceStateLabel.stringValue = "正在等待 macOS 蓝牙状态…"
        case .scanning:
            deviceStateLabel.stringValue =
                discoveredDevices.isEmpty
                ? "正在查找兼容遥控器…"
                : "已发现 \(discoveredDevices.count) 个兼容遥控器，扫描结束前仍可选择。"
        case .finished:
            deviceStateLabel.stringValue =
                discoveredDevices.isEmpty
                ? "未发现兼容遥控器。请确认遥控器已配对并在附近。"
                : "扫描完成，可从上方选择要固定的遥控器。"
        case .unavailable(let message):
            deviceStateLabel.stringValue = message
        }
    }

    private func startObservingButtonActivity() {
        guard !isObservingButtonActivity else { return }
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(runtimeButtonActivity),
            name: MiAoRuntimeNotifications.buttonActivity,
            object: nil
        )
        isObservingButtonActivity = true
    }

    private func stopObservingButtonActivity() {
        guard isObservingButtonActivity else { return }
        DistributedNotificationCenter.default().removeObserver(
            self,
            name: MiAoRuntimeNotifications.buttonActivity,
            object: nil
        )
        isObservingButtonActivity = false
        buttonHighlightTimers.values.forEach { $0.invalidate() }
        buttonHighlightTimers.removeAll()
        mappingRows.values.forEach { $0.setActive(false) }
    }

    @objc private func runtimeButtonActivity(_ notification: Notification) {
        guard let rawButton = notification.userInfo?["button"] as? String,
            let button = RemoteButton(rawValue: rawButton),
            let phase = notification.userInfo?["phase"] as? String,
            let row = mappingRows[button]
        else { return }

        buttonHighlightTimers[button]?.invalidate()
        buttonHighlightTimers[button] = nil
        let isPressed = phase == "down"
        row.setActive(isPressed)
        guard isPressed else { return }
        buttonHighlightTimers[button] = Timer.scheduledTimer(
            withTimeInterval: 1.2,
            repeats: false
        ) { [weak self, weak row] _ in
            Task { @MainActor in
                row?.setActive(false)
                self?.buttonHighlightTimers[button] = nil
            }
        }
    }

    @objc private func scanDevices() {
        deviceDiscoveryController.start(
            preferredIdentifier: preferences.preferredPeripheralIdentifier
        )
    }

    @objc private func deviceSelectionChanged() {
        guard let selected = devicePicker.selectedItem?.representedObject as? String else {
            return
        }
        let previous = preferences
        preferences.preferredPeripheralIdentifier =
            selected == "automatic" ? nil : UUID(uuidString: selected)
        do {
            try preferencesStore.save(preferences)
            preferencesLoadState = .loaded
            deviceStateLabel.stringValue =
                preferences.preferredPeripheralIdentifier == nil
                ? "已改为自动仲裁；下次重连时生效。"
                : "已保存首选遥控器；下次重连时生效。"
        } catch {
            preferences = previous
            showError(title: "遥控器选择没有保存", message: error.localizedDescription)
            updateDeviceControls()
        }
    }

    @objc private func preferencesChanged() {
        let previous = preferences
        preferences.submissionMode =
            automaticSubmitCheckbox.state == .on ? .codex : .transcriptionOnly
        preferences.buttonControlEnabled = buttonControlCheckbox.state == .on
        preferences.voiceConnectionMode =
            voiceConnectionModeControl.selectedSegment == 1 ? .smartSleep : .alwaysReady
        do {
            try preferencesStore.save(preferences)
            preferencesLoadState = .loaded
            if preferences.voiceConnectionMode != previous.voiceConnectionMode {
                MiAoRuntimeNotifications.postVoiceConnectionModeChanged()
            }
        } catch {
            preferences = previous
            showError(title: "偏好设置没有保存", message: error.localizedDescription)
        }
        refresh()
    }

    @objc private func loginItemChanged() {
        let requested = loginAtStartupCheckbox.state == .on
        do {
            try loginItemController.setEnabled(requested)
        } catch {
            showError(title: "登录时启动没有更改", message: error.localizedDescription)
        }
        refresh()
    }

    @objc private func openLoginItemsSettings() {
        loginItemController.openSystemSettings()
    }

    @objc private func configureQwen() {
        guard process == nil, report?.runtimeActive != true else {
            showError(title: "请先退出语音运行", message: "退出菜单栏中的运行进程后再更换模型。")
            return
        }
        let modelPanel = NSOpenPanel()
        modelPanel.title = InterfaceStyle.text("选择 Qwen3-ASR 的 MLX 模型文件夹")
        modelPanel.canChooseDirectories = true
        modelPanel.canChooseFiles = false
        modelPanel.allowsMultipleSelection = false
        guard modelPanel.runModal() == .OK, let model = modelPanel.url else { return }
        let pythonPanel = NSOpenPanel()
        pythonPanel.title = InterfaceStyle.text("选择已安装 mlx-audio 的 Python 可执行文件")
        pythonPanel.showsHiddenFiles = true
        pythonPanel.canChooseDirectories = false
        pythonPanel.canChooseFiles = true
        pythonPanel.allowsMultipleSelection = false
        guard pythonPanel.runModal() == .OK, let python = pythonPanel.url,
            let context = MiAoInstallationContext.load()
        else { return }
        runScript(
            context.runtimeURL.appendingPathComponent("scripts/configure-qwen.sh"),
            arguments: [python.path, model.path], progress: "正在验证Qwen环境与模型…"
        ) { [weak self] result in
            switch result {
            case .success:
                self?.configuration.speechEngine = "qwen"
                self?.refresh()
            case .failure(let error):
                self?.showError(title: "Qwen配置未完成", message: error.localizedDescription)
            }
        }
    }

    @objc private func performCheckAction(_ sender: NSButton) {
        guard
            let rawID = sender.identifier?.rawValue,
            let id = SetupCheckID(rawValue: rawID),
            let action = report?.check(id)?.action
        else { return }

        switch action {
        case .requestAccessibility:
            repairAccessibilityAuthorization()
        case .requestBluetooth:
            bluetoothRequester = BluetoothAuthorizationRequester { [weak self] in
                self?.scheduleRefresh()
            }
            bluetoothRequester?.start()
        case .openBluetoothSettings:
            openBluetoothSettings()
        case .openBluetoothPrivacy:
            openPrivacyPane(anchor: "Privacy_Bluetooth")
        case .prepareCodex:
            prepareCodex()
        case .runSetup:
            runSetupRepair()
        case .revealSource:
            NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
        }
    }

    @objc private func startPressed() {
        refresh()
        guard report?.canStart == true, let context = MiAoInstallationContext.load(), context.isValid
        else {
            showReadinessSheet()
            return
        }
        runScript(
            context.startScriptURL,
            arguments: preferences.runtimeArguments,
            progress: "正在执行启动门禁并连接遥控器…"
        ) { [weak self] result in
            switch result {
            case .success(let output):
                var completedPreferences = self?.preferences ?? .defaults
                completedPreferences.hasCompletedSetup = true
                if let loadState = self?.preferencesLoadState,
                    case .unsupportedVersion = loadState
                {
                    // Preserve the future-version file verbatim.
                } else {
                    do {
                        try self?.preferencesStore.save(completedPreferences)
                        self?.preferences = completedPreferences
                        self?.preferencesLoadState = .loaded
                    } catch {
                        self?.showError(
                            title: "遥声已启动，但设置未保存",
                            message: error.localizedDescription
                        )
                        self?.refresh()
                        return
                    }
                }
                self?.summaryLabel.stringValue =
                    output.isEmpty
                    ? "遥声已启动，请查看菜单栏。"
                    : output
                self?.showLaunchSuccessAndFinish()
            case .failure(let error):
                self?.showError(title: "遥声没有启动", message: error.localizedDescription)
                self?.refresh()
            }
        }
    }

    private func showLaunchSuccessAndFinish() {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "遥声已在菜单栏运行"
        alert.informativeText = "设置已保存。接下来可以从菜单栏查看连接状态、打开设置或安全退出。"
        alert.addButton(withTitle: "完成")
        guard let window else {
            alert.runModal()
            NSApplication.shared.terminate(nil)
            return
        }
        alert.beginSheetModal(for: window) { _ in
            NSApplication.shared.terminate(nil)
        }
    }

    private func prepareCodex() {
        guard let context = MiAoInstallationContext.load(), context.isValid else {
            showError(title: "缺少启动脚本", message: "请从本地项目目录重新运行 ./scripts/setup.sh。")
            return
        }
        let snapshot = inspector.codexSnapshot()
        if snapshot.isRunning && !snapshot.compatibilityEnabled {
            let alert = NSAlert()
            alert.messageText = "需要重启一次 Codex"
            alert.informativeText =
                "这只为下一次 Codex 进程加入官方 Chromium 辅助功能参数，不修改偏好设置。请先确认当前 Codex 工作已经可以安全重启。"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "重启并准备")
            alert.addButton(withTitle: "稍后")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        let arguments = snapshot.isRunning ? ["enable", "--restart"] : ["enable"]
        runScript(
            context.codexAccessibilityScriptURL,
            arguments: arguments,
            progress: "正在准备 Codex 输入区…"
        ) { [weak self] result in
            if case .failure(let error) = result {
                self?.showError(title: "Codex 准备失败", message: error.localizedDescription)
            }
            self?.refresh()
        }
    }

    private func repairAccessibilityAuthorization() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        if AXIsProcessTrustedWithOptions(options) {
            refresh()
            return
        }

        let alert = NSAlert()
        alert.messageText = "请重新添加当前遥声 App"
        alert.informativeText =
            "源码版更新后 ad-hoc 签名会变化。系统设置里即使旧“遥声”仍显示开启，也不代表当前构建已获授权。请选中旧“遥声”并移除，再点击“+”添加 Finder 中显示的当前 App。向导会自动刷新，无需重启。"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "打开设置并显示 App")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
        openPrivacyPane(anchor: "Privacy_Accessibility")
        scheduleRefresh()
    }

    private func runSetupRepair() {
        guard let context = MiAoInstallationContext.load(), context.isValid else {
            showError(title: "启动组件损坏", message: "请从项目目录重新运行 ./scripts/setup.sh 恢复 App。")
            return
        }
        let alert = NSAlert()
        alert.messageText = "修复本地语音引擎"
        alert.informativeText = "将使用 App 内置组件安装缺失的 whisper.cpp 或语音模型，不会覆盖 App，也不会删除录音和配置。"
        alert.addButton(withTitle: "开始修复")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        runScript(
            context.setupScriptURL,
            arguments: [],
            progress: "正在修复安装，这可能需要几分钟…"
        ) { [weak self] result in
            if case .failure(let error) = result {
                self?.showError(title: "修复失败", message: error.localizedDescription)
            }
            self?.refresh()
        }
    }

    private func runScript(
        _ scriptURL: URL,
        arguments: [String],
        progress: String,
        completion: @escaping @MainActor @Sendable (Result<String, Error>) -> Void
    ) {
        guard process == nil else { return }
        let logURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("mi-ao-gui-\(UUID().uuidString).log")
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        guard let logHandle = try? FileHandle(forWritingTo: logURL) else {
            completion(.failure(BridgeError.configuration("无法创建临时运行日志")))
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [scriptURL.path] + arguments
        process.currentDirectoryURL = scriptURL.deletingLastPathComponent().deletingLastPathComponent()
        process.environment = MiAoProcessEnvironment.sanitizedForExternalProcess()
        process.standardOutput = logHandle
        process.standardError = logHandle
        self.process = process
        summaryLabel.stringValue = progress
        (window?.contentView as? RemoteHomeView)?.setBusy(progress)
        startButton.isEnabled = false
        refreshButton.isEnabled = false

        process.terminationHandler = { [weak self] terminated in
            try? logHandle.close()
            let data = (try? Data(contentsOf: logURL)) ?? Data()
            try? FileManager.default.removeItem(at: logURL)
            let output =
                String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let terminationStatus = terminated.terminationStatus
            DispatchQueue.main.async {
                self?.process = nil
                (self?.window?.contentView as? RemoteHomeView)?.setBusy(nil)
                if terminationStatus == 0 {
                    completion(.success(output))
                } else {
                    let message =
                        output.isEmpty
                        ? "脚本退出码：\(terminationStatus)"
                        : output
                    completion(.failure(BridgeError.configuration(message)))
                }
            }
        }
        do {
            try process.run()
        } catch {
            self.process = nil
            (window?.contentView as? RemoteHomeView)?.setBusy(nil)
            try? logHandle.close()
            try? FileManager.default.removeItem(at: logURL)
            completion(.failure(error))
            refresh()
        }
    }

    private func openPrivacyPane(anchor: String) {
        guard
            let url = URL(
                string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)"
            )
        else { return }
        NSWorkspace.shared.open(url)
    }

    private func openBluetoothSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings")
        else { return }
        NSWorkspace.shared.open(url)
    }

    private func scheduleRefresh() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.refresh()
        }
    }

    private func startAutoRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) {
            [weak self] _ in
            Task { @MainActor in
                guard self?.window?.isVisible == true else { return }
                self?.refresh()
            }
        }
        refreshTimer?.tolerance = 0.25
    }

    private func showError(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }
}

private final class BluetoothAuthorizationRequester: NSObject, CBCentralManagerDelegate {
    private let completion: () -> Void
    private var manager: CBCentralManager?

    init(completion: @escaping () -> Void) {
        self.completion = completion
    }

    func start() {
        manager = CBCentralManager(
            delegate: self,
            queue: .main,
            options: [CBCentralManagerOptionShowPowerAlertKey: false]
        )
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        completion()
        if CBManager.authorization != .notDetermined {
            manager = nil
        }
    }
}
