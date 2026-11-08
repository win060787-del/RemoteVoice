// Copyright (c) 2026 FanXeon@Poemcoder with Codex
import Foundation
import Testing

@testable import MiAo

@Test func backButtonDeletesImmediatelyInPointerModeAndEscapesInDirectionalMode() {
    #expect(ButtonActionExecutor.resolvedAction(.backPointerDeleteOrEscape, mode: .pointer) == .deleteOrParagraph)
    #expect(ButtonActionExecutor.resolvedAction(.backPointerDeleteOrEscape, mode: .directional) == .keyboardEscape)
}

@Test func backButtonSeparatesEscapeFromRepeatingDelete() {
    var short = BackPressArbiter()
    #expect(short.poll(heldSeconds: 0.2) == nil)
    #expect(short.release(heldSeconds: 0.2) == .keyboardEscape)
    var long = BackPressArbiter()
    #expect(long.poll(heldSeconds: 0.5) == .keyboardDelete)
    #expect(long.poll(heldSeconds: 0.55) == nil)
    #expect(long.poll(heldSeconds: 0.61) == .keyboardDelete)
    #expect(long.release(heldSeconds: 0.7) == nil)
    #expect(BackPressArbiter().release(heldSeconds: 0.6) == .keyboardDelete)
}

@Test func centerButtonClicksInPointerModeAndConfirmsInDirectionalMode() {
    #expect(ButtonActionExecutor.resolvedAction(.centerPointerOrReturn, mode: .pointer) == .pointerLeftClick)
    #expect(ButtonActionExecutor.resolvedAction(.centerPointerOrReturn, mode: .directional) == .keyboardReturn)
}

@Test func audioBoostPreservesLoudSpeechWithoutFlatteningPeaks() {
    let audio: [Int16] = [0, 5_000, -10_000, 20_000, -20_000]
    let output = AudioPipeline.prepareForWhisper(audio, sampleRate: 16_000, gainDB: 20)
    #expect(output.count == audio.count)
    #expect(output[3] == Int16.max)
    #expect(output[4] == -Int16.max)
    #expect(abs(Int(output[1]) * 4 - Int(output[3])) <= 2)
    #expect(abs(Int(output[2]) * 2 + Int(output[3])) <= 2)
    #expect(AudioPipeline.prepareForWhisper([], sampleRate: 16_000, gainDB: 20).isEmpty)
    #expect(AudioPipeline.prepareForWhisper([Int16.min], sampleRate: 16_000, gainDB: 20) == [-Int16.max])
}

@Test func parsesV04Capabilities() {
    let data = Data([0x0B, 0x00, 0x04, 0x00, 0x01, 0x00, 0x86, 0x00, 0x14])
    let capabilities = ATVVProtocol.parseCapabilities(data)
    #expect(
        capabilities
            == ATVVCapabilities(
                version: .v04,
                codecs: 0x01,
                interactionModel: 0,
                frameSize: 134
            ))
}

@Test func parsesV10Capabilities() {
    let data = Data([0x0B, 0x01, 0x00, 0x03, 0x03, 0x00, 0x80])
    let capabilities = ATVVProtocol.parseCapabilities(data)
    #expect(
        capabilities
            == ATVVCapabilities(
                version: .v10,
                codecs: 0x03,
                interactionModel: 0x03,
                frameSize: 128
            ))
    #expect(capabilities?.selectedCodec == .adpcm16k)
}

@Test func parsesXiaomiFirmware2671SwappedV10Capabilities() {
    let data = Data([0x0B, 0x01, 0x00, 0x00, 0x03, 0x00, 0x78, 0x00, 0x00])
    let capabilities = ATVVProtocol.parseCapabilities(data)
    #expect(
        capabilities
            == ATVVCapabilities(
                version: .v10,
                codecs: 0x03,
                interactionModel: 0x00,
                frameSize: 120
            ))
    #expect(capabilities?.selectedCodec == .adpcm16k)
}

@Test func decodesSilentV04Frame() throws {
    let handler = ATVVProtocol()
    try handler.acceptCapabilities(
        ATVVCapabilities(
            version: .v04,
            codecs: 0x01,
            interactionModel: 0,
            frameSize: 134
        ))
    var frame = Data(repeating: 0, count: 134)
    frame[1] = 1
    let decoded = handler.decodeAudio(frame)
    #expect(decoded?.sequence == 1)
    #expect(decoded?.samples.count == 257)
    #expect(decoded?.samples.allSatisfy { abs(Int($0)) < 256 } == true)
}

@Test func resamplesEightToSixteenKilohertz() {
    let input: [Int16] = [0, 100, 200, 300]
    let output = AudioPipeline.linearResample(input, from: 8_000, to: 16_000)
    #expect(output.count == 8)
    #expect(output.first == 0)
}
