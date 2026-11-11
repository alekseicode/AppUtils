import XCTest
import AppUtils

final class OrderedJSONTests: XCTestCase {

    private func parse(_ text: String) throws -> OrderedJSON {
        try OrderedJSON(data: Data(text.utf8))
    }

    private func keys(_ json: OrderedJSON?) -> [String]? {
        guard case .object(let members) = json else { return nil }
        return members.map(\.key)
    }

    func testObjectKeepsDocumentOrder() throws {
        let json = try parse(#"{"Я":"1","b":"2","А":"3","a":{"z":1,"y":2}}"#)
        XCTAssertEqual(keys(json), ["Я", "b", "А", "a"])
        XCTAssertEqual(keys(json["a"]), ["z", "y"])
    }

    func testReadsLiteralsAndNesting() throws {
        let json = try parse(#" { "z" : [1, true, false, null, -2.5e3, "x"], "a" : {} } "#)
        XCTAssertEqual(keys(json), ["z", "a"])
        XCTAssertEqual(keys(json["a"]), [])
        guard case .array(let items) = json["z"] else {
            return XCTFail("expected an array")
        }
        XCTAssertEqual(items.count, 6)
        XCTAssertEqual(items[0].int, 1)
        guard case .bool(true) = items[1], case .bool(false) = items[2], case .null = items[3] else {
            return XCTFail("literals misread")
        }
        guard case .number(let number) = items[4] else {
            return XCTFail("expected a number")
        }
        XCTAssertEqual(number.doubleValue, -2500)
        XCTAssertEqual(items[5].string, "x")
    }

    func testStringEscapesFollowFoundation() throws {
        let json = try parse(#"{"k\"ey":"a\\b\n\u0416\ud83d\ude97"}"#)
        XCTAssertEqual(keys(json), ["k\"ey"])
        XCTAssertEqual(json["k\"ey"]?.string, "a\\b\nЖ🚗")
    }

    func testIntIsOnlyAWholeNumber() throws {
        XCTAssertEqual(try parse("200").int, 200)
        XCTAssertEqual(try parse("-7").int, -7)
        XCTAssertNil(try parse("200.5").int)
        XCTAssertNil(try parse("1e30").int)
        XCTAssertNil(try parse("-1e30").int)
        XCTAssertNil(try parse("1.9999999999999998").int)
        XCTAssertNil(try parse("200.00000000000003").int)
        XCTAssertNil(try parse(#""200""#).int)
        XCTAssertNil(try parse("true").int)
    }

    func testIntKeepsTheExactBoundsOfInt() throws {
        XCTAssertEqual(try parse(String(Int.max)).int, Int.max)
        XCTAssertEqual(try parse(String(Int.min)).int, Int.min)
        XCTAssertNil(try parse("9223372036854775808").int)
        XCTAssertNil(try parse("-9223372036854775809").int)
        XCTAssertNil(OrderedJSON.number(NSDecimalNumber(string: "-9223372036854775809")).int)
        XCTAssertNil(OrderedJSON.number(NSNumber(value: -Double.infinity)).int)
        XCTAssertNil(OrderedJSON.number(NSNumber(value: UInt64.max)).int)
    }

    func testSubscriptTakesTheFirstMemberAndIgnoresNonObjects() throws {
        XCTAssertEqual(try parse(#"{"a":"first","a":"second"}"#)["a"]?.string, "first")
        XCTAssertNil(try parse(#"{"a":"1"}"#)["b"])
        XCTAssertNil(try parse(#"["a"]"#)["a"])
    }

    func testRejectsAnythingButOneValue() {
        let bodies = ["", "   ", "<html></html>", #"{"a":1"#, #"{"a":1}}"#, #"{"a" 1}"#, #"{a:1}"#,
                      #"[1,]"#, #"[,1]"#, #"{"a":1,}"#, #"{"a":}"#, #""open"#, #""abc\"#, "tru", "1 2",
                      #"{"a":1} x"#]
        for body in bodies {
            XCTAssertThrowsError(try parse(body), body) { error in
                XCTAssertTrue(error is OrderedJSON.SyntaxError, body)
            }
        }
    }

    func testRejectsAByteOrderMarkInsideTheDocument() {
        for body in ["{\"x\":\u{FEFF}1}", "[1,\u{FEFF}true]", "\u{FEFF}null"] {
            XCTAssertThrowsError(try parse(body), body)
        }
    }

    func testErrorPointsAtTheOffendingToken() {
        XCTAssertThrowsError(try parse(#"{"a": tru}"#)) { error in
            XCTAssertEqual((error as? OrderedJSON.SyntaxError)?.offset, 6)
        }
    }

    func testDeepNestingThrowsInsteadOfOverflowingTheStack() throws {
        func nested(_ depth: Int) -> String {
            String(repeating: "[", count: depth) + String(repeating: "]", count: depth)
        }
        XCTAssertNoThrow(try parse(nested(512)))
        XCTAssertThrowsError(try parse(nested(513)))
        XCTAssertThrowsError(try parse(nested(100_000)))
        XCTAssertThrowsError(try parse(String(repeating: #"{"a":"#, count: 100_000)))
    }
}
