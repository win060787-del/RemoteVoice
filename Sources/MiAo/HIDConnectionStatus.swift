import Foundation
import IOKit

/// Reads connection metadata only; does not open input monitoring or synthesize events.
enum HIDConnectionStatus {
    static func connectedName() -> String? {
        var iterator: io_iterator_t = 0
        guard
            IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOHIDDevice"), &iterator)
                == KERN_SUCCESS
        else { return nil }
        defer { IOObjectRelease(iterator) }
        let config = Configuration()
        var names = Set<String>()
        while true {
            let service = IOIteratorNext(iterator)
            guard service != 0 else { break }
            defer { IOObjectRelease(service) }
            func value(_ key: String) -> Any? {
                IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
            }
            guard (value("VendorID") as? NSNumber)?.intValue == config.hidVendorID,
                (value("ProductID") as? NSNumber)?.intValue == config.hidProductID,
                let name = value("Product") as? String, !name.isEmpty
            else { continue }
            names.insert(name)
        }
        return names.count == 1 ? names.first : nil
    }
}
