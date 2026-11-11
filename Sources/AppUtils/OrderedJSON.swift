//
//  OrderedJSON.swift
//  AppUtils
//

import Foundation

/// A JSON value whose objects keep their keys in the order the document lists them.
///
/// `JSONDecoder` and `JSONSerialization` both hand an object over as a dictionary, and the order of
/// its keys is lost. Use this where the order carries meaning, e.g. keys that are labels shown to the
/// user in the order the server sent them. Strings and numbers are still read by `JSONSerialization`,
/// so escapes and number syntax follow Foundation exactly.
public enum OrderedJSON {
    case object([(key: String, value: OrderedJSON)])
    case array([OrderedJSON])
    case string(String)
    case number(NSNumber)
    case bool(Bool)
    case null

    public struct SyntaxError: Error {
        /// Byte offset of the offending token or character.
        public let offset: Int
    }

    /// Throws `SyntaxError` for anything that is not exactly one JSON value (surrounding whitespace allowed).
    public init(data: Data) throws {
        var reader = Reader(bytes: Array(data))
        self = try reader.readValue()
        reader.skipWhitespace()
        guard reader.isAtEnd else { throw SyntaxError(offset: reader.offset) }
    }

    /// The value of the first member named `key`; `nil` when absent or when this is not an object.
    public subscript(key: String) -> OrderedJSON? {
        guard case .object(let members) = self else { return nil }
        return members.first { $0.key == key }?.value
    }

    public var string: String? {
        guard case .string(let value) = self else { return nil }
        return value
    }

    /// Only a whole number in `Int` range: `200.5` is not read as 200, and `1e30` is not clamped to `Int.max`.
    public var int: Int? {
        guard case .number(let value) = self else { return nil }
        // A double is judged by itself: its `decimalValue` is rounded to about 16 digits, so
        // `1.9999999999999998` would look whole. `NSDecimalNumber` reports "d" too, hence the first check.
        if !(value is NSDecimalNumber), ["f", "d"].contains(String(cString: value.objCType)) {
            return Int(exactly: value.doubleValue)
        }
        // Integers and `NSDecimalNumber` (what `JSONSerialization` returns past 64 bits) are exact as
        // `Decimal`; `intValue` alone is unreliable out of range.
        var decimal = value.decimalValue
        guard !decimal.isNaN, decimal >= Decimal(Int.min), decimal <= Decimal(Int.max) else { return nil }
        var whole = Decimal()
        NSDecimalRound(&whole, &decimal, 0, .plain)
        guard whole == decimal else { return nil }
        return value.intValue
    }
}

// MARK: - Reading

private extension OrderedJSON {

    struct Reader {
        let bytes: [UInt8]
        var offset = 0
        /// Containers currently open. Reading recurses per level, so a hostile body would otherwise
        /// overflow the stack; 512 is about where `JSONSerialization` gives up too.
        private var depth = 0
        private let maxDepth = 512

        var isAtEnd: Bool { offset >= bytes.count }

        mutating func readValue() throws -> OrderedJSON {
            skipWhitespace()
            guard !isAtEnd else { throw SyntaxError(offset: offset) }
            switch bytes[offset] {
            case UInt8(ascii: "{"): return try readObject()
            case UInt8(ascii: "["): return try readArray()
            case UInt8(ascii: "\""): return .string(try readString())
            default: return try readScalar()
            }
        }

        mutating func skipWhitespace() {
            while !isAtEnd, [0x20, 0x09, 0x0A, 0x0D].contains(bytes[offset]) {
                offset += 1
            }
        }

        private mutating func readObject() throws -> OrderedJSON {
            try enterContainer()
            defer { depth -= 1 }
            offset += 1
            var members: [(key: String, value: OrderedJSON)] = []
            skipWhitespace()
            if consume("}") { return .object(members) }
            repeat {
                skipWhitespace()
                guard !isAtEnd, bytes[offset] == UInt8(ascii: "\"") else { throw SyntaxError(offset: offset) }
                let key = try readString()
                skipWhitespace()
                guard consume(":") else { throw SyntaxError(offset: offset) }
                members.append((key, try readValue()))
                skipWhitespace()
            } while consume(",")
            guard consume("}") else { throw SyntaxError(offset: offset) }
            return .object(members)
        }

        private mutating func readArray() throws -> OrderedJSON {
            try enterContainer()
            defer { depth -= 1 }
            offset += 1
            var items: [OrderedJSON] = []
            skipWhitespace()
            if consume("]") { return .array(items) }
            repeat {
                items.append(try readValue())
                skipWhitespace()
            } while consume(",")
            guard consume("]") else { throw SyntaxError(offset: offset) }
            return .array(items)
        }

        /// The whole quoted token goes to `JSONSerialization`, which owns the escapes (`\uXXXX`, surrogate pairs).
        private mutating func readString() throws -> String {
            let start = offset
            offset += 1
            while !isAtEnd, bytes[offset] != UInt8(ascii: "\"") {
                offset += bytes[offset] == UInt8(ascii: "\\") ? 2 : 1
            }
            guard !isAtEnd else { throw SyntaxError(offset: start) }
            offset += 1
            guard let value = try fragment(from: start) as? String else { throw SyntaxError(offset: start) }
            return value
        }

        private mutating func readScalar() throws -> OrderedJSON {
            let start = offset
            while !isAtEnd, !"{}[],: \t\n\r\"".utf8.contains(bytes[offset]) {
                offset += 1
            }
            // A lone fragment lets Foundation skip a leading byte-order mark, which is not valid inside a document.
            guard offset > start, "-0123456789tfn".utf8.contains(bytes[start]) else { throw SyntaxError(offset: start) }
            switch try fragment(from: start) {
            case is NSNull: return .null
            // `true`/`false` come back as an `NSNumber` too; only the literal tells them from 1 and 0.
            case let number as NSNumber where bytes[start] == UInt8(ascii: "t") || bytes[start] == UInt8(ascii: "f"):
                return .bool(number.boolValue)
            case let number as NSNumber: return .number(number)
            default: throw SyntaxError(offset: start)
            }
        }

        private func fragment(from start: Int) throws -> Any {
            do {
                return try JSONSerialization.jsonObject(with: Data(bytes[start..<offset]), options: .fragmentsAllowed)
            } catch {
                throw SyntaxError(offset: start)
            }
        }

        private mutating func enterContainer() throws {
            guard depth < maxDepth else { throw SyntaxError(offset: offset) }
            depth += 1
        }

        private mutating func consume(_ character: Unicode.Scalar) -> Bool {
            guard !isAtEnd, bytes[offset] == UInt8(ascii: character) else { return false }
            offset += 1
            return true
        }
    }
}
