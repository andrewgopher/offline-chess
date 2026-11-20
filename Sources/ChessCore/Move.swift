import Foundation

public struct Move: Hashable, Codable, CustomStringConvertible {
    public let from: Square
    public let to: Square
    public let promotion: PieceKind?

    public init(from: Square, to: Square, promotion: PieceKind? = nil) {
        self.from = from
        self.to = to
        self.promotion = promotion
    }

    /// Parses long algebraic (UCI) notation such as "e2e4" or "e7e8q".
    public init?(uci: String) {
        let chars = Array(uci)
        guard chars.count == 4 || chars.count == 5,
              let from = Square(String(chars[0...1])),
              let to = Square(String(chars[2...3]))
        else { return nil }
        var promotion: PieceKind?
        if chars.count == 5 {
            guard let kind = PieceKind(letter: chars[4]), PieceKind.promotionChoices.contains(kind) else { return nil }
            promotion = kind
        }
        self.init(from: from, to: to, promotion: promotion)
    }

    public var uci: String {
        from.name + to.name + (promotion.map { String($0.letter) } ?? "")
    }

    public var description: String { uci }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let text = try container.decode(String.self)
        guard let move = Move(uci: text) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid move \(text)")
        }
        self = move
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(uci)
    }
}
