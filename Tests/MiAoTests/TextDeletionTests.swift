import Foundation
import Testing

@testable import MiAo

@Test func emptyComposerHintIsNotTreatedAsExistingDraft() {
    let hint = "使用 ChatGPT Work"
    #expect(
        AccessibleText.normalizedValue(
            hint + "\n", title: hint, description: hint, placeholder: nil,
            selection: NSRange(location: 0, length: 0)) == "")
    #expect(
        AccessibleText.normalizedValue(
            "真正的草稿", title: hint, description: hint, placeholder: nil,
            selection: NSRange(location: 0, length: 0)) == "真正的草稿")
    #expect(
        AccessibleText.normalizedValue(
            hint, title: hint, description: hint, placeholder: nil,
            selection: NSRange(location: (hint as NSString).length, length: 0)) == hint)
}

@Test func singleDeleteRemovesOneComposedCharacterAndNeverWholeSelection() throws {
    let value = "甲👨‍👩‍👧‍👦乙"
    let emoji = (value as NSString).range(of: "👨‍👩‍👧‍👦")
    let plan = try #require(
        try TextDeletionPlan.make(
            value: value, selection: NSRange(location: NSMaxRange(emoji), length: 0), paragraph: false))
    #expect(plan.range == emoji)
    #expect(plan.expectedValue == "甲乙")
    let selected = try #require(
        try TextDeletionPlan.make(
            value: value, selection: NSRange(location: 0, length: (value as NSString).length), paragraph: false))
    #expect(selected.expectedValue == "甲👨‍👩‍👧‍👦")
}

@Test func paragraphDeletePreservesOtherParagraphs() throws {
    let value = "第一段\n第二段😀\n第三段"
    let cursor = (value as NSString).range(of: "二").location
    let plan = try #require(
        try TextDeletionPlan.make(value: value, selection: NSRange(location: cursor, length: 0), paragraph: true))
    #expect(plan.expectedValue == "第一段\n第三段")
    #expect(try TextDeletionPlan.make(value: "", selection: NSRange(location: 0, length: 0), paragraph: true) == nil)
    #expect(throws: (any Error).self) {
        try TextDeletionPlan.make(value: value, selection: NSRange(location: NSNotFound, length: 1), paragraph: false)
    }
}

@Test func onePhysicalPressProducesOneDeleteDecisionWithoutRepeating() {
    var short = DeletePressArbiter()
    #expect(short.poll(heldSeconds: 0.3) == nil)
    #expect(short.poll(heldSeconds: 0.64) == nil)
    #expect(short.release(heldSeconds: 0.64) == .character)
    var long = DeletePressArbiter()
    #expect(long.poll(heldSeconds: 0.65) == .paragraph)
    #expect(long.poll(heldSeconds: 0.9) == nil)
    #expect(long.poll(heldSeconds: 3) == nil)
    #expect(long.release(heldSeconds: 3) == nil)
    #expect(DeletePressArbiter().release(heldSeconds: 1) == .paragraph)
}
