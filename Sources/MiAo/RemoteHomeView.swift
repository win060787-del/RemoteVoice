import AppKit
import ApplicationServices
import CoreBluetooth
import SceneKit

final class RemoteHomeView: NSView {
    private let batteryMonitor = BatteryMonitor()
    private weak var serviceButton: NSButton?
    private var busy = false
    private var scanSheet: DeviceScanSheet?
    private let deviceDiscovery = RemoteDeviceDiscoveryController()
    private let devicePicker = NSPopUpButton()
    private weak var sceneView: RemoteSceneView?
    private var statusTimer: Timer?
    private var transcriptionControl: NSSegmentedControl?
    private let backdrop = CAGradientLayer()
    private let halo = CAGradientLayer()
    private let groundShadow = CAGradientLayer()
    private let open: (Int) -> Void
    init(frame: NSRect, running: Bool, open: @escaping (Int) -> Void) {
        self.open = open
        super.init(frame: frame)
        appearance = InterfaceStyle.appearance
        wantsLayer = true
        backdrop.colors = [InterfaceStyle.background.cgColor, InterfaceStyle.background.cgColor]
        backdrop.locations = [0, 0.58, 1]
        layer?.addSublayer(backdrop)
        halo.type = .radial
        halo.colors = [
            NSColor(white: InterfaceStyle.dark ? 0.17 : 1, alpha: 1).cgColor,
            NSColor(white: InterfaceStyle.dark ? 0.09 : 0.90, alpha: 0.45).cgColor,
            NSColor(white: 0.96, alpha: 0).cgColor,
        ]
        halo.locations = [0, 0.55, 1]
        halo.startPoint = CGPoint(x: 0.5, y: 0.5)
        halo.endPoint = CGPoint(x: 1, y: 1)
        halo.isHidden = true
        layer?.addSublayer(halo)
        groundShadow.type = .radial
        groundShadow.colors = [NSColor(white: 0.25, alpha: 0.24).cgColor, NSColor(white: 0.4, alpha: 0).cgColor]
        groundShadow.startPoint = CGPoint(x: 0.5, y: 0.5)
        groundShadow.endPoint = CGPoint(x: 1, y: 1)
        groundShadow.zPosition = 1
        layer?.addSublayer(groundShadow)
        let device = RemoteDeviceStatus.load()
        let initiallyConnected = device.connected || HIDConnectionStatus.connectedName() != nil
        let state = NSButton(
            title: device.connected ? "● 已连接" : "● 未连接", target: self, action: #selector(connectionGuide))
        state.isBordered = false
        state.attributedTitle = Self.connectionTitle(initiallyConnected)
        state.font = NSFont(name: "PingFangSC-Regular", size: 12)
        state.setAccessibilityLabel("遥控器连接状态，点击显示配置指南")
        let scene = RemoteSceneView()
        scene.scene = Self.remoteScene()
        sceneView = scene
        scene.onButtonClick = { [weak self] button in self?.editMapping(button) }
        scene.backgroundColor = InterfaceStyle.background
        scene.allowsCameraControl = true
        scene.cameraControlConfiguration.allowsTranslation = false
        scene.autoenablesDefaultLighting = false
        scene.antialiasingMode = .multisampling4X
        scene.setAccessibilityLabel("三维遥控器，可拖动旋转和缩放")
        let batteryStatus = BatteryStatusBadge()
        batteryStatus.setAccessibilityElement(true)
        batteryStatus.setAccessibilityRole(.button)
        batteryStatus.onRefresh = { [weak self] in
            self?.batteryMonitor.refresh(
                preferred: AppPreferencesStore().load().preferences.preferredPeripheralIdentifier)
        }
        batteryStatus.level = nil
        batteryStatus.toolTip = "独立读取遥控器电量，点击刷新"
        let status = NSStackView(views: [state, batteryStatus])
        status.spacing = 16
        statusTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) {
            [weak self, weak state, weak batteryStatus] _ in
            MainActor.assumeIsolated {
                let value = RemoteDeviceStatus.load()
                let selected = AppPreferencesStore().load().preferences.preferredPeripheralIdentifier
                let connections = self?.deviceDiscovery.connectedDevices() ?? []
                let bluetoothConnected =
                    connections.contains {
                        $0.isConnected && (selected == nil || selected == $0.identifier)
                    } || HIDConnectionStatus.connectedName() != nil
                state?.attributedTitle = Self.connectionTitle(value.connected || bluetoothConnected)
                state?.toolTip = InterfaceStyle.text(
                    value.connected ? "语音连接已建立" : bluetoothConnected ? "蓝牙已连接，语音服务尚未就绪" : "点击检查连接与权限")
                self?.batteryMonitor.synchronize(preferred: selected)
                batteryStatus?.level = self?.batteryMonitor.percent
                batteryStatus?.toolTip = self.map { InterfaceStyle.text($0.batteryMonitor.detail) }
                if self?.busy == false {
                    self?.serviceButton?.title = InterfaceStyle.text(
                        RemoteDeviceStatus.runtimeActive ? "停止语音服务" : "启动语音服务")
                }
            }
        }
        devicePicker.isBordered = false
        devicePicker.heightAnchor.constraint(equalToConstant: 28).isActive = true
        devicePicker.widthAnchor.constraint(greaterThanOrEqualToConstant: 180).isActive = true
        devicePicker.font = NSFont(name: "PingFangSC-Regular", size: 12)
        devicePicker.target = self
        devicePicker.action = #selector(selectDevice)
        devicePicker.setAccessibilityLabel("选择遥控器")
        devicePicker.toolTip = "更换遥控器在下次启动语音服务时生效"
        populateDevices([])
        deviceDiscovery.onUpdate = { [weak self] _, devices in self?.populateDevices(devices) }
        if CBManager.authorization == .allowedAlways {
            deviceDiscovery.start(
                preferredIdentifier: AppPreferencesStore().load().preferences.preferredPeripheralIdentifier)
        }
        let scan = SurfaceActionButton(title: "扫描", target: self, action: #selector(scanDevices))
        scan.font = NSFont(name: "PingFangSC-Regular", size: 12)
        scan.isBordered = false
        scan.widthAnchor.constraint(equalToConstant: 48).isActive = true
        scan.heightAnchor.constraint(equalToConstant: 28).isActive = true
        let devicesRow = NSStackView(views: [devicePicker, scan])
        devicesRow.spacing = 8
        let deviceContent = NSStackView(views: [status])
        deviceContent.orientation = .vertical
        deviceContent.alignment = .leading
        deviceContent.spacing = 10
        deviceContent.translatesAutoresizingMaskIntoConstraints = false
        let deviceCard = NSView()
        deviceCard.wantsLayer = true
        deviceCard.layer?.backgroundColor = NSColor.clear.cgColor
        deviceCard.layer?.cornerRadius = 14
        deviceCard.layer?.borderWidth = 0
        deviceCard.layer?.borderColor = NSColor.black.withAlphaComponent(0.04).cgColor
        deviceCard.addSubview(deviceContent)
        NSLayoutConstraint.activate([
            deviceContent.leadingAnchor.constraint(equalTo: deviceCard.leadingAnchor, constant: 14),
            deviceContent.trailingAnchor.constraint(equalTo: deviceCard.trailingAnchor, constant: -14),
            deviceContent.topAnchor.constraint(equalTo: deviceCard.topAnchor, constant: 12),
            deviceContent.bottomAnchor.constraint(equalTo: deviceCard.bottomAnchor, constant: -12),
        ])
        let pref = AppPreferencesStore().load().preferences
        let input = HomeRuntimeOptions.load()
        let actions = NSStackView(views: [
            panel(
                "语音输入",
                rows: [
                    button("启动语音服务", symbol: "power", tag: 12),
                    choice(
                        "转录方式", labels: ["整段", "逐句"],
                        selected: Configuration().speechEngine == "qwen" && input.streaming ? 1 : 0, tag: 20),
                    toggle("填入输入框", on: pref.submissionMode == .codex, tag: 21),
                    toggle("自动发送", on: input.automaticSend, tag: 22),
                ]),
            panel(
                "遥控器",
                rows: [
                    row("设备选择", control: devicesRow),
                    choice("控制模式", labels: ["鼠标", "聚焦"], selected: pref.controlMode == .pointer ? 0 : 1, tag: 24),
                    toggle("按键控制", on: pref.buttonControlEnabled, tag: 25),
                    choice(
                        "语音连接", labels: ["随时就绪", "智能休眠"], selected: pref.voiceConnectionMode == .alwaysReady ? 0 : 1,
                        tag: 23),
                ]),
            panel(
                "模型与系统",
                rows: [
                    choice(
                        "本机引擎", labels: ["Whisper", "Qwen"], selected: Configuration().speechEngine == "qwen" ? 1 : 0,
                        tag: 28),
                    buttonGroup([
                        button("配置 Qwen…", symbol: "waveform", tag: 10),
                        button("修复 Whisper", symbol: "arrow.down.circle", tag: 14),
                    ]),
                    choice(
                        "外观", labels: ["跟随系统", "浅色", "深色"],
                        selected: InterfaceStyle.theme == "dark" ? 2 : InterfaceStyle.theme == "light" ? 1 : 0, tag: 29),
                    choice(
                        "界面语言", labels: ["中文", "English"], selected: InterfaceStyle.language == "en" ? 1 : 0, tag: 30),
                    toggle("登录时启动", on: LoginItemController().state == .enabled, tag: 27),
                    button(AXIsProcessTrusted() ? "辅助功能 · 已授权" : "辅助功能 · 去授权", symbol: "lock.shield", tag: 11),
                ]),
        ])
        actions.orientation = .vertical
        actions.alignment = .leading
        for card in actions.arrangedSubviews {
            card.widthAnchor.constraint(equalTo: actions.widthAnchor).isActive = true
        }
        actions.spacing = 16
        let divider = NSBox()
        divider.boxType = .separator
        for view in [scene, deviceCard, actions, divider] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        let zoom = NSStackView(views: [
            zoomButton("minus.magnifyingglass", tag: -1), zoomButton("plus.magnifyingglass", tag: 1),
        ])
        zoom.spacing = 8
        zoom.translatesAutoresizingMaskIntoConstraints = false
        addSubview(zoom)
        NSLayoutConstraint.activate([
            zoom.trailingAnchor.constraint(equalTo: divider.leadingAnchor, constant: -28),
            zoom.topAnchor.constraint(equalTo: topAnchor, constant: 32),
        ])
        NSLayoutConstraint.activate([
            divider.centerXAnchor.constraint(equalTo: centerXAnchor, constant: 40),
            divider.topAnchor.constraint(equalTo: topAnchor, constant: 28),
            divider.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -28),
            divider.widthAnchor.constraint(equalToConstant: 1),
            deviceCard.topAnchor.constraint(equalTo: topAnchor, constant: 32),
            deviceCard.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 32),
            deviceCard.trailingAnchor.constraint(lessThanOrEqualTo: divider.leadingAnchor, constant: -24),
            scene.topAnchor.constraint(equalTo: deviceCard.bottomAnchor, constant: 24),
            scene.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            scene.trailingAnchor.constraint(equalTo: divider.leadingAnchor, constant: -12),
            scene.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -28),
            actions.leadingAnchor.constraint(equalTo: divider.trailingAnchor, constant: 28),
            actions.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -28),
            actions.topAnchor.constraint(equalTo: topAnchor, constant: 32),
            actions.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -28),
        ])
        InterfaceStyle.apply(self)
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(systemAppearanceChanged),
            name: Notification.Name("AppleInterfaceThemeChangedNotification"), object: nil)
    }

    @objc private func systemAppearanceChanged() {
        guard InterfaceStyle.theme == "system", window != nil else { return }
        window?.appearance = InterfaceStyle.appearance
        window?.contentView = RemoteHomeView(frame: bounds, running: RemoteDeviceStatus.runtimeActive, open: open)
    }
    func setBusy(_ progress: String?) {
        busy = progress != nil
        serviceButton?.isEnabled = !busy
        serviceButton?.title = InterfaceStyle.text(progress ?? (RemoteDeviceStatus.runtimeActive ? "停止语音服务" : "启动语音服务"))
    }
    private static func connectionTitle(_ connected: Bool) -> NSAttributedString {
        let value = NSMutableAttributedString(
            string: InterfaceStyle.text(connected ? "● 已连接" : "● 未连接"),
            attributes: [
                .font: NSFont(name: "PingFangSC-Regular", size: 12)!, .foregroundColor: NSColor.secondaryLabelColor,
            ])
        value.addAttribute(
            .foregroundColor, value: connected ? NSColor.systemGreen : NSColor.systemRed,
            range: NSRange(location: 0, length: 1))
        return value
    }
    override func layout() {
        super.layout()
        backdrop.frame = bounds
        halo.frame = CGRect(
            x: bounds.width * 0.12, y: bounds.height * 0.19, width: bounds.width * 0.76, height: bounds.height * 0.65)
        groundShadow.frame = CGRect(x: bounds.width * 0.27 - 110, y: 70, width: 220, height: 32)
    }
    required init?(coder: NSCoder) { nil }
    private func button(_ title: String, symbol: String, tag: Int) -> NSButton {
        let b = SurfaceActionButton(title: title, target: self, action: #selector(navigate(_:)))
        b.tag = tag
        b.primary = tag == 12
        if tag == 12 { serviceButton = b; b.title = RemoteDeviceStatus.runtimeActive ? "停止语音服务" : "启动语音服务" }
        b.bezelStyle = .rounded
        b.isBordered = false
        b.wantsLayer = true
        b.layer?.cornerRadius = 8
        b.layer?.backgroundColor = NSColor.white.cgColor
        b.font = NSFont(name: "PingFangSC-Regular", size: 14)
        let descriptions = [
            12: "检查环境并启动语音与按键服务。", 10: "选择本机 Qwen 模型文件夹和 Python 运行环境。", 14: "安装或修复 Whisper 及其本地识别模型。",
            11: "打开 macOS 辅助功能授权设置。",
        ]
        b.toolTip = descriptions[tag]
        b.image = nil
        b.imagePosition = .imageLeading
        b.imageScaling = .scaleProportionallyDown
        b.contentTintColor = .black
        b.heightAnchor.constraint(equalToConstant: tag == 12 ? 40 : 34).isActive = true
        return b
    }
    @objc private func navigate(_ sender: NSButton) {
        if sender.tag == 11 {
            NSWorkspace.shared.open(
                URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        } else {
            open(sender.tag)
        }
    }
    private func buttonGroup(_ buttons: [NSView]) -> NSStackView {
        let group = NSStackView(views: buttons)
        group.spacing = 8
        group.distribution = .fillEqually
        return group
    }
    private func panel(_ title: String, rows: [NSView]) -> NSView {
        let heading = NSTextField(labelWithString: title)
        heading.font = NSFont(name: "PingFangSC-Medium", size: 15)
        let stack = NSStackView(views: [heading] + rows)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        let card = TintedControlCard(title: title)
        card.wantsLayer = true
        card.layer?.backgroundColor = InterfaceStyle.surface.cgColor
        card.layer?.cornerRadius = 18
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -18),
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16),
        ])
        for row in rows { row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
        return card
    }
    private func row(_ title: String, control: NSView) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.font = NSFont(name: "PingFangSC-Regular", size: 13)
        let spacer = NSView()
        let symbols = [
            "外观": "circle.lefthalf.filled", "界面语言": "globe", "设备选择": "antenna.radiowaves.left.and.right", "本机引擎": "cpu",
            "转录方式": "text.alignleft",
            "填入输入框": "text.cursor", "自动发送": "paperplane", "语音连接": "waveform",
            "控制模式": "cursorarrow", "按键控制": "keyboard", "显示按键指南": "list.bullet", "登录时启动": "power",
        ]
        let icon = NSImageView(
            image: NSImage(systemSymbolName: symbols[title] ?? "circle", accessibilityDescription: nil)!)
        icon.alphaValue = 0.75
        icon.widthAnchor.constraint(equalToConstant: 16).isActive = true
        let iconSpace = NSView()
        iconSpace.widthAnchor.constraint(equalToConstant: 16).isActive = true
        icon.setAccessibilityElement(false)
        let stack = NSStackView(views: [title == "控制模式" ? iconSpace : icon, label, spacer, control])
        let descriptions = [
            "设备选择": "扫描并选择已配对的兼容遥控器，更换设备后重启语音服务生效。",
            "转录方式": "整段：松开后一次转录。逐句：说话时分段识别并更新输入框，目前仅支持 Qwen。",
            "填入输入框": "开启后把识别结果填入当前输入框；关闭后只保留本地转写。",
            "自动发送": "默认关闭。开启后在最终转写完成、输入焦点核验成功时发送。",
            "控制模式": "鼠标模式移动指针、确认键为左键；聚焦模式使用方向键、确认键为回车。TV 键也可切换。",
            "按键控制": "使用遥控器控制鼠标和键盘。此项在重启语音服务后生效。",
            "语音连接": "随时就绪会自动恢复连接；智能休眠在连续失败后等待按键唤醒。",
            "本机引擎": "Whisper 使用整段转录；Qwen 支持分段输入，需要已配置本地模型。切换后重启服务生效。",
            "登录时启动": "登录 macOS 后自动启动遥声，由系统登录项管理。",
        ]
        stack.toolTip = descriptions[title]
        control.toolTip = descriptions[title]
        label.toolTip = descriptions[title]
        stack.heightAnchor.constraint(greaterThanOrEqualToConstant: 30).isActive = true
        stack.spacing = 8
        spacer.widthAnchor.constraint(greaterThanOrEqualToConstant: 4).isActive = true
        return stack
    }
    private func toggle(_ title: String, on: Bool, tag: Int) -> NSView {
        let control = RefinedSwitch()
        control.state = on ? .on : .off
        control.tag = tag
        control.target = self
        control.action = #selector(change(_:))
        control.setAccessibilityLabel(title)
        return row(title, control: control)
    }
    private func choice(_ title: String, labels: [String], selected: Int, tag: Int) -> NSView {
        let control = RefinedSegments(
            labels: labels, trackingMode: .selectOne, target: self, action: #selector(change(_:)))
        control.selectedSegment = selected
        control.tag = tag
        control.font = NSFont(name: "PingFangSC-Regular", size: 12)
        control.setAccessibilityLabel(title)
        if tag == 20 {
            transcriptionControl = control
            control.isEnabled = Configuration().speechEngine == "qwen"
            control.toolTip = "逐句输入仅支持 Qwen；Whisper 在松开后整段识别"
        }
        return row(title, control: control)
    }
    @objc private func change(_ sender: NSControl) {
        do {
            let store = AppPreferencesStore()
            let snapshot = store.load()
            if case .unsupportedVersion = snapshot.state {
                throw AppPreferencesError.unsupportedVersion(snapshot.preferences.schemaVersion)
            }
            var pref = snapshot.preferences
            var input = HomeRuntimeOptions.load()
            let on = (sender as? NSButton)?.state == .on
            let selected = (sender as? NSSegmentedControl)?.selectedSegment ?? 0
            switch sender.tag {
            case 20: input.streaming = selected == 1
            case 21: pref.submissionMode = on ? .codex : .transcriptionOnly
            case 22: input.automaticSend = on
            case 23: pref.voiceConnectionMode = selected == 0 ? .alwaysReady : .smartSleep
            case 24:
                pref.controlMode = selected == 0 ? .pointer : .directional
            case 25: pref.buttonControlEnabled = on
            case 26:
                input.showGuide = on;
                sceneView?.scene?.rootNode.childNode(withName: "button-guide", recursively: true)?.isHidden = !on
            case 27: try LoginItemController().setEnabled(on)
            case 29, 30:
                if sender.tag == 29 {
                    UserDefaults.standard.set(["system", "light", "dark"][selected], forKey: "RemoteVoice.theme")
                } else {
                    UserDefaults.standard.set(selected == 1 ? "en" : "zh", forKey: "RemoteVoice.language")
                }
                window?.appearance = InterfaceStyle.appearance
                window?.contentView = RemoteHomeView(
                    frame: bounds, running: RemoteDeviceStatus.runtimeActive, open: open)
                return
            case 28:
                input.speechEngine = selected == 0 ? "whisper" : "qwen"
                transcriptionControl?.isEnabled = selected == 1
                transcriptionControl?.selectedSegment = selected == 1 && input.streaming ? 1 : 0
            default: break
            }
            try store.save(pref)
            try input.save()
            MiAoRuntimeNotifications.postButtonConfigurationChanged()
            MiAoRuntimeNotifications.postVoiceConnectionModeChanged()
        } catch {
            let alert = NSAlert()
            alert.messageText = "设置未生效"
            alert.informativeText = error.localizedDescription
            alert.runModal()
            window?.contentView = RemoteHomeView(frame: bounds, running: RemoteDeviceStatus.runtimeActive, open: open)
        }
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            statusTimer?.invalidate(); statusTimer = nil; deviceDiscovery.stop(); batteryMonitor.stop();
            DistributedNotificationCenter.default().removeObserver(self)
        }
    }
    private func populateDevices(_ devices: [RemoteDeviceRecord]) {
        let store = AppPreferencesStore()
        let snapshot = store.load()
        let selected = snapshot.preferences.preferredPeripheralIdentifier
        if let selected, snapshot.preferences.preferredPeripheralName == nil,
            let name = devices.first(where: { $0.identifier == selected })?.name ?? HIDConnectionStatus.connectedName()
        {
            var preferences = snapshot.preferences
            preferences.preferredPeripheralName = name
            try? store.save(preferences)
        }
        devicePicker.removeAllItems()
        devicePicker.addItem(withTitle: InterfaceStyle.text("自动选择遥控器"))
        devicePicker.lastItem?.representedObject = "automatic"
        for device in devices {
            devicePicker.addItem(withTitle: device.name)
            devicePicker.lastItem?.representedObject = device.identifier.uuidString
        }
        if let selected, !devices.contains(where: { $0.identifier == selected }) {
            devicePicker.addItem(
                withTitle: AppPreferencesStore().load().preferences.preferredPeripheralName
                    ?? HIDConnectionStatus.connectedName() ?? "已保存的遥控器")
            devicePicker.lastItem?.representedObject = selected.uuidString
        }
        if let item = devicePicker.itemArray.first(where: { $0.representedObject as? String == selected?.uuidString }) {
            devicePicker.select(item)
        }
    }
    @objc private func scanDevices() {
        guard let window else { return }
        let sheet = DeviceScanSheet()
        scanSheet = sheet
        sheet.show(on: window) { [weak self] device in
            self?.devicePicker.removeAllItems()
            self?.devicePicker.addItem(withTitle: device.name)
            self?.devicePicker.lastItem?.representedObject = device.identifier.uuidString
            self?.selectDevice()
        }
    }
    @objc private func selectDevice() {
        do {
            let store = AppPreferencesStore()
            let snapshot = store.load()
            guard case .unsupportedVersion = snapshot.state else {
                var pref = snapshot.preferences
                pref.preferredPeripheralIdentifier = UUID(
                    uuidString: devicePicker.selectedItem?.representedObject as? String ?? "")
                batteryMonitor.synchronize(preferred: pref.preferredPeripheralIdentifier)
                pref.preferredPeripheralName =
                    pref.preferredPeripheralIdentifier == nil ? nil : devicePicker.selectedItem?.title
                try store.save(pref)
                return
            }
            throw AppPreferencesError.unsupportedVersion(snapshot.preferences.schemaVersion)
        } catch {
            let alert = NSAlert(); alert.messageText = "遥控器选择未保存"; alert.informativeText = error.localizedDescription;
            alert.runModal()
        }
    }
    @objc private func connectionGuide() { open(1) }
    private func zoomButton(_ symbol: String, tag: Int) -> NSButton {
        let button = NSButton(
            image: NSImage(systemSymbolName: symbol, accessibilityDescription: tag > 0 ? "放大" : "缩小")!, target: self,
            action: #selector(zoom(_:)))
        button.title = ""
        button.imagePosition = .imageOnly
        button.tag = tag
        button.setAccessibilityLabel(tag > 0 ? "放大" : "缩小")
        button.toolTip = tag > 0 ? "放大" : "缩小"
        button.bezelStyle = .rounded
        button.widthAnchor.constraint(equalToConstant: 44).isActive = true
        button.heightAnchor.constraint(equalToConstant: 32).isActive = true
        return button
    }
    @objc private func zoom(_ sender: NSButton) {
        guard let camera = sceneView?.pointOfView?.camera else { return }
        camera.orthographicScale = min(7, max(4.1, camera.orthographicScale - Double(sender.tag) * 0.4))
    }
    private func editMapping(_ button: RemoteButton) {
        let alert = NSAlert()
        alert.messageText = button.displayName
        guard button.isUserEditable else {
            alert.informativeText = button == .voice ? "语音键保留为按住说话。" : "菜单键保留为系统原生右键。"
            alert.addButton(withTitle: "完成")
            alert.runModal()
            return
        }
        do {
            let store = ButtonPresetStore()
            let snapshot = store.load()
            guard case .unsupportedVersion = snapshot.state else {
                let preferencesStore = AppPreferencesStore()
                let preferenceSnapshot = preferencesStore.load()
                if case .unsupportedVersion(let version) = preferenceSnapshot.state {
                    throw AppPreferencesError.unsupportedVersion(version)
                }
                var preferences = preferenceSnapshot.preferences
                let current = try snapshot.catalog.preset(id: preferences.selectedPresetID)
                var options: [ButtonBinding] = []
                for action in ButtonAction.allCases {
                    let binding = ButtonBinding.action(action)
                    let candidate = try DirectButtonMapping.edited(current, button: button, binding: binding)
                    let others = snapshot.catalog.userPresets.filter { $0.id != candidate.id }
                    if (try? ButtonPresetCatalog(userPresets: others + [candidate]).validate()) != nil {
                        options.append(binding)
                    }
                }
                let existing = current.binding(for: button)
                if !options.contains(existing) { options.insert(existing, at: 0) }
                let picker = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 360, height: 30))
                picker.font = NSFont(name: "PingFangSC-Regular", size: 13)
                picker.addItems(withTitles: options.map(\.displayName))
                picker.selectItem(at: options.firstIndex(of: existing) ?? 0)
                alert.informativeText = "选择按键动作，保存后立即生效。"
                alert.accessoryView = picker
                alert.addButton(withTitle: "保存")
                alert.addButton(withTitle: "取消")
                guard alert.runModal() == .alertFirstButtonReturn else { return }
                let candidate = try DirectButtonMapping.edited(
                    current, button: button, binding: options[picker.indexOfSelectedItem])
                let updated = ButtonPresetCatalog(
                    userPresets: snapshot.catalog.userPresets.filter { $0.id != candidate.id } + [candidate])
                try store.save(updated)
                preferences.selectedPresetID = candidate.id
                try preferencesStore.save(preferences)
                MiAoRuntimeNotifications.postButtonConfigurationChanged()
                if let view = sceneView {
                    let angles = view.scene?.rootNode.childNode(withName: "remote", recursively: false)?.eulerAngles
                    let scale = view.pointOfView?.camera?.orthographicScale
                    let scene = Self.remoteScene()
                    scene.rootNode.childNode(withName: "remote", recursively: false)?.eulerAngles =
                        angles ?? SCNVector3(0, -0.18, 0)
                    scene.rootNode.childNode(withName: "button-guide", recursively: true)?.isHidden =
                        !HomeRuntimeOptions.load().showGuide
                    view.scene = scene
                    view.pointOfView = scene.rootNode.childNodes.first { $0.camera != nil }
                    if let scale { view.pointOfView?.camera?.orthographicScale = scale }
                }
                return
            }
            throw BridgeError.configuration("按键配置来自更新版本，无法修改")
        } catch {
            alert.informativeText = error.localizedDescription
            alert.addButton(withTitle: "关闭")
            alert.runModal()
        }
    }
    private static func remoteScene() -> SCNScene {
        let scene = SCNScene()
        scene.background.contents = InterfaceStyle.background
        let remote = SCNNode()
        remote.name = "remote"
        remote.eulerAngles = SCNVector3(0, -0.18, 0)
        scene.rootNode.addChildNode(remote)
        scene.lightingEnvironment.contents = RefinedRemoteMaterial.studio()
        scene.lightingEnvironment.intensity = 0.7
        let silver = SCNMaterial()
        silver.diffuse.contents = NSColor(white: 0.64, alpha: 1)
        silver.lightingModel = .physicallyBased
        silver.metalness.contents = 0.85
        silver.roughness.contents = RefinedRemoteMaterial.brushedRoughness()
        let black = SCNMaterial()
        black.diffuse.contents = NSColor(white: 0.045, alpha: 1)
        black.lightingModel = .blinn
        black.specular.contents = NSColor(white: 0.16, alpha: 1)
        black.shininess = 0.22
        black.roughness.contents = 0.56
        @discardableResult
        func add(_ geometry: SCNGeometry, x: Float = 0, y: Float = 0, z: Float = 0, material: SCNMaterial) -> SCNNode {
            geometry.materials = [material]
            let node = SCNNode(geometry: geometry)
            node.position = SCNVector3(x, y, z)
            remote.addChildNode(node)
            return node
        }
        add(SCNBox(width: 1.42, height: 6.4, length: 0.28, chamferRadius: 0.14), material: silver).name = "body"
        func symbol(_ name: String, x: Float, y: Float, red: Bool = false, text: String? = nil) {
            let size = NSSize(width: 128, height: 128)
            let texture = NSImage(size: size)
            texture.lockFocus()
            let color = red ? NSColor.systemOrange : NSColor(white: 0.8, alpha: 1)
            if let text {
                let value = NSAttributedString(
                    string: text,
                    attributes: [.font: NSFont(name: "PingFangSC-Medium", size: 65)!, .foregroundColor: color])
                value.draw(at: NSPoint(x: (128 - value.size().width) / 2, y: (128 - value.size().height) / 2))
            } else if let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: 64, weight: .regular))
            {
                image.draw(in: NSRect(x: 26, y: 26, width: 76, height: 76))
                color.setFill()
                NSRect(x: 0, y: 0, width: 128, height: 128).fill(using: .sourceAtop)
            }
            texture.unlockFocus()
            let material = SCNMaterial()
            material.diffuse.contents = texture
            material.lightingModel = .constant
            material.isDoubleSided = true
            add(SCNPlane(width: 0.18, height: 0.18), x: x, y: y, z: 0.232, material: material)
        }
        func key(_ name: String, x: Float, y: Float, red: Bool = false, text: String? = nil) {
            let node = add(
                RefinedRemoteMaterial.button(radius: 0.215, height: 0.065), x: x, y: y, z: 0.1375, material: black)
            let ids = [
                "power": "power", "mic": "voice", "chevron.left": "back", "house": "home", "line.3.horizontal": "menu",
                "tv": "tv",
            ]
            node.name = ids[name]
            symbol(name, x: x, y: y, red: red, text: text)
        }
        key("power", x: -0.35, y: 2.72, red: true)
        key("mic", x: 0.35, y: 2.72)
        let discNode = add(
            RefinedRemoteMaterial.button(radius: 0.59, height: 0.065), y: 1.72, z: 0.1375, material: black)
        discNode.name = "dpad"
        let centerMaterial = black.copy() as! SCNMaterial
        centerMaterial.diffuse.contents = NSColor(white: 0.055, alpha: 1)
        let centerNode = add(
            RefinedRemoteMaterial.button(radius: 0.29, height: 0.075), y: 1.72, z: 0.1425, material: centerMaterial)
        centerNode.name = "center"
        for (name, x, y) in [
            ("chevron.up", Float(0), Float(2.18)), ("chevron.down", 0, 1.26), ("chevron.left", -0.46, 1.72),
            ("chevron.right", 0.46, 1.72),
        ] {
            symbol(name, x: x, y: y)
        }
        key("chevron.left", x: -0.35, y: 0.75)
        key("house", x: -0.35, y: 0.20)
        key("line.3.horizontal", x: -0.35, y: -0.35)
        add(
            SCNBox(width: 0.43, height: 0.57, length: 0.065, chamferRadius: 0), x: 0.35, y: 0.475, z: 0.17,
            material: black
        ).name = "volume"
        for y: Float in [0.19, 0.76] {
            let cap = SCNCylinder(radius: 0.215, height: 0.065)
            cap.radialSegmentCount = 96
            let node = add(cap, x: 0.35, y: y, z: 0.17, material: black)
            node.name = "volume"
            node.eulerAngles.x = .pi / 2
        }
        symbol("plus", x: 0.35, y: 0.75)
        symbol("minus", x: 0.35, y: 0.20)
        key("tv", x: 0.35, y: -0.35)
        let light = SCNNode()
        light.light = SCNLight()
        light.light?.type = .omni
        light.light?.intensity = 650
        light.light?.castsShadow = true
        light.light?.shadowRadius = 8
        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 140
        scene.rootNode.addChildNode(ambient)
        let fill = SCNNode()
        fill.light = SCNLight()
        fill.light?.type = .omni
        fill.light?.intensity = 260
        fill.position = SCNVector3(4, 1, 5)
        scene.rootNode.addChildNode(fill)
        light.position = SCNVector3(-4, 6, 8)
        scene.rootNode.addChildNode(light)
        let camera = SCNNode()
        camera.camera = SCNCamera()
        camera.camera?.usesOrthographicProjection = true
        camera.camera?.orthographicScale = 4.8
        camera.camera?.automaticallyAdjustsZRange = true
        camera.camera?.screenSpaceAmbientOcclusionIntensity = 0.55
        camera.camera?.screenSpaceAmbientOcclusionRadius = 0.12
        camera.position = SCNVector3(0, 0, 12)
        scene.rootNode.addChildNode(camera)
        return scene
    }
}

