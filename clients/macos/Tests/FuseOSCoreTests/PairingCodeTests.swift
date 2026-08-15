import XCTest
@testable import FuseOSCore

/// These vectors are mirrored in the Android suite (`PairingCodeTest.kt`). A code typed
/// on one platform has to normalize the same way on the other, so drift fails a test here.
final class PairingCodeTests: XCTestCase {
    func testNormalizeUppercasesAndStripsFormatting() {
        XCTAssertEqual(PairingCode.normalize("a7x2-9qkm"), "A7X29QKM")
        XCTAssertEqual(PairingCode.normalize("A7X2 9QKM"), "A7X29QKM")
        XCTAssertEqual(PairingCode.normalize("a7x2–9qkm"), "A7X29QKM")
    }

    func testNormalizeCapsAtTheCodeLength() {
        XCTAssertEqual(PairingCode.normalize("A7X2-9QKM-EXTRA"), "A7X29QKM")
        XCTAssertEqual(PairingCode.normalize("ABCDEFGHIJ").count, PairingCode.length)
    }

    func testNormalizeKeepsPartialInput() {
        XCTAssertEqual(PairingCode.normalize(""), "")
        XCTAssertEqual(PairingCode.normalize("a7x"), "A7X")
    }

    func testGroupedInsertsSeparatorOnlyWithASecondHalf() {
        XCTAssertEqual(PairingCode.grouped("A7X29QKM"), "A7X2-9QKM")
        XCTAssertEqual(PairingCode.grouped("A7X2"), "A7X2")
        XCTAssertEqual(PairingCode.grouped("A7X29"), "A7X2-9")
    }

    func testURIRoundTripsThroughAScan() {
        XCTAssertEqual(PairingCode.uri("a7x29qkm"), "fuseos://pair?code=A7X2-9QKM")
        XCTAssertEqual(PairingCode.fromScan(PairingCode.uri("A7X29QKM")), "A7X29QKM")
    }

    func testFromScanAcceptsABareCodeWithOrWithoutSeparator() {
        XCTAssertEqual(PairingCode.fromScan("A7X2-9QKM"), "A7X29QKM")
        XCTAssertEqual(PairingCode.fromScan("A7X29QKM"), "A7X29QKM")
        XCTAssertEqual(PairingCode.fromScan("  a7x2-9qkm\n"), "A7X29QKM")
    }

    func testFromScanRejectsAnyQRThatIsNotACode() {
        // A camera sees whatever is in front of it — a URL must not become a code by
        // having its punctuation stripped.
        XCTAssertNil(PairingCode.fromScan("https://example.com"))
        XCTAssertNil(PairingCode.fromScan("A7X2"))
        XCTAssertNil(PairingCode.fromScan("A7X2-9QKM-EXTRA"))
        XCTAssertNil(PairingCode.fromScan("fuseos://pair?code=A7X2-9QKM-EXTRA"))
        XCTAssertNil(PairingCode.fromScan("WIFI:S=home;T=WPA;P=hunter2;;"))
        XCTAssertNil(PairingCode.fromScan(""))
    }
}
