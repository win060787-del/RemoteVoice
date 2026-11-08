import Foundation
import Testing

@testable import MiAo

@Test func batteryReadingAcceptsOnlyCurrentDevicesValidPercentage() {
    let selected = UUID(), other = UUID()
    var reading = BatteryReading()
    reading.select(selected)
    reading.receive(Data([85]), from: other)
    #expect(reading.percent == nil)
    reading.receive(Data([85]), from: selected)
    #expect(reading.percent == 85)
    for invalid in [Data(), Data([101]), Data([255]), Data([40, 0])] { reading.receive(invalid, from: selected) }
    #expect(reading.percent == 85)
    reading.receive(Data([0]), from: selected)
    #expect(reading.percent == 0)
    reading.receive(Data([100]), from: selected)
    #expect(reading.percent == 100)
}

@Test func batteryReadingClearsOnDisconnectAndDeviceChange() {
    let first = UUID(), second = UUID()
    var reading = BatteryReading()
    reading.select(first); reading.receive(Data([70]), from: first)
    reading.select(first)
    #expect(reading.percent == 70)
    reading.disconnect(second)
    #expect(reading.percent == 70)
    reading.disconnect(first)
    #expect(reading.percent == nil)
    reading.receive(Data([65]), from: first)
    reading.select(second)
    #expect(reading.percent == nil)
    reading.receive(Data([65]), from: first)
    #expect(reading.percent == nil)
    reading.receive(Data([30]), from: second)
    #expect(reading.percent == 30)
}