private final class RemoteSceneView: SCNView {
    var onButtonClick: ((RemoteButton) -> Void)?
    private var downPoint = NSPoint.zero
    private var moved = false
    override func mouseDown(with event: NSEvent) {
        downPoint = convert(event.locationInWindow, from: nil)
        moved = false
        clearHover()
        super.mouseDown(with: event)
    }
    override func mouseDragged(with event: NSEvent) {
        clearHover()
        let point = convert(event.locationInWindow, from: nil)
        if hypot(point.x - downPoint.x, point.y - downPoint.y) > 5 { moved = true }
        super.mouseDragged(with: event)
    }
    private var area: NSTrackingArea?
    private weak var highlighted: SCNNode?
    private var originalMaterials: [SCNMaterial] = []
    private let hint = RemoteHoverCard()
    private var describedButton: RemoteButton?
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area { removeTrackingArea(area) }
        let tracking = NSTrackingArea(
            rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self
        )
        addTrackingArea(tracking)
        area = tracking
        if hint.superview == nil {
            hint.isHidden = true
            addSubview(hint)
        }
    }
    private func clearHover() {
        highlighted?.geometry?.materials = originalMaterials
        highlighted = nil
        originalMaterials = []
        hint.isHidden = true
        describedButton = nil
        NSCursor.arrow.set()
    }
    override func mouseExited(with event: NSEvent) { clearHover() }
    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let (button, node) = buttonHit(at: point) else { clearHover(); return }
        if highlighted !== node {
            clearHover()
            highlighted = node
            originalMaterials = node.geometry?.materials ?? []
            node.geometry?.materials = originalMaterials.map {
                let copy = $0.copy() as! SCNMaterial
                copy.emission.contents = NSColor(white: 0.30, alpha: 1)
                return copy
            }
        }
        if describedButton != button {
            let preferences = AppPreferencesStore().load().preferences
            let preset = (try? ButtonPresetStore().load().catalog.preset(id: preferences.selectedPresetID)) ?? .pointer
            hint.configure(button: button, action: preset.binding(for: button).displayName)
            describedButton = button
        }
        let anchor = projectPoint(node.presentation.worldPosition)
        let width = min(CGFloat(244), bounds.width - 24)
        let remote = scene?.rootNode.childNode(withName: "remote", recursively: false)
        let rightEdge = remote.map { projectPoint($0.presentation.convertPosition(SCNVector3(0.8, 0, 0), to: nil)) }
        let leftEdge = remote.map { projectPoint($0.presentation.convertPosition(SCNVector3(-0.8, 0, 0), to: nil)) }
        let rightX = max(CGFloat(anchor.x) + 24, CGFloat(rightEdge?.x ?? anchor.x) + 16)
        let x = rightX + width < bounds.width - 12 ? rightX : CGFloat(leftEdge?.x ?? anchor.x) - width - 16
        hint.frame = NSRect(
            x: min(max(12, x), bounds.width - width - 12), y: min(max(12, CGFloat(anchor.y) + 20), bounds.height - 104),
            width: width, height: 92)
        hint.isHidden = false
        NSCursor.pointingHand.set()
    }
    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        guard !moved else { mouseMoved(with: event); return }
        let point = convert(event.locationInWindow, from: nil)
        if let (button, _) = buttonHit(at: point) { clearHover(); onButtonClick?(button) }
    }
    private func buttonHit(at point: NSPoint) -> (RemoteButton, SCNNode)? {
        for hit in hitTest(point, options: nil) {
            guard let name = hit.node.name else { continue }
            if name == "body" { return nil }
            if name == "dpad" || name == "volume", let parent = hit.node.parent {
                let local = parent.convertPosition(hit.worldCoordinates, from: nil)
                if name == "volume" { return (local.y >= 0.475 ? .volumeUp : .volumeDown, hit.node) }
                let dy = local.y - 1.72
                return (
                    abs(local.x) > abs(dy) ? (local.x > 0 ? .dpadRight : .dpadLeft) : (dy > 0 ? .dpadUp : .dpadDown),
                    hit.node
                )
            }
            if let button = RemoteButton(rawValue: name) { return (button, hit.node) }
        }
        return nil
    }

    override func scrollWheel(with event: NSEvent) {
        guard let camera = pointOfView?.camera else { return }
        camera.orthographicScale = min(7, max(4.1, camera.orthographicScale + Double(event.scrollingDeltaY) * 0.015))
    }
    override func layout() {
        super.layout()
        if let camera = pointOfView?.camera, bounds.height > 0 {
            camera.orthographicScale = max(
                camera.orthographicScale, 4.1, 1.6 / max(0.1, Double(bounds.width / bounds.height)))
        }
    }
}

