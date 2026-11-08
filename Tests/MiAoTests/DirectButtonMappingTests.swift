import Testing

@testable import MiAo

@Test func editing3DButtonCopiesBuiltInPresetWithoutOverwritingIt() throws {
    let edited = try DirectButtonMapping.edited(.pointer, button: .center, binding: .action(.keyboardReturn))
    #expect(!edited.isBuiltIn)
    #expect(edited.id.hasPrefix("user."))
    #expect(edited.binding(for: .center) == .action(.keyboardReturn))
    #expect(ButtonPreset.pointer.binding(for: .center) == .action(.centerPointerOrReturn))
    try ButtonPresetCatalog(userPresets: [edited]).validate()
    let another = try DirectButtonMapping.edited(.pointer, button: .center, binding: .action(.keyboardReturn))
    #expect(another.id != edited.id)
}

@Test func editing3DReservedButtonIsRejected() throws {
    for button in [RemoteButton.voice, .menu] {
        #expect(throws: (any Error).self) {
            try DirectButtonMapping.edited(.pointer, button: button, binding: .action(.keyboardReturn))
        }
    }
}
