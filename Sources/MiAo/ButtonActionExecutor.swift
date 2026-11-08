// Copyright (c) 2026 FanXeon@Poemcoder with Codex
import AppKit
import ApplicationServices
import Foundation

enum RemoteControlMode: String, Codable, Equatable {
    case pointer
    case directional
}

enum HomeClickDecision: Equatable {
    case waitForSecondClick
    case pageUp
}

struct HomeClickArbiter {
    private(set) var isWaitingForSecondClick = false

    mutating func registerClick() -> HomeClickDecision {
        if isWaitingForSecondClick {
            isWaitingForSecondClick = false
            return .pageUp
        }
        isWaitingForSecondClick = true
        return .waitForSecondClick
    }

    mutating func commitSingleClick() -> Bool {
        guard isWaitingForSecondClick else { return false }
        isWaitingForSecondClick = false
        return true
    }

    mutating func reset() {
        isWaitingForSecondClick = false
    }
}

struct BackPressArbiter {
    private var lastDeleteAt: TimeInterval?
    mutating func poll(heldSeconds: TimeInterval) -> ButtonAction? {
        guard heldSeconds >= 0.5,
            lastDeleteAt.map({ heldSeconds - $0 >= 0.1 }) ?? true
        else { return nil }
        lastDeleteAt = heldSeconds
        return .keyboardDelete
    }
    func release(heldSeconds: TimeInterval) -> ButtonAction? {
        guard lastDeleteAt == nil else { return nil }
        return heldSeconds < 0.5 ? .keyboardEscape : .keyboardDelete
    }
}

enum DeletePressDecision: Equatable { case character, paragraph }
struct DeletePressArbiter {
    private var longPressFired = false
    mutating func poll(heldSeconds: TimeInterval) -> DeletePressDecision? {
        guard heldSeconds >= 0.65, !longPressFired else { return nil }
        longPressFired = true
        return .paragraph
    }
    func release(heldSeconds: TimeInterval) -> DeletePressDecision? {
        guard !longPressFired else { return nil }
        return heldSeconds < 0.65 ? .character : .paragraph
    }
}

final class ButtonActionExecutor: @unchecked Sendable {
    private(set) var preset: ButtonPreset
    private var catalog: ButtonPresetCatalog
    private let debug: Bool
    private let controlModeHandler: ((RemoteControlMode) -> Void)?
    private let presetChangeHandler: ((ButtonPreset) -> Void)?
    private let activityHandler: ((MiAoCommandActivity) -> Void)?
    private var timer: Timer?
    private var activeButton: RemoteButton?
    private var activeAction: ButtonAction?
    private var activeShortcut: KeyboardShortcutSpec?
    private var pressedAt: Date?
    private var lastTickAt = Date()
    private var lastScrollAt = Date.distantPast
    private var lastKeyRepeatAt = Date.distantPast
    private var homeClickArbiter = HomeClickArbiter()
    private var backPressArbiter = BackPressArbiter()
    private var deletePressArbiter = DeletePressArbiter()
    private let textDeletionController = TextDeletionController()
    private var pendingHomeSingle: DispatchWorkItem?
    private(set) var controlMode: RemoteControlMode

    static let homeDoubleClickInterval: TimeInterval = 0.35

    init(
        preset: ButtonPreset,
        catalog: ButtonPresetCatalog = .builtIn,
        debug: Bool = false,
        initialControlMode: RemoteControlMode = .pointer,
        controlModeHandler: ((RemoteControlMode) -> Void)? = nil,
        presetChangeHandler: ((ButtonPreset) -> Void)? = nil,
        activityHandler: ((MiAoCommandActivity) -> Void)? = nil
    ) {
        self.preset = preset
        self.catalog = catalog
        self.debug = debug
        self.controlMode = initialControlMode
        self.controlModeHandler = controlModeHandler
        self.presetChangeHandler = presetChangeHandler
        self.activityHandler = activityHandler
    }