private final class BatteryStatusBadge: NSView {
    var onRefresh: (() -> Void)?
    override func mouseDown(with event: NSEvent) { onRefresh?() }
    override func accessibilityPerformPress() -> Bool { onRefresh?(); return true }

    var level: Int? { didSet { needsDisplay = true } }
    override var intrinsicContentSize: NSSize { NSSize(width: 43, height: 22) }
    override func draw(_ dirtyRect: NSRect) {
        let valid = level.flatMap { (0...100).contains($0) ? $0 : nil }
        let color: NSColor =
            valid.map { $0 <= 20 ? .systemRed : $0 <= 50 ? .systemYellow : .systemGreen } ?? .secondaryLabelColor
        NSColor.secondaryLabelColor.withAlphaComponent(0.75).setStroke()
        let body = NSBezierPath(roundedRect: NSRect(x: 1, y: 3, width: 36, height: 16), xRadius: 3, yRadius: 3)
        body.lineWidth = 1
        body.stroke()
        NSColor.secondaryLabelColor.withAlphaComponent(0.75).setFill()
        NSBezierPath(roundedRect: NSRect(x: 38, y: 8, width: 3, height: 6), xRadius: 1, yRadius: 1).fill()
        if let valid, valid > 0 {
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(roundedRect: NSRect(x: 3, y: 5, width: 32, height: 12), xRadius: 2, yRadius: 2).addClip()
            color.withAlphaComponent(0.75).setFill()
            NSRect(x: 3, y: 5, width: 32 * CGFloat(valid) / 100, height: 12).fill()
            NSGraphicsContext.restoreGraphicsState()
        }
        let text = valid.map { "\($0)%" } ?? "?"
        let value = NSAttributedString(
            string: text,
            attributes: [
                .font: NSFont(name: "PingFangSC-Medium", size: 10)!,
                .foregroundColor: (valid.map { $0 > 0 } == true ? NSColor.black : InterfaceStyle.textColor)
                    .withAlphaComponent(0.75),
            ])
        value.draw(at: NSPoint(x: 19 - value.size().width / 2, y: 11 - value.size().height / 2))
        setAccessibilityLabel(valid.map { "电量 \($0)%" } ?? "电池状态未知")
    }
}

