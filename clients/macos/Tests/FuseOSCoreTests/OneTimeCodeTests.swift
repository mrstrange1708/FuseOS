import FuseOSCore
import XCTest

final class OneTimeCodeTests: XCTestCase {
    func testFindsTheCodeInCommonMessages() {
        XCTAssertEqual(OneTimeCode.find(in: "G-482913 is your Google verification code."), "482913")
        XCTAssertEqual(OneTimeCode.find(in: "Your OTP for login is 7788. Do not share it."), "7788")
        XCTAssertEqual(OneTimeCode.find(in: "Amazon: 334455 is your one-time password (OTP)."), "334455")
        XCTAssertEqual(OneTimeCode.find(in: "Use 123-456 to verify your account"), "123456")
    }

    func testPrefersTheCodeOverAnAmountOrAnAccount() {
        XCTAssertEqual(OneTimeCode.find(in: "₹4999 to be paid at Flipkart. OTP 552211, valid 10 min."), "552211")
        XCTAssertEqual(OneTimeCode.find(in: "Rs. 4500 for txn at Swiggy. Your OTP is 918273"), "918273")
    }

    func testLeavesOrdinaryNumbersAlone() {
        XCTAssertNil(OneTimeCode.find(in: "Your order 88231 has shipped and arrives Tuesday."))
        XCTAssertNil(OneTimeCode.find(in: "Rs. 4500 debited from A/c XX1234 on 29-09."))
        XCTAssertNil(OneTimeCode.find(in: "Meeting moved to 1430 tomorrow"))
        XCTAssertNil(OneTimeCode.find(in: "Your verification is complete."))
    }
}
