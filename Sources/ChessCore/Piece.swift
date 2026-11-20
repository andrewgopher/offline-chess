import Foundation

public enum PieceColor: String, Codable, CaseIterable, Hashable {
    case white
    case black

    public var opposite: PieceColor { self == .white ? .black : .white }
    public var name: String { self == .white ? "White" : "Black" }

    /// The rank direction pawns of this color advance in.
    var forward: Int { self == .white ? 1 : -1 }
}

public enum PieceKind: String, Codable, CaseIterable, Hashable {
    case pawn, knight, bishop, rook, queen, king

    /// Lowercase letter used in FEN and UCI notation.
    public var letter: Character {
        switch self {
        case .pawn: return "p"
        case .knight: return "n"
        case .bishop: return "b"
        case .rook: return "r"
        case .queen: return "q"
        case .king: return "k"
        }
    }

    public init?(letter: Character) {
        switch letter.lowercased() {
        case "p": self = .pawn
        case "n": self = .knight
        case "b": self = .bishop
        case "r": self = .rook
        case "q": self = .queen
        case "k": self = .king
        default: return nil
        }
    }

    /// Piece letter as written in SAN (empty for pawns).
    public var sanLetter: String { self == .pawn ? "" : String(letter).uppercased() }

    public var materialValue: Int {
        switch self {
        case .pawn: return 1
        case .knight, .bishop: return 3
        case .rook: return 5
        case .queen: return 9
        case .king: return 0
        }
    }

    public static let promotionChoices: [PieceKind] = [.queen, .rook, .bishop, .knight]
}

public struct Piece: Hashable, Codable {
    public let color: PieceColor
    public let kind: PieceKind

    public init(_ color: PieceColor, _ kind: PieceKind) {
        self.color = color
        self.kind = kind
    }

    public var fenCharacter: Character {
        color == .white ? Character(String(kind.letter).uppercased()) : kind.letter
    }

    public init?(fenCharacter: Character) {
        guard let kind = PieceKind(letter: fenCharacter) else { return nil }
        self.init(fenCharacter.isUppercase ? .white : .black, kind)
    }

    /// Filled Unicode chess glyph. The UI tints it per color.
    public var solidGlyph: String {
        switch kind {
        case .king: return "\u{265A}\u{FE0E}"
        case .queen: return "\u{265B}\u{FE0E}"
        case .rook: return "\u{265C}\u{FE0E}"
        case .bishop: return "\u{265D}\u{FE0E}"
        case .knight: return "\u{265E}\u{FE0E}"
        case .pawn: return "\u{265F}\u{FE0E}"
        }
    }

    /// Outlined Unicode chess glyph, drawn over the solid one for white pieces.
    public var outlineGlyph: String {
        switch kind {
        case .king: return "\u{2654}\u{FE0E}"
        case .queen: return "\u{2655}\u{FE0E}"
        case .rook: return "\u{2656}\u{FE0E}"
        case .bishop: return "\u{2657}\u{FE0E}"
        case .knight: return "\u{2658}\u{FE0E}"
        case .pawn: return "\u{2659}\u{FE0E}"
        }
    }
}