private final class TintedControlCard: NSView {
    private let glow = CAGradientLayer()
    init(title: String) {
        let tint: NSColor = title == "语音输入" ? .systemBlue : title == "遥控器" ? .systemGreen : .systemOrange
        super.init(frame: .zero)
        wantsLayer = true
        glow.type = .radial
        glow.colors = [
            tint.withAlphaComponent(InterfaceStyle.dark ? 0.18 : 0.14).cgColor, tint.withAlphaComponent(0).cgColor,
        ]
        glow.startPoint = CGPoint(x: 0.5, y: 0.5)
        glow.endPoint = CGPoint(x: 1, y: 1)
        layer?.addSublayer(glow)
    }
    required init?(coder: NSCoder) { nil }
    override func layout() {
        super.layout()
        glow.frame = CGRect(x: bounds.width - 250, y: bounds.height - 130, width: 300, height: 230)
        layer?.masksToBounds = true
    }
}

final class SurfaceActionButton: NSButton {
    var primary = false
    private var tracking: NSTrackingArea?
    private var hovered = false
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(
            rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(area)
        tracking = area
    }
    override func mouseEntered(with event: NSEvent) { hovered = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovered = false; needsDisplay = true }
    override func draw(_ dirtyRect: NSRect) {
        let color: NSColor =
            primary
            ? NSColor(
                white: !isEnabled ? (InterfaceStyle.dark ? 0.23 : 0.55) : isHighlighted ? 0.25 : hovered ? 0.18 : 0.12,
                alpha: 1)
            : NSColor(
                white: InterfaceStyle.dark
                    ? (isHighlighted ? 0.30 : hovered ? 0.25 : 0.21) : (isHighlighted ? 0.88 : hovered ? 0.92 : 0.96),
                alpha: 1)
        color.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8).fill()
        let text = NSAttributedString(
            string: title,
            attributes: [
                .font: NSFont(name: primary ? "PingFangSC-Medium" : "PingFangSC-Regular", size: 12)!,
                .foregroundColor: (primary ? NSColor.white : InterfaceStyle.textColor).withAlphaComponent(
                    isEnabled ? 1 : 0.4),
            ])
        text.draw(at: NSPoint(x: (bounds.width - text.size().width) / 2, y: (bounds.height - text.size().height) / 2))
        if window?.firstResponder === self {
            NSColor.keyboardFocusIndicatorColor.setStroke()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 8, yRadius: 8).stroke()
        }
    }
}