    deinit {
        stop()
    }

    func start() {
        controlModeHandler?(controlMode)
        lastTickAt = Date()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) {
            [weak self] _ in self?.tick()
        }
    }

    func stop() {
        pendingHomeSingle?.cancel()
        pendingHomeSingle = nil
        homeClickArbiter.reset()
        if let activeAction, Self.isKeyboardAction(activeAction) {
            postKeyboard(action: activeAction, isDown: false)
        }
        if let activeShortcut {
            postKeyboardShortcut(activeShortcut, isDown: false)
        }
        timer?.invalidate()
        timer = nil
        clearActiveAction()
    }

    func buttonDown(_ button: RemoteButton) {
        switch preset.binding(for: button) {
        case .presetSwitch(let targetPresetID):
            switchPreset(to: targetPresetID)
            return
        case .keyboardShortcut(let shortcut):
            activeButton = button
            activeAction = nil
            activeShortcut = shortcut
            pressedAt = Date()
            postKeyboardShortcut(shortcut, isDown: true)
            activityHandler?(.keyboardShortcut(shortcut))
            return
        case .action(let baseAction):
            execute(action: baseAction, for: button)
        }
    }

    @discardableResult
    func replaceCatalog(
        _ catalog: ButtonPresetCatalog,
        selecting presetID: String
    ) throws -> ButtonPreset {
        try catalog.validate()
        let selected = (try? catalog.preset(id: presetID)) ?? .pointer
        self.catalog = catalog
        preset = selected
        presetChangeHandler?(selected)
        return selected
    }

    func adoptControlMode(_ mode: RemoteControlMode) {
        guard mode != controlMode else { return }
        clearActiveAction()
        controlMode = mode
        controlModeHandler?(mode)
    }

    private func execute(action baseAction: ButtonAction, for button: RemoteButton) {
        if baseAction == .modeTogglePointerDirectional {
            controlMode = controlMode == .pointer ? .directional : .pointer
            clearActiveAction()
            print(
                controlMode == .pointer
                    ? "控制模式：鼠标指针"
                    : "控制模式：方向键"
            )
            controlModeHandler?(controlMode)
            activityHandler?(.controlMode(controlMode))
            return
        }

        let action = Self.resolvedAction(baseAction, mode: controlMode)
        activeButton = button
        activeAction = action
        activeShortcut = nil
        pressedAt = Date()
        lastTickAt = pressedAt!
        switch action {
        case .pointerLeftClick:
            if let location = CGEvent(source: nil)?.location {
                let source = CGEventSource(stateID: .hidSystemState)
                for type in [CGEventType.leftMouseDown, .leftMouseUp] {
                    let event = CGEvent(
                        mouseEventSource: source, mouseType: type, mouseCursorPosition: location, mouseButton: .left)
                    event?.setIntegerValueField(.mouseEventClickState, value: 1)
                    event?.post(tap: .cghidEventTap)
                }
            }
        case .pointerMoveUp, .pointerMoveDown, .pointerMoveLeft, .pointerMoveRight:
            _ = CGDisplayShowCursor(CGMainDisplayID())
            movePointer(action: action, distance: 3, verify: debug)
        case .pointerScrollUp:
            postScroll(lines: 2)
            lastScrollAt = Date()
        case .pointerScrollDown:
            postScroll(lines: -2)
            lastScrollAt = Date()
        case .keyboardArrowUp, .keyboardArrowDown, .keyboardArrowLeft,
            .keyboardArrowRight, .keyboardReturn, .keyboardEscape, .keyboardDelete,
            .keyboardPageUp, .keyboardPageDown:
            if button == .back {
                print("返回键执行：\(action.displayName) · \(controlMode == .pointer ? "鼠标模式" : "方向键模式")")
                fflush(stdout)
            }
            postKeyboard(action: action, isDown: true)
            lastKeyRepeatAt = Date()
        case .homePageNavigation, .backEscapeOrDelete, .deleteOrParagraph:
            break
        case .codexFocus:
            let succeeded = CodexSubmitter().activateCodex()
            print(succeeded ? "已聚焦 Codex" : "Codex 未运行")
            activityHandler?(.codexFocus(succeeded: succeeded))
        case .codexLaunchOrFocus:
            let result = CodexSubmitter().launchOrActivateCodex()
            switch result {
            case .activated: print("已聚焦 Codex")
            case .launchRequested: print("正在启动 Codex")
            case .unavailable: print("未找到 Codex App，请先安装 Codex")
            }
            activityHandler?(.codexActivation(result))
        case .codexPreviousTask:
            let succeeded = CodexSubmitter().navigateTask(.previous)
            print(succeeded ? "Codex：上一个会话" : "Codex 未运行或找不到会话菜单，未切换")
            activityHandler?(.codexTask(.previous, succeeded: succeeded))
        case .codexNextTask:
            let succeeded = CodexSubmitter().navigateTask(.next)
            print(succeeded ? "Codex：下一个会话" : "Codex 未运行或找不到会话菜单，未切换")
            activityHandler?(.codexTask(.next, succeeded: succeeded))
        case .presetCycle:
            print("旧版循环切换已停用；请在按键配置中为 TV 选择目标配置")
            activityHandler?(.legacyPresetCycleUnavailable())
        case .voicePushToTalk, .modeTogglePointerDirectional, .centerPointerOrReturn, .backPointerDeleteOrEscape,
            .unmapped:
            break
        }
        if let activity = MiAoCommandActivity.executed(action: action) {
            activityHandler?(activity)
        }
    }

    func buttonUp(_ button: RemoteButton) {
        guard button == activeButton else { return }
        if activeAction == .deleteOrParagraph {
            let held = pressedAt.map { Date().timeIntervalSince($0) } ?? 0
            if let decision = deletePressArbiter.release(heldSeconds: held) { performDeletion(decision) }
            clearActiveAction()
            return
        }
        if activeAction == .backEscapeOrDelete {
            let held = pressedAt.map { Date().timeIntervalSince($0) } ?? 0
            if let action = backPressArbiter.release(heldSeconds: held) {
                postKeyboardStroke(action: action)
                if let activity = MiAoCommandActivity.executed(action: action) { activityHandler?(activity) }
            }
            clearActiveAction()
            return
        }
        if let activeShortcut {
            postKeyboardShortcut(activeShortcut, isDown: false)
            clearActiveAction()
            return
        }
        if activeAction == .homePageNavigation {
            handleHomeClick()
            clearActiveAction()
            return
        }
        if let activeAction, Self.isKeyboardAction(activeAction) {
            postKeyboard(action: activeAction, isDown: false)
        }
        clearActiveAction()
    }

    static func resolvedAction(
        _ baseAction: ButtonAction,
        mode: RemoteControlMode
    ) -> ButtonAction {
        if baseAction == .centerPointerOrReturn {
            return mode == .pointer ? .pointerLeftClick : .keyboardReturn
        }
        if baseAction == .backPointerDeleteOrEscape {
            return mode == .pointer ? .deleteOrParagraph : .keyboardEscape
        }
        guard mode == .directional else { return baseAction }
        switch baseAction {
        case .pointerMoveUp: return .keyboardArrowUp
        case .pointerMoveDown: return .keyboardArrowDown
        case .pointerMoveLeft: return .keyboardArrowLeft
        case .pointerMoveRight: return .keyboardArrowRight
        default: return baseAction
        }
    }

    private func tick(now: Date = Date()) {
        let delta = min(0.05, max(0, now.timeIntervalSince(lastTickAt)))
        lastTickAt = now
        guard let activeAction else { return }
        let held = pressedAt.map { now.timeIntervalSince($0) } ?? 0

        switch activeAction {
        case .deleteOrParagraph:
            if let decision = deletePressArbiter.poll(heldSeconds: held) { performDeletion(decision) }
        case .backEscapeOrDelete:
            if let action = backPressArbiter.poll(heldSeconds: held) {
                postKeyboardStroke(action: action)
                if let activity = MiAoCommandActivity.executed(action: action) { activityHandler?(activity) }
            }
        case .pointerMoveUp, .pointerMoveDown, .pointerMoveLeft, .pointerMoveRight:
            let distance = Self.pointerSpeed(heldSeconds: held) * delta
            movePointer(action: activeAction, distance: distance)
        case .pointerScrollUp, .pointerScrollDown:
            guard now.timeIntervalSince(lastScrollAt) >= 0.12 else { return }
            postScroll(lines: activeAction == .pointerScrollUp ? 2 : -2)
            lastScrollAt = now
        case .keyboardArrowUp, .keyboardArrowDown, .keyboardArrowLeft,
            .keyboardArrowRight:
            guard held >= 0.35, now.timeIntervalSince(lastKeyRepeatAt) >= 0.07 else {
                return
            }
            postKeyboard(action: activeAction, isDown: true)
            lastKeyRepeatAt = now
        default:
            break
        }
    }

    static func pointerSpeed(heldSeconds: TimeInterval) -> Double {
        let progress = min(1, max(0, heldSeconds) / 0.9)
        let eased = progress * progress * (3 - 2 * progress)
        return 100 + 750 * eased
    }

    private static func isKeyboardAction(_ action: ButtonAction) -> Bool {
        switch action {
        case .keyboardArrowUp, .keyboardArrowDown, .keyboardArrowLeft,
            .keyboardArrowRight, .keyboardReturn, .keyboardEscape, .keyboardDelete,
            .keyboardPageUp, .keyboardPageDown:
            return true
        default:
            return false
        }
    }

    private func clearActiveAction() {
        backPressArbiter = BackPressArbiter()
        deletePressArbiter = DeletePressArbiter()
        activeButton = nil
        activeAction = nil
        activeShortcut = nil
        pressedAt = nil
    }

    private func switchPreset(to targetPresetID: String) {
        guard let target = try? catalog.preset(id: targetPresetID) else {
            print("配置切换失败：找不到 \(targetPresetID)")
            activityHandler?(.presetUnavailable(id: targetPresetID))
            return
        }
        guard target.id != preset.id else {
            print("配置切换已忽略：目标与当前配置相同")
            activityHandler?(.presetAlreadySelected(name: target.name))
            return
        }
        preset = target
        presetChangeHandler?(target)
        print("已切换按键配置：\(target.name)")
        activityHandler?(.presetChanged(name: target.name))
    }

    private func handleHomeClick() {
        switch homeClickArbiter.registerClick() {
        case .waitForSecondClick:
            let workItem = DispatchWorkItem { [weak self] in
                guard let self, self.homeClickArbiter.commitSingleClick() else { return }
                self.pendingHomeSingle = nil
                self.postKeyboardStroke(action: .keyboardPageDown)
                print("HOME 单击：Page Down")
                self.activityHandler?(.homePage(up: false))
            }
            pendingHomeSingle = workItem
            DispatchQueue.main.asyncAfter(
                deadline: .now() + Self.homeDoubleClickInterval,
                execute: workItem
            )
        case .pageUp:
            pendingHomeSingle?.cancel()
            pendingHomeSingle = nil
            postKeyboardStroke(action: .keyboardPageUp)
            print("HOME 双击：Page Up")
            activityHandler?(.homePage(up: true))
        }
    }

    private func movePointer(
        action: ButtonAction,
        distance: Double,
        verify: Bool = false
    ) {
        guard let current = CGEvent(source: nil)?.location else { return }
        var target = current
        switch action {
        case .pointerMoveUp: target.y -= distance
        case .pointerMoveDown: target.y += distance
        case .pointerMoveLeft: target.x -= distance
        case .pointerMoveRight: target.x += distance
        default: return
        }
        let warpResult = CGWarpMouseCursorPosition(target)
        let source = CGEventSource(stateID: .hidSystemState)
        CGEvent(
            mouseEventSource: source,
            mouseType: .mouseMoved,
            mouseCursorPosition: target,
            mouseButton: .left
        )?.post(tap: .cghidEventTap)
        if verify {
            let expected = target
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                guard let actual = CGEvent(source: nil)?.location else { return }
                print(
                    "鼠标动作：warp=\(warpResult.rawValue)，请求 (\(Int(expected.x)), \(Int(expected.y)))，实际 (\(Int(actual.x)), \(Int(actual.y)))"
                )
            }
        }
    }

    private func postScroll(lines: Int32) {
        let source = CGEventSource(stateID: .hidSystemState)
        CGEvent(
            scrollWheelEvent2Source: source,
            units: .line,
            wheelCount: 1,
            wheel1: lines,
            wheel2: 0,
            wheel3: 0
        )?.post(tap: .cghidEventTap)
    }

    private func postKeyboard(action: ButtonAction, isDown: Bool) {
        guard let keyCode = Self.keyCode(for: action) else { return }
        let source = CGEventSource(stateID: .hidSystemState)
        guard
            let event = CGEvent(
                keyboardEventSource: source,
                virtualKey: keyCode,
                keyDown: isDown
            )
        else { return }
        event.flags = []
        event.post(tap: .cghidEventTap)
    }

    private func performDeletion(_ decision: DeletePressDecision) {
        let paragraph = decision == .paragraph
        textDeletionController.delete(paragraph: paragraph) { [weak self] result in
            switch result {
            case .success(let deleted):
                print(deleted ? (paragraph ? "返回键：已删除当前段落" : "返回键：已删除一个字") : "返回键：没有可删除文字")
                if deleted { self?.activityHandler?(.textDeletion(paragraph: paragraph, succeeded: true)) }
            case .failure(let error):
                print("返回键删除失败：\(error.localizedDescription)")
                self?.activityHandler?(.textDeletion(paragraph: paragraph, succeeded: false))
            }
            fflush(stdout)
        }
    }

    private func postKeyboardStroke(action: ButtonAction) {
        postKeyboard(action: action, isDown: true)
        postKeyboard(action: action, isDown: false)
    }

    private func postKeyboardShortcut(_ shortcut: KeyboardShortcutSpec, isDown: Bool) {
        let modifiers = ShortcutModifier.allCases.filter(shortcut.modifiers.contains)
        if isDown {
            for modifier in modifiers {
                postRawKeyboard(keyCode: modifier.keyCode, isDown: true)
            }
            postRawKeyboard(keyCode: shortcut.keyCode, isDown: true)
        } else {
            postRawKeyboard(keyCode: shortcut.keyCode, isDown: false)
            for modifier in modifiers.reversed() {
                postRawKeyboard(keyCode: modifier.keyCode, isDown: false)
            }
        }
    }

    private func postRawKeyboard(keyCode: CGKeyCode, isDown: Bool) {
        let source = CGEventSource(stateID: .hidSystemState)
        CGEvent(
            keyboardEventSource: source,
            virtualKey: keyCode,
            keyDown: isDown
        )?.post(tap: .cghidEventTap)
    }

    private static func keyCode(for action: ButtonAction) -> CGKeyCode? {
        switch action {
        case .keyboardArrowUp: return 126
        case .keyboardArrowDown: return 125
        case .keyboardArrowLeft: return 123
        case .keyboardArrowRight: return 124
        case .keyboardReturn: return 36
        case .keyboardEscape: return 53
        case .keyboardDelete: return 51
        case .keyboardPageUp: return 116
        case .keyboardPageDown: return 121
        default: return nil
        }
    }
}
