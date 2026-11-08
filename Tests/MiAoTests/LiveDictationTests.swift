import Foundation
import Testing

@testable import MiAo

@Test func dictationTargetsTheExplicitlyFocusedInputWithoutGuessingBetweenFields() {
    #expect(CodexEditorSelectionPolicy.index(candidateCount: 2, focusedIndices: [1]) == 1)
    #expect(CodexEditorSelectionPolicy.index(candidateCount: 2, focusedIndices: []) == nil)
    #expect(CodexEditorSelectionPolicy.index(candidateCount: 2, focusedIndices: [0, 1]) == nil)
    #expect(CodexEditorSelectionPolicy.index(candidateCount: 1, focusedIndices: []) == 0)
    #expect(CodexEditorSelectionPolicy.index(candidateCount: 0, focusedIndices: []) == nil)
    #expect(CodexEditorSelectionPolicy.index(candidateCount: 2, focusedIndices: [4]) == nil)
}

@Test func rollingDictationRevisesOnlyItsOwnTextAndPreservesEmojiAndSuffix() throws {
    let original = "草稿😀后缀"
    let selection = (original as NSString).range(of: "😀")
    let start = try DictationDraft(value: original, selection: selection)
    let first = try start.replacing(with: "今天", currentValue: original)
    #expect(first.expectedValue == "草稿今天后缀")
    let second = try first.replacing(with: "今天天气不错", currentValue: first.expectedValue)
    #expect(second.expectedValue == "草稿今天天气不错后缀")
    #expect(second.caret == NSRange(location: 8, length: 0))
    let corrected = try second.replacing(with: "今天开始检查。", currentValue: second.expectedValue)
    #expect(corrected.expectedValue == "草稿今天开始检查。后缀")
}

@Test func rollingDictationRejectsUserEditsAndInvalidSelection() throws {
    let draft = try DictationDraft(value: "原草稿", selection: NSRange(location: 3, length: 0))
    #expect(throws: (any Error).self) { try draft.replacing(with: "听写", currentValue: "手动改过的草稿") }
    #expect(throws: (any Error).self) { try DictationDraft(value: "草稿", selection: NSRange(location: 5, length: 0)) }
    #expect(throws: (any Error).self) { try DictationDraft(value: "草稿", selection: NSRange(location: -1, length: 0)) }
}