private final class RemoteHoverCard: NSView {
    private let title = NSTextField(labelWithString: "")
    private let action = NSTextField(wrappingLabelWithString: "")
    private let affordance = NSTextField(labelWithString: "")
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor(white: 0.12, alpha: 0.97).cgColor
        layer?.cornerRadius = 12
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.10).cgColor
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.15
        layer?.shadowRadius = 12
        layer?.shadowOffset = NSSize(width: 0, height: -4)
        title.font = NSFont(name: "PingFangSC-Medium", size: 13)
        title.textColor = .white
        action.font = NSFont(name: "PingFangSC-Regular", size: 11)
        action.textColor = NSColor(white: 0.84, alpha: 1)
        action.maximumNumberOfLines = 2
        affordance.font = NSFont(name: "PingFangSC-Regular", size: 10)
        affordance.textColor = NSColor(white: 0.61, alpha: 1)
        for label in [title, action, affordance] {
            label.translatesAutoresizingMaskIntoConstraints = false
            addSubview(label)
        }
        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            title.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            title.topAnchor.constraint(equalTo: topAnchor, constant: 11),
            action.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            action.trailingAnchor.constraint(equalTo: title.trailingAnchor),
            action.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 5),
            affordance.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            affordance.trailingAnchor.constraint(equalTo: title.trailingAnchor),
            affordance.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
        ])
    }
    required init?(coder: NSCoder) { nil }
    func configure(button: RemoteButton, action: String) {
        title.stringValue = InterfaceStyle.text(button.displayName)
        self.action.stringValue = InterfaceStyle.text(button == .menu ? "系统原生鼠标右键" : action)
        affordance.stringValue = InterfaceStyle.text(button.isUserEditable ? "点击编辑映射  ›" : "系统保留按键")
    }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
