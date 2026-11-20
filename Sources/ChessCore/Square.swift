import Foundation

/// A board square. Index 0 is a1, 7 is h1, 56 is a8, 63 is h8.
public struct Square: Hashable, Comparable, Codable, CustomStringConvertible {
    public let index: Int

    public init(_ index: Int) {
        precondition((0..<64).contains(index), "Square index out of range")
        self.index = index
    }

    /// `file` 0...7 is a...h, `rank` 0...7 is 1...8.
    public init(file: Int, rank: Int) {
        self.init(rank * 8 + file)
    }

    /// Parses algebraic names like "e4".
    public init?(_ name: String) {
        let chars = Array(name)
        guard chars.count == 2,
              let file = Square.fileLetters.firstIndex(of: chars[0]),
              let rankNumber = chars[1].wholeNumberValue,
              (1...8).contains(rankNumber)
        else { return nil }
        self.init(file: file, rank: rankNumber - 1)
    }

    public static let fileLetters: [Character] = Array("abcdefgh")
    public static let all: [Square] = (0..<64).map { Square($0) }

    public var file: Int { index % 8 }
    public var rank: Int { index / 8 }
    public var name: String { String(Square.fileLetters[file]) + String(rank + 1) }
    public var description: String { name }

    /// a1 is a dark square.
    public var isLight: Bool { (file + rank) % 2 == 1 }

    public func offset(_ fileDelta: Int, _ rankDelta: Int) -> Square? {
        let f = file + fileDelta
        let r = rank + rankDelta
        guard (0..<8).contains(f), (0..<8).contains(r) else { return nil }
        return Square(file: f, rank: r)
    }

    public static func < (lhs: Square, rhs: Square) -> Bool { lhs.index < rhs.index }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let text = try container.decode(String.self)
        guard let square = Square(text) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid square \(text)")
        }
        self = square
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(name)
    }
}
