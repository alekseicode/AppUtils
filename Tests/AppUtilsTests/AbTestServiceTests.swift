import XCTest
// Not `@testable`: the apps see only the public surface, and a forgotten `public` should fail here.
import AppUtils

final class AbTestServiceTests: XCTestCase {

    private func makeDefaults() -> UserDefaults {
        let name = "AbTestServiceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func installIds(count: Int) -> [String] {
        // Deterministic, so a failure reproduces.
        (0..<count).map { index in
            var generator = index &* 2_654_435_761
            let parts = (0..<4).map { _ -> String in
                generator = generator &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                return String(UInt32(truncatingIfNeeded: generator >> 16), radix: 16)
            }
            return parts.joined(separator: "-")
        }
    }

    func testTheSameDeviceAlwaysLandsInTheSameGroup() {
        let first = AbTestService(testName: "t", installId: "device-1", defaults: makeDefaults())
        let second = AbTestService(testName: "t", installId: "device-1", defaults: makeDefaults())
        XCTAssertEqual(first.variant, second.variant)
    }

    func testDevicesSplitRoughlyInHalf() {
        let defaults = makeDefaults()
        let ids = installIds(count: 20_000)
        let inA = ids.filter { AbTestService(testName: "t", installId: $0, defaults: defaults).variant == .a }.count
        XCTAssertLessThan(abs(Double(inA) / Double(ids.count) - 0.5), 0.02)
    }

    /// The lowest bit of FNV-1a does not depend on the test name in any useful way: with it two
    /// tests divide devices identically or exactly inversely, and their effects cannot be separated.
    func testTwoTestsSplitDevicesIndependently() {
        let defaults = makeDefaults()
        let ids = installIds(count: 20_000)
        let same = ids.filter {
            AbTestService(testName: "first", installId: $0, defaults: defaults).variant
                == AbTestService(testName: "second", installId: $0, defaults: defaults).variant
        }.count
        XCTAssertLessThan(abs(Double(same) / Double(ids.count) - 0.5), 0.02)
    }

    func testForcingAVariantWinsAndIsReported() {
        let test = AbTestService(testName: "t", installId: "device-1", defaults: makeDefaults())
        XCTAssertFalse(test.isForced)
        for variant in AbTestService.Variant.allCases {
            test.forcedVariant = variant
            XCTAssertEqual(test.variant, variant)
            XCTAssertTrue(test.isForced)
        }
        test.forcedVariant = nil
        XCTAssertFalse(test.isForced)
    }

    func testAnOverrideBelongsToItsOwnTest() {
        let defaults = makeDefaults()
        let first = AbTestService(testName: "first", installId: "device-1", defaults: defaults)
        let second = AbTestService(testName: "second", installId: "device-1", defaults: defaults)
        first.forcedVariant = .a
        XCTAssertFalse(second.isForced)
    }

    /// Values computed outside Swift. A different hash, bit or input format moves devices already in
    /// a running test to the other group, which the statistical tests above would not notice.
    func testKnownDevicesKeepTheirGroups() {
        let expected: [(id: String, proSample: AbTestService.Variant, other: AbTestService.Variant)] = [
            ("CFCD2084-95D5-65EF-66E7-DFF9F98764DA", .b, .b),
            ("C4CA4238-A0B9-2382-0DCC-509A6F75849B", .a, .a),
            ("C81E728D-9D4C-2F63-6F06-7F89CC14862C", .a, .b),
            ("ECCBC87E-4B5C-E2FE-2830-8FD9F2A7BAF3", .a, .b),
            ("A87FF679-A2F3-E71D-9181-A67B7542122C", .b, .a),
            ("E4DA3B7F-BBCE-2345-D777-2B0674A318D5", .a, .a),
            ("1679091C-5A88-0FAF-6FB5-E6087EB1B2DC", .b, .b),
            ("8F14E45F-CEEA-167A-5A36-DEDD4BEA2543", .a, .a)
        ]
        let defaults = makeDefaults()
        for row in expected {
            XCTAssertEqual(AbTestService(testName: "pro_sample_entry", installId: row.id, defaults: defaults).variant, row.proSample, row.id)
            XCTAssertEqual(AbTestService(testName: "other_test", installId: row.id, defaults: defaults).variant, row.other, row.id)
        }
    }

    /// An override written by an earlier app version has to be found under the same key.
    func testTheOverrideStorageKeyAndValuesAreStable() {
        let defaults = makeDefaults()
        let test = AbTestService(testName: "pro_sample_entry", installId: "device-1", defaults: defaults)

        test.forcedVariant = .b
        XCTAssertEqual(defaults.string(forKey: "AbTest.pro_sample_entry.forcedVariant"), "b")

        defaults.set("a", forKey: "AbTest.pro_sample_entry.forcedVariant")
        XCTAssertEqual(test.forcedVariant, .a)

        test.forcedVariant = nil
        XCTAssertNil(defaults.object(forKey: "AbTest.pro_sample_entry.forcedVariant"))
    }
}
