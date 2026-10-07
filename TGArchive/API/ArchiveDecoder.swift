import Foundation

/// The one JSON decoder for every archive route: snake_case keys, the archive's date forms, and the
/// lenient wrappers below.
enum ArchiveDecoder {
    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws(APIError) -> T {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            guard let date = ArchiveDate.parse(text) else {
                // The value is left out on purpose: error text is logged, and dates sit next to message text.
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "not an ISO 8601 date")
            }
            return date
        }
        do {
            return try decoder.decode(T.self, from: data)
        } catch let error as DecodingError {
            throw .decoding(ArchiveDecoder.describe(error))
        } catch {
            throw .decoding(String(describing: Swift.type(of: error)))
        }
    }

    /// The coding path and the kind of failure, never the value that failed.
    static func describe(_ error: DecodingError) -> String {
        func path(_ context: DecodingError.Context) -> String {
            context.codingPath.map { $0.intValue.map(String.init) ?? $0.stringValue }.joined(separator: ".")
        }
        switch error {
        case let .typeMismatch(type, context): return "type mismatch (\(type)) at \(path(context))"
        case let .valueNotFound(type, context): return "missing value (\(type)) at \(path(context))"
        case let .keyNotFound(key, context): return "missing key \(key.stringValue) at \(path(context))"
        case let .dataCorrupted(context): return "corrupted data at \(path(context)): \(context.debugDescription)"
        @unknown default: return "decoding error"
        }
    }
}

/// The archive's timestamps: ISO 8601 with or without fractional seconds and with or without an offset.
/// A timestamp without an offset is UTC, as the server documents.
enum ArchiveDate {
    static func parse(_ text: String) -> Date? {
        var scanner = DigitScanner(Array(text.utf8))
        guard let year = scanner.number(4), scanner.skip("-"),
              let month = scanner.number(2), scanner.skip("-"),
              let day = scanner.number(2), scanner.skip("T") || scanner.skip(" "),
              let hour = scanner.number(2), scanner.skip(":"),
              let minute = scanner.number(2)
        else { return nil }
        var second = 0
        var fraction = 0.0
        if scanner.skip(":") {
            guard let value = scanner.number(2) else { return nil }
            second = value
            if scanner.skip(".") || scanner.skip(",") {
                guard let digits = scanner.fraction() else { return nil }
                fraction = digits
            }
        }
        var offset = 0
        if scanner.skip("Z") || scanner.skip("z") {
            offset = 0
        } else if let sign = scanner.sign() {
            guard let hours = scanner.number(2) else { return nil }
            _ = scanner.skip(":")
            guard let minutes = scanner.number(2) else { return nil }
            offset = sign * (hours * 3600 + minutes * 60)
        }
        guard scanner.atEnd, (1...12).contains(month), (1...31).contains(day), hour < 24, minute < 60, second < 61
        else { return nil }
        let days = daysFromCivil(year: year, month: month, day: day)
        let seconds = days * 86_400 + hour * 3600 + minute * 60 + second - offset
        return Date(timeIntervalSince1970: Double(seconds) + fraction)
    }

    /// Days since 1970-01-01 in the proleptic Gregorian calendar (Howard Hinnant's algorithm).
    private static func daysFromCivil(year: Int, month: Int, day: Int) -> Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yearOfEra = y - era * 400
        let dayOfYear = (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146_097 + dayOfEra - 719_468
    }

    /// How a cursor date goes back to the server: UTC with a `Z`, whole seconds, as Telegram dates are.
    static func format(_ date: Date) -> String {
        date.formatted(Date.ISO8601FormatStyle(timeZone: .gmt))
    }
}

private struct DigitScanner {
    private let bytes: [UInt8]
    private var index = 0

    init(_ bytes: [UInt8]) { self.bytes = bytes }

    var atEnd: Bool { index == bytes.count }

    mutating func skip(_ character: Character) -> Bool {
        guard index < bytes.count, let ascii = character.asciiValue, bytes[index] == ascii else { return false }
        index += 1
        return true
    }

    mutating func number(_ width: Int) -> Int? {
        guard index + width <= bytes.count else { return nil }
        var value = 0
        for byte in bytes[index..<index + width] {
            guard (48...57).contains(byte) else { return nil }
            value = value * 10 + Int(byte - 48)
        }
        index += width
        return value
    }

    mutating func fraction() -> Double? {
        var value = 0.0
        var scale = 0.1
        let start = index
        while index < bytes.count, (48...57).contains(bytes[index]) {
            value += Double(bytes[index] - 48) * scale
            scale /= 10
            index += 1
        }
        return index > start ? value : nil
    }

    mutating func sign() -> Int? {
        if skip("+") { return 1 }
        if skip("-") { return -1 }
        return nil
    }
}

/// A flag the archive sends as `0`/`1` on some routes and `true`/`false` on others. `null` and a missing key
/// both read as false.
@propertyWrapper
struct FlexBool: Decodable, Hashable, Sendable {
    var wrappedValue: Bool

    init(wrappedValue: Bool) { self.wrappedValue = wrappedValue }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            wrappedValue = false
        } else if let flag = try? container.decode(Bool.self) {
            wrappedValue = flag
        } else if let number = try? container.decode(Int.self) {
            wrappedValue = number != 0
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "not a flag")
        }
    }
}

/// A part of a payload the app can live without (raw data, media, reactions). A part that does not decode
/// reads as nil, so one odd message never fails its whole page.
@propertyWrapper
struct Lenient<Value: Decodable & Hashable & Sendable>: Decodable, Hashable, Sendable {
    var wrappedValue: Value?

    init(wrappedValue: Value?) { self.wrappedValue = wrappedValue }

    init(from decoder: Decoder) throws {
        wrappedValue = try? decoder.singleValueContainer().decode(Value.self)
    }
}

/// A value the archive sends as a number on some rows and a string on others; kept as a string.
struct NumberOrString: Decodable, Hashable, Sendable {
    let value: String

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let text = try? container.decode(String.self) {
            value = text
        } else if let number = try? container.decode(Int64.self) {
            value = String(number)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "neither a number nor a string")
        }
    }
}

extension KeyedDecodingContainer {
    // The synthesized decoders call these for wrapped properties; a missing key falls back instead of failing.
    func decode(_ type: FlexBool.Type, forKey key: Key) throws -> FlexBool {
        try decodeIfPresent(type, forKey: key) ?? FlexBool(wrappedValue: false)
    }

    func decode<Value>(_ type: Lenient<Value>.Type, forKey key: Key) throws -> Lenient<Value> {
        (try? decodeIfPresent(type, forKey: key)) ?? Lenient(wrappedValue: nil)
    }
}
