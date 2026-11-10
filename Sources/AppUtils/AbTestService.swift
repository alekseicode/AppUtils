//
//  AbTestService.swift
//  AppUtils
//

import Foundation

/// One A/B test split on the device, 50/50 by install id. Needs no server: the only way to change
/// the ratio is a new app version.
///
/// The group is as stable as `installId`, so pass one that survives a reinstall (a keychain value,
/// for example). The hash and the storage key below are a contract with devices already in a test:
/// changing either moves them to another group or forgets their override.
public final class AbTestService {

    public enum Variant: String, CaseIterable {
        case a
        case b
    }

    /// Keeps the manual override between launches.
    private let defaults: UserDefaults
    /// The group this device falls into without an override.
    private let splitVariant: Variant
    /// Storage key of the manual override.
    private let forcedVariantKey: String

    /// - Parameter testName: Part of the hashed value and of the storage key, so tests do not share a
    ///   split or an override.
    public init(testName: String, installId: String, defaults: UserDefaults) {
        self.defaults = defaults
        forcedVariantKey = "AbTest.\(testName).forcedVariant"
        // FNV-1a, not `hashValue`: Swift seeds `hashValue` per process, so the group would change on
        // every launch. The top bit, not the bottom one: FNV-1a's lowest bit is only the parity of the
        // input's low bits, so a different test name would flip it or not for every device at once —
        // measured on 200 000 UUIDs, two test names then split devices identically, not independently.
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in "\(testName):\(installId)".utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        splitVariant = hash >> 63 == 0 ? .a : .b
    }

    /// Manual override for walkthroughs (a debug menu, for example). Callers should mark such devices
    /// in their events and exclude them from the results.
    public var forcedVariant: Variant? {
        get { defaults.string(forKey: forcedVariantKey).flatMap(Variant.init(rawValue:)) }
        set {
            if let newValue {
                defaults.set(newValue.rawValue, forKey: forcedVariantKey)
            } else {
                defaults.removeObject(forKey: forcedVariantKey)
            }
        }
    }

    public var variant: Variant { forcedVariant ?? splitVariant }

    public var isForced: Bool { forcedVariant != nil }
}
