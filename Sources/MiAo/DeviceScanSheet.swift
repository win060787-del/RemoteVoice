import AppKit

@MainActor
final class DeviceScanSheet: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    private let discovery = RemoteDeviceDiscoveryController()
    private var devices: [RemoteDeviceRecord] = []
    private let table = NSTableView()
    private let progress = NSProgressIndicator()
    private let status = NSTextField(labelWithString: "正在准备蓝牙扫描…")
    private let use = SurfaceActionButton(title: "使用设备", target: nil, action: nil)
    private let rescan = SurfaceActionButton(title: "重新扫描", target: nil, action: nil)
    private let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 560, height: 540), styleMask: [.titled], backing: .buffered, defer: false
    )
    private var completion: ((RemoteDeviceRecord) -> Void)?
    func show(on parent: NSWindow, completion: @escaping (RemoteDeviceRecord) -> Void) {
        self.completion = completion
        window.title = InterfaceStyle.text("附近蓝牙设备")
        window.appearance = InterfaceStyle.appearance
        window.isReleasedWhenClosed = false
        window.backgroundColor = InterfaceStyle.background
        let title = NSTextField(labelWithString: "选择遥控器")
        title.font = RemoteTypography.font(ofSize: 20, weight: .medium)
        let detail = NSTextField(wrappingLabelWithString: "显示附近广播中的 BLE 设备。仅兼容的语音遥控器可用于本应用；配对请使用系统蓝牙设置。")
        detail.font = RemoteTypography.font(ofSize: 12)
        detail.textColor = .secondaryLabelColor
        status.font = RemoteTypography.font(ofSize: 12)
        let column = NSTableColumn(identifier: .init("device"))
        column.title = InterfaceStyle.text("设备 · 兼容性 · 信号")
        column.width = 500
        table.addTableColumn(column)
        table.rowHeight = 44
        table.backgroundColor = InterfaceStyle.surface
        table.intercellSpacing = NSSize(width: 12, height: 4)
        table.dataSource = self
        table.delegate = self
        table.allowsEmptySelection = true
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder
        scroll.wantsLayer = true
        scroll.layer?.cornerRadius = 12
        scroll.layer?.masksToBounds = true
        scroll.backgroundColor = InterfaceStyle.surface
        scroll.heightAnchor.constraint(equalToConstant: 220).isActive = true
        let cancel = SurfaceActionButton(title: "取消", target: self, action: #selector(close))
        let bluetooth = SurfaceActionButton(title: "蓝牙设置…", target: self, action: #selector(openSettings))
        use.target = self; use.action = #selector(selectDevice); use.isEnabled = false
        rescan.target = self; rescan.action = #selector(scan)
        let buttons = NSStackView(views: [bluetooth, rescan, cancel, use])
        buttons.spacing = 8
        buttons.distribution = .fillEqually
        for button in [bluetooth, rescan, cancel, use] {
            button.isBordered = false
            button.heightAnchor.constraint(equalToConstant: 32).isActive = true
        }
        use.primary = true
        cancel.keyEquivalent = "\u{1b}"
        progress.style = .spinning
        progress.controlSize = .small
        progress.isDisplayedWhenStopped = false
        progress.widthAnchor.constraint(equalToConstant: 16).isActive = true
        progress.heightAnchor.constraint(equalToConstant: 16).isActive = true
        let scanStatus = NSStackView(views: [progress, status])
        scanStatus.spacing = 8
        let content = NSStackView(views: [title, detail, scroll, scanStatus, buttons])
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 16
        content.translatesAutoresizingMaskIntoConstraints = false
        window.contentView!.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 24),
            content.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -24),
            content.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 24),
            content.bottomAnchor.constraint(equalTo: window.contentView!.bottomAnchor, constant: -24),
        ])
        for view in [detail, scroll, scanStatus, buttons] {
            view.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
        }
        discovery.onUpdate = { [weak self] state, records in
            MainActor.assumeIsolated { self?.update(state, records) }
        }
        InterfaceStyle.apply(content)
        parent.beginSheet(window)
        scan()
    }
    @objc private func scan() {
        devices = []; table.reloadData(); use.isEnabled = false; rescan.isEnabled = false
        discovery.start(
            preferredIdentifier: AppPreferencesStore().load().preferences.preferredPeripheralIdentifier,
            includeAllDevices: true)
    }
    private func update(_ state: RemoteDeviceDiscoveryState, _ records: [RemoteDeviceRecord]) {
        let selected = devices.indices.contains(table.selectedRow) ? devices[table.selectedRow].identifier : nil
        devices = records
        table.reloadData()
        if let index = devices.firstIndex(where: { $0.identifier == selected }) {
            table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        }
        switch state {
        case .idle: status.stringValue = "尚未扫描"
        case .waitingForBluetooth: status.stringValue = "正在等待蓝牙状态或系统授权…"
        case .scanning: status.stringValue = "扫描中 · 发现 \(devices.count) 台设备"
        case .finished:
            status.stringValue = devices.isEmpty ? "未发现正在广播的 BLE 设备，请唤醒遥控器后重新扫描。" : "发现 \(devices.count) 台设备；请选择兼容遥控器。"
        case .unavailable(let reason): status.stringValue = reason + "，可点击蓝牙设置处理。"
        }
        if case .scanning = state {
            rescan.isEnabled = false
        } else if case .waitingForBluetooth = state {
            rescan.isEnabled = false
        } else {
            rescan.isEnabled = true
        }
        if rescan.isEnabled { progress.stopAnimation(nil) } else { progress.startAnimation(nil) }
        status.stringValue = InterfaceStyle.text(status.stringValue)
        updateSelection()
    }
    func numberOfRows(in tableView: NSTableView) -> Int { devices.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let device = devices[row]
        let signal = device.rssi == -127 ? InterfaceStyle.text("已连接") : "\(device.rssi) dBm"
        let text = NSTextField(
            labelWithString:
                "\(device.name)    ·    \(InterfaceStyle.text(device.isCompatible ? "兼容" : "不支持"))    ·    \(signal)")
        text.font = RemoteTypography.font(ofSize: 12)
        text.textColor = device.isCompatible ? .labelColor : .secondaryLabelColor
        return text
    }
    func tableViewSelectionDidChange(_ notification: Notification) { updateSelection() }
    private func updateSelection() {
        use.isEnabled = devices.indices.contains(table.selectedRow) && devices[table.selectedRow].isCompatible
    }
    @objc private func selectDevice() {
        guard use.isEnabled else { return }
        completion?(devices[table.selectedRow])
        close()
    }
    @objc private func openSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings")!)
    }
    @objc private func close() {
        progress.stopAnimation(nil)
        discovery.stop()
        window.sheetParent?.endSheet(window)
        window.orderOut(nil)
    }
}
