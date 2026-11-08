import AppKit
import ApplicationServices
import Foundation

struct TextDeletionPlan: Equatable {
    let range: NSRange
    let expectedValue: String
    static func make(value: String, selection: NSRange, paragraph: Bool) throws -> Self? {
        let text = value as NSString
        guard selection.location >= 0, selection.length >= 0,
            selection.location <= text.length, selection.length <= text.length - selection.location
        else { throw BridgeError.configuration("删除选区无效") }
        let range: NSRange
        if paragraph {
            range = text.paragraphRange(for: NSRange(location: selection.location, length: 0))
        } else {
            let cursor = NSMaxRange(selection)
            guard cursor > 0 else { return nil }
            range = text.rangeOfComposedCharacterSequence(at: cursor - 1)
        }
        guard range.length > 0 else { return nil }
        return Self(range: range, expectedValue: text.replacingCharacters(in: range, with: ""))
    }
}

final class TextDeletionController: @unchecked Sendable {
    private struct Request: @unchecked Sendable {
        let element: AXUIElement
        let processID: pid_t
        let paragraph: Bool
        let completion: @Sendable (Result<Bool, Error>) -> Void
    }
    private var pending: [Request] = []
    private var busy = false

    func delete(paragraph: Bool, completion: @escaping @Sendable (Result<Bool, Error>) -> Void) {
        precondition(Thread.isMainThread)
        guard let app = NSWorkspace.shared.frontmostApplication else {
            completion(.failure(BridgeError.submission("请先点入需要编辑的文本框"))); return
        }
        let application = AXUIElementCreateApplication(app.processIdentifier)
        var focused: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(application, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
            let focused, CFGetTypeID(focused) == AXUIElementGetTypeID()
        else {
            completion(.failure(BridgeError.submission("无法确认文本框焦点，未删除文字"))); return
        }
        let element = focused as! AXUIElement
        guard let role = AccessibleText.string(kAXRoleAttribute, of: element),
            [kAXTextAreaRole as String, kAXTextFieldRole as String].contains(role)
        else {
            completion(.failure(BridgeError.submission("当前焦点不是文本框，未删除文字"))); return
        }
        pending.append(
            Request(element: element, processID: app.processIdentifier, paragraph: paragraph, completion: completion))
        drain()
    }

    private func drain() {
        guard !busy, !pending.isEmpty else { return }
        busy = true
        let request = pending.removeFirst()
        let finish: @Sendable (Result<Bool, Error>) -> Void = { result in
            request.completion(result)
            self.busy = false
            self.drain()
        }
        do {
            guard AccessibleText.focused(request.element, processID: request.processID),
                let value = AccessibleText.value(of: request.element),
                let selection = AccessibleText.selection(of: request.element)
            else { throw BridgeError.submission("文本框焦点已改变，未删除文字") }
            guard let plan = try TextDeletionPlan.make(value: value, selection: selection, paragraph: request.paragraph)
            else {
                finish(.success(false)); return
            }
            guard AccessibleText.select(plan.range, in: request.element) else {
                throw BridgeError.submission("无法选择要删除的文字")
            }
            DictationSelectionAwaiter.wait(
                requested: plan.range, previous: selection,
                read: {
                    .init(
                        valueMatches: AccessibleText.value(of: request.element) == value,
                        focusMatches: AccessibleText.focused(request.element, processID: request.processID),
                        range: AccessibleText.selection(of: request.element))
                },
                completion: { result in
                    switch result {
                    case .failure(let error): finish(.failure(error))
                    case .success:
                        let source = CGEventSource(stateID: .hidSystemState)
                        for down in [true, false] {
                            let event = CGEvent(keyboardEventSource: source, virtualKey: 51, keyDown: down)
                            event?.flags = []
                            event?.post(tap: .cghidEventTap)
                        }
                        self.verify(
                            request: request, expected: plan.expectedValue, previous: value, remaining: 6,
                            completion: finish)
                    }
                })
        } catch { finish(.failure(error)) }
    }

    private func verify(
        request: Request, expected: String, previous: String, remaining: Int,
        completion: @escaping @Sendable (Result<Bool, Error>) -> Void
    ) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) {
            let actual = AccessibleText.value(of: request.element)
            if actual == expected {
                completion(.success(true))
            } else if actual == previous, remaining > 1 {
                self.verify(
                    request: request, expected: expected, previous: previous, remaining: remaining - 1,
                    completion: completion)
            } else {
                completion(.failure(BridgeError.submission("输入框未确认删除结果，已停止操作")))
            }
        }
    }
}
