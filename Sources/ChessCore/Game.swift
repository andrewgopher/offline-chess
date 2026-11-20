import Foundation

public struct GameResult: Codable, Hashable {
    public enum Reason: String, Codable, Hashable {
        case checkmate
        case resignation
        case timeout
        case stalemate
        case insufficientMaterial
        case threefoldRepetition
        case fiftyMoveRule
        case agreement
        /// Flag fell, but the opponent had no mating material.
        case timeoutVsInsufficientMaterial
    }

    /// `nil` means a draw.
    public let winner: PieceColor?
    public let reason: Reason

    public init(winner: PieceColor?, reason: Reason) {
        self.winner = winner
        self.reason = reason
    }

    /// Results that follow from the moves on the board alone.
    public var isAutomatic: Bool {
        switch reason {
        case .checkmate, .stalemate, .insufficientMaterial, .threefoldRepetition, .fiftyMoveRule: return true
        case .resignation, .timeout, .agreement, .timeoutVsInsufficientMaterial: return false
        }
    }

    public var pgnResult: String {
        switch winner {
        case .white?: return "1-0"
        case .black?: return "0-1"
        case nil: return "1/2-1/2"
        }
    }

    public var pgnTermination: String {
        switch reason {
        case .timeout, .timeoutVsInsufficientMaterial: return "Time forfeit"
        default: return "Normal"
        }
    }

    /// Stable ordering key used to break ties deterministically when merging.
    var sortKey: String { "\(winner?.rawValue ?? "draw")-\(reason.rawValue)" }

    public func summary(white: String, black: String) -> String {
        let winnerName = winner.map { $0 == .white ? white : black } ?? ""
        let loserName = winner.map { $0 == .white ? black : white } ?? ""
        switch reason {
        case .checkmate: return "Checkmate. \(winnerName) wins."
        case .resignation: return "\(loserName) resigned. \(winnerName) wins."
        case .timeout: return "\(loserName) ran out of time. \(winnerName) wins."
        case .stalemate: return "Draw by stalemate."
        case .insufficientMaterial: return "Draw: insufficient material."
        case .threefoldRepetition: return "Draw by threefold repetition."
        case .fiftyMoveRule: return "Draw by the 50-move rule."
        case .agreement: return "Draw by agreement."
        case .timeoutVsInsufficientMaterial: return "Time ran out, but the other side can't checkmate. Draw."
        }
    }
}

/// A game from the standard starting position: the move list plus every
/// intermediate position, SAN, and automatic game-over detection.
public struct ChessGame {
    public let initialPosition: Position
    public private(set) var moves: [Move] = []
    public private(set) var sanMoves: [String] = []
    /// `positions[i]` is the position after `i` moves; always `moves.count + 1` long.
    public private(set) var positions: [Position]
    private var repetitionKeys: [Position.RepetitionKey]

    public init(initialPosition: Position = .standard) {
        self.initialPosition = initialPosition
        self.positions = [initialPosition]
        self.repetitionKeys = [initialPosition.repetitionKey]
    }

    /// Replays UCI moves; fails if any of them is illegal.
    public init?(initialPosition: Position = .standard, uciMoves: [String]) {
        self.init(initialPosition: initialPosition)
        for text in uciMoves {
            guard let move = Move(uci: text), play(move) else { return nil }
        }
    }

    public var position: Position { positions[positions.count - 1] }
    public var ply: Int { moves.count }
    public var lastMove: Move? { moves.last }

    /// The color that made move number `ply` (0-based).
    public func mover(ofPly ply: Int) -> PieceColor { positions[ply].sideToMove }

    /// Plays `move` if it is legal. Returns false (and changes nothing) otherwise.
    @discardableResult
    public mutating func play(_ move: Move) -> Bool {
        let current = position
        guard current.legalMoves().contains(move) else { return false }
        sanMoves.append(current.san(for: move))
        let next = current.applying(move)
        moves.append(move)
        positions.append(next)
        repetitionKeys.append(next.repetitionKey)
        return true
    }

    /// Removes moves so that exactly `ply` moves remain.
    public mutating func truncate(toPly ply: Int) {
        let keep = max(0, min(ply, moves.count))
        moves.removeSubrange(keep...)
        sanMoves.removeSubrange(keep...)
        positions.removeSubrange((keep + 1)...)
        repetitionKeys.removeSubrange((keep + 1)...)
    }

    /// Game over by the rules of chess (mate, stalemate, automatic draws), if any.
    public var outcome: GameResult? {
        let current = position
        if current.legalMoves().isEmpty {
            return current.isInCheck
                ? GameResult(winner: current.sideToMove.opposite, reason: .checkmate)
                : GameResult(winner: nil, reason: .stalemate)
        }
        if current.isInsufficientMaterial { return GameResult(winner: nil, reason: .insufficientMaterial) }
        if let last = repetitionKeys.last, repetitionKeys.filter({ $0 == last }).count >= 3 {
            return GameResult(winner: nil, reason: .threefoldRepetition)
        }
        if current.halfmoveClock >= 100 { return GameResult(winner: nil, reason: .fiftyMoveRule) }
        return nil
    }
}
