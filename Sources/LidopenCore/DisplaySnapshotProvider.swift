import AppKit
import CoreGraphics
import Foundation
import IOKit
import IOKit.graphics

public protocol DisplaySnapshotProviding: Sendable {
    func captureSnapshot() -> DisplaySnapshot
}

public struct SystemDisplaySnapshotProvider: DisplaySnapshotProviding {
    public init() {}

    public func captureSnapshot() -> DisplaySnapshot {
        let onlineDisplays = currentOnlineDisplays()
        let entries = onlineDisplays.map(makeDisplayInfo)
        return DisplaySnapshot(displays: entries)
    }

    private func currentOnlineDisplays() -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success else {
            return []
        }

        var displays = Array(repeating: CGDirectDisplayID(), count: Int(count))
        guard CGGetOnlineDisplayList(count, &displays, &count) == .success else {
            return []
        }
        return Array(displays.prefix(Int(count)))
    }

    private func makeDisplayInfo(for displayID: CGDirectDisplayID) -> DisplayInfo {
        let vendorID = CGDisplayVendorNumber(displayID)
        let productID = CGDisplayModelNumber(displayID)
        let serialNumber = CGDisplaySerialNumber(displayID)
        let isBuiltIn = CGDisplayIsBuiltin(displayID) != 0
        let registryMatch = matchingRegistryDisplay(
            displayID: displayID,
            vendorID: vendorID,
            productID: productID,
            serialNumber: serialNumber,
            isBuiltIn: isBuiltIn
        )
        let name = registryMatch?.name ?? fallbackName(
            vendorID: vendorID,
            productID: productID,
            isBuiltIn: isBuiltIn
        )
        let identity = MonitorIdentity(
            vendorID: vendorID,
            productID: productID,
            serialNumber: serialNumber == 0 ? nil : serialNumber,
            fallbackName: name
        )

        let modeDescription: String?
        if let mode = CGDisplayCopyDisplayMode(displayID) {
            modeDescription = "\(mode.pixelWidth)x\(mode.pixelHeight) @ \(Int(mode.refreshRate))Hz"
        } else {
            modeDescription = nil
        }

        return DisplayInfo(
            displayID: displayID,
            name: name,
            isBuiltIn: isBuiltIn,
            isDetectedInIORegistry: isBuiltIn || registryMatch != nil,
            isOnline: CGDisplayIsOnline(displayID) != 0,
            isActive: CGDisplayIsActive(displayID) != 0,
            isAsleep: CGDisplayIsAsleep(displayID) != 0,
            isMain: CGDisplayIsMain(displayID) != 0,
            isInMirrorSet: CGDisplayIsInMirrorSet(displayID) != 0,
            bounds: CGDisplayBounds(displayID),
            modeDescription: modeDescription,
            monitorIdentity: isBuiltIn ? nil : identity
        )
    }

    private func matchingRegistryDisplay(
        displayID: CGDirectDisplayID,
        vendorID: UInt32,
        productID: UInt32,
        serialNumber: UInt32,
        isBuiltIn: Bool
    ) -> RegistryDisplayMatch? {
        if let screenName = NSScreen.screens.first(where: { screen in
            (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == displayID
        })?.localizedName,
           !screenName.isEmpty {
            return RegistryDisplayMatch(name: screenName)
        }

        var iterator: io_iterator_t = 0
        guard let matching = IOServiceMatching("IODisplayConnect"),
              IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iterator) }

        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            guard let info = IODisplayCreateInfoDictionary(service, IOOptionBits(kIODisplayOnlyPreferredName)).takeRetainedValue() as? [String: Any] else {
                continue
            }

            let matchesVendor = (info[kDisplayVendorID as String] as? NSNumber)?.uint32Value == vendorID
            let matchesProduct = (info[kDisplayProductID as String] as? NSNumber)?.uint32Value == productID
            let storedSerial = (info[kDisplaySerialNumber as String] as? NSNumber)?.uint32Value ?? 0
            let matchesSerial = serialNumber == 0 || storedSerial == 0 || storedSerial == serialNumber

            guard matchesVendor, matchesProduct, matchesSerial else {
                continue
            }

            if let names = info[kDisplayProductName as String] as? [String: String],
               let first = names.values.first,
               !first.isEmpty {
                return RegistryDisplayMatch(name: first)
            }

            return RegistryDisplayMatch(
                name: fallbackName(vendorID: vendorID, productID: productID, isBuiltIn: isBuiltIn)
            )
        }

        return nil
    }

    private func fallbackName(
        vendorID: UInt32,
        productID: UInt32,
        isBuiltIn: Bool
    ) -> String {
        isBuiltIn ? "Built-in Display" : "Display \(vendorID):\(productID)"
    }
}

private struct RegistryDisplayMatch {
    let name: String
    }
