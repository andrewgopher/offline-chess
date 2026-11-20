import Foundation

/// Bump when the wire format changes incompatibly; peers with a different version are ignored.
public enum Wire {
    public static let protocolVersion = 1

    public static func encode<T: Encodable>(_ value: T) throws -> Data {
        try JSONEncoder().encode(value)
    }

    public static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try JSONDecoder().decode(type, from: data)
    }
}

public struct PlayerInfo: Codable, Hashable {
    /// Stable random identifier for this installation.
    public var id: String
    public var name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

public struct ChatMessage: Codable, Hashable, Identifiable {
    public var id: UUID
    public var senderID: String
    public var text: String
    public var sentAt: Date

    public init(id: UUID = UUID(), senderID: String, text: String, sentAt: Date) {
        self.id = id
        self.senderID = senderID
        self.text = text
        self.sentAt = sentAt
    }
}

/// A proposal for a new game. Colors are already resolved (no "random" on the wire),
/// so both Macs build the identical game from it.
public struct Challenge: Codable, Hashable {
    public var gameID: UUID
    public var challenger: PlayerInfo
    public var challengerColor: PieceColor
    public var timeControl: TimeControl

    public init(gameID: UUID = UUID(), challenger: PlayerInfo, challengerColor: PieceColor, timeControl: TimeControl) {
        self.gameID = gameID
        self.challenger = challenger
        self.challengerColor = challengerColor
        self.timeControl = timeControl
    }
}

/// Sent as the context of a connection invitation.
public enum Invitation: Codable, Hashable {
    case challenge(Challenge)
    case resume(gameID: UUID, player: PlayerInfo)
}

public struct InvitationEnvelope: Codable, Hashable {
    public var protocolVersion: Int
    public var invitation: Invitation

    public init(_ invitation: Invitation) {
        self.protocolVersion = Wire.protocolVersion
        self.invitation = invitation
    }
}

/// Everything needed to save, resume and reconcile a game.
public struct MatchSnapshot: Codable, Hashable, Identifiable {
    public var gameID: UUID
    public var white: PlayerInfo
    public var black: PlayerInfo
    public var timeControl: TimeControl
    public var moves: [String]
    public var result: GameResult?
    public var whiteRemaining: Double?
    public var blackRemaining: Double?
    public var chat: [ChatMessage]
    public var createdAt: Date
    public var updatedAt: Date

    public var id: UUID { gameID }

    public func player(_ color: PieceColor) -> PlayerInfo { color == .white ? white : black }

    public func color(of playerID: String) -> PieceColor? {
        if white.id == playerID { return .white }
        if black.id == playerID { return .black }
        return nil
    }

    public var sanMoves: [String] {
        ChessGame(uciMoves: moves)?.sanMoves ?? []
    }

    public func pgn() -> String {
        var tags: [(String, String)] = [
            ("Event", "Offline Chess"),
            ("Site", "Offline"),
            ("Date", PGN.dateTag(createdAt)),
            ("Round", "-"),
            ("White", white.name),
            ("Black", black.name),
            ("Result", result?.pgnResult ?? "*"),
            ("TimeControl", timeControl.pgnTag),
        ]
        if let result = result {
            tags.append(("Termination", result.pgnTermination))
        }
        return PGN.render(tags: tags, sanMoves: sanMoves, result: result?.pgnResult ?? "*")
    }
}

/// In-game messages. Every message travels inside a `WireEnvelope` tagged with the game it belongs to.
public enum GameMessage: Codable, Hashable {
    /// Full state, exchanged whenever a connection (re)opens.
    case sync(MatchSnapshot)
    /// `ply` is the 0-based index of this move; `remaining` is the mover's clock after the move.
    case move(ply: Int, uci: String, remaining: Double?)
    case resign(color: PieceColor)
    /// Sent by the player whose own clock ran out.
    case flag(color: PieceColor)
    case drawOffer
    case drawDeclined
    case drawAccepted
    case takebackRequest(atPly: Int)
    case takebackDeclined
    case takebackAccepted(atPly: Int, toPly: Int)
    case chat(ChatMessage)
    case rematchOffer(Challenge)
    case rematchDeclined
    case rematchAccepted(gameID: UUID)
    /// The sender is closing the game on purpose (not a connection drop).
    case leaving
}

public struct WireEnvelope: Codable, Hashable {
    public var protocolVersion: Int
    public var gameID: UUID
    public var message: GameMessage

    public init(gameID: UUID, message: GameMessage) {
        self.protocolVersion = Wire.protocolVersion
        self.gameID = gameID
        self.message = message
    }
}
