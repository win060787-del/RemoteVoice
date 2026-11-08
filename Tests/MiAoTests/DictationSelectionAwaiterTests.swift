import Foundation
import Testing

@testable import MiAo

private final class SelectionSequence: @unchecked Sendable {
    private let lock = NSLock()
    private let values: [DictationSelectionSnapshot]
    private var index = 0
    init(_ values: [DictationSelectionSnapshot]) { self.values = values }
    func read() -> DictationSelectionSnapshot {
        lock.lock(); defer { lock.unlock() }
        let value = values[min(index, values.count - 1)]
        index += 1
        return value
    }
}

@Test func streamingWaitsForItsOwnAsynchronousSelectionChange() async throws {
    let previous = NSRange(location: 9, length: 0)
    let requested = NSRange(location: 3, length: 6)
    let sequence = SelectionSequence([
        .init(valueMatches: true, focusMatches: true, range: previous),
        .init(valueMatches: true, focusMatches: true, range: previous),
        .init(valueMatches: true, focusMatches: true, range: requested),
    ])
    let result: Result<Void, Error> = await withCheckedContinuation { continuation in
        DictationSelectionAwaiter.wait(
            requested: requested, previous: previous,
            read: { sequence.read() }, completion: { continuation.resume(returning: $0) })
    }
    try result.get()
}

@Test func streamingRefusesManualEditsFocusChangesAndUnrelatedSelections() async {
    let previous = NSRange(location: 9, length: 0)
    let requested = NSRange(location: 3, length: 6)
    let invalid: [DictationSelectionSnapshot] = [
        .init(valueMatches: false, focusMatches: true, range: requested),
        .init(valueMatches: true, focusMatches: false, range: requested),
        .init(valueMatches: true, focusMatches: true, range: NSRange(location: 1, length: 0)),
    ]
    for snapshot in invalid {
        let result: Result<Void, Error> = await withCheckedContinuation { continuation in
            DictationSelectionAwaiter.wait(
                requested: requested, previous: previous,
                read: { snapshot }, completion: { continuation.resume(returning: $0) })
        }
        #expect(throws: (any Error).self) { try result.get() }
    }
}

@Test func streamingDoesNotPasteWhenSelectionNeverTakesEffect() async {
    let previous = NSRange(location: 9, length: 0)
    let result: Result<Void, Error> = await withCheckedContinuation { continuation in
        DictationSelectionAwaiter.wait(
            requested: NSRange(location: 3, length: 6), previous: previous,
            attemptsRemaining: 2,
            read: { .init(valueMatches: true, focusMatches: true, range: previous) },
            completion: { continuation.resume(returning: $0) })
    }
    #expect(throws: (any Error).self) { try result.get() }
}
