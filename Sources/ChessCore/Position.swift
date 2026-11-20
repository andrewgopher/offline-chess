import Foundation

public struct CastlingRights: OptionSet, Hashable, Codable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }

    public static let whiteKingside = CastlingRights(rawValue: 1)
    public static let whiteQueenside = CastlingRights(rawValue: 2)
    public static let blackKingside = CastlingRights(rawValue: 4)
    public static let blackQueenside = CastlingRights(rawValue: 8)
    public static let all: CastlingRights = [.whiteKingside, .whiteQueenside, .blackKingside, .blackQueenside]

    public static func kingside(_ color: PieceColor) -> CastlingRights {
        color == .white ? .whiteKingside : .blackKingside
    }

    public static func queenside(_ color: PieceColor) -> CastlingRights {
        color == .white ? .whiteQueenside : .blackQueenside
    }
}

/// A complete chess position: piece placement plus side to move, castling rights,
/// en-passant target and move counters (everything in a FEN string).
public struct Position: Hashable {
    public private(set) var board: [Piece?]
    public private(set) var sideToMove: PieceColor
    public private(set) var castlingRights: CastlingRights
    public private(set) var enPassantSquare: Square?
    public private(set) var halfmoveClock: Int
    public private(set) var fullmoveNumber: Int

    public static let startingFEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
    public static let standard = Position(fen: startingFEN)!

    private init(board: [Piece?], sideToMove: PieceColor, castlingRights: CastlingRights,
                 enPassantSquare: Square?, halfmoveClock: Int, fullmoveNumber: Int) {
        self.board = board
        self.sideToMove = sideToMove
        self.castlingRights = castlingRights
        self.enPassantSquare = enPassantSquare
        self.halfmoveClock = halfmoveClock
        self.fullmoveNumber = fullmoveNumber
    }

    public subscript(_ square: Square) -> Piece? { board[square.index] }

    // MARK: - FEN

    public init?(fen: String) {
        let parts = fen.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard parts.count >= 4 else { return nil }

        var board = [Piece?](repeating: nil, count: 64)
        let rows = parts[0].split(separator: "/", omittingEmptySubsequences: false)
        guard rows.count == 8 else { return nil }
        for (rowIndex, row) in rows.enumerated() {
            let rank = 7 - rowIndex
            var file = 0
            for ch in row {
                if let empty = ch.wholeNumberValue, (1...8).contains(empty) {
                    file += empty
                } else if let piece = Piece(fenCharacter: ch) {
                    guard file < 8 else { return nil }
                    board[rank * 8 + file] = piece
                    file += 1
                } else {
                    return nil
                }
            }
            guard file == 8 else { return nil }
        }

        let side: PieceColor
        switch parts[1] {
        case "w": side = .white
        case "b": side = .black
        default: return nil
        }

        var rights: CastlingRights = []
        if parts[2] != "-" {
            for ch in parts[2] {
                switch ch {
                case "K": rights.insert(.whiteKingside)
                case "Q": rights.insert(.whiteQueenside)
                case "k": rights.insert(.blackKingside)
                case "q": rights.insert(.blackQueenside)
                default: return nil
                }
            }
        }

        var enPassant: Square?
        if parts[3] != "-" {
            guard let square = Square(parts[3]) else { return nil }
            enPassant = square
        }

        let halfmove = parts.count > 4 ? (Int(parts[4]) ?? 0) : 0
        let fullmove = parts.count > 5 ? (Int(parts[5]) ?? 1) : 1

        self.init(board: board, sideToMove: side, castlingRights: rights,
                  enPassantSquare: enPassant, halfmoveClock: halfmove, fullmoveNumber: max(1, fullmove))
        self.castlingRights = sanitizedCastlingRights(rights)
    }

    public var fen: String {
        var rows: [String] = []
        for rank in stride(from: 7, through: 0, by: -1) {
            var row = ""
            var empty = 0
            for file in 0..<8 {
                if let piece = board[rank * 8 + file] {
                    if empty > 0 { row += String(empty); empty = 0 }
                    row.append(piece.fenCharacter)
                } else {
                    empty += 1
                }
            }
            if empty > 0 { row += String(empty) }
            rows.append(row)
        }
        var castling = ""
        if castlingRights.contains(.whiteKingside) { castling += "K" }
        if castlingRights.contains(.whiteQueenside) { castling += "Q" }
        if castlingRights.contains(.blackKingside) { castling += "k" }
        if castlingRights.contains(.blackQueenside) { castling += "q" }
        if castling.isEmpty { castling = "-" }
        let side = sideToMove == .white ? "w" : "b"
        return "\(rows.joined(separator: "/")) \(side) \(castling) \(enPassantSquare?.name ?? "-") \(halfmoveClock) \(fullmoveNumber)"
    }

    /// Drops castling rights whose king or rook is not on its original square.
    private func sanitizedCastlingRights(_ rights: CastlingRights) -> CastlingRights {
        var result = rights
        if board[4] != Piece(.white, .king) { result.subtract([.whiteKingside, .whiteQueenside]) }
        if board[7] != Piece(.white, .rook) { result.remove(.whiteKingside) }
        if board[0] != Piece(.white, .rook) { result.remove(.whiteQueenside) }
        if board[60] != Piece(.black, .king) { result.subtract([.blackKingside, .blackQueenside]) }
        if board[63] != Piece(.black, .rook) { result.remove(.blackKingside) }
        if board[56] != Piece(.black, .rook) { result.remove(.blackQueenside) }
        return result
    }

    // MARK: - Attacks

    static let knightOffsets: [(Int, Int)] = [(1, 2), (2, 1), (2, -1), (1, -2), (-1, -2), (-2, -1), (-2, 1), (-1, 2)]
    static let kingOffsets: [(Int, Int)] = [(1, 0), (1, 1), (0, 1), (-1, 1), (-1, 0), (-1, -1), (0, -1), (1, -1)]
    static let rookDirections: [(Int, Int)] = [(1, 0), (0, 1), (-1, 0), (0, -1)]
    static let bishopDirections: [(Int, Int)] = [(1, 1), (-1, 1), (-1, -1), (1, -1)]
    static let queenDirections: [(Int, Int)] = rookDirections + bishopDirections

    public func kingSquare(_ color: PieceColor) -> Square? {
        board.firstIndex(of: Piece(color, .king)).map { Square($0) }
    }

    /// Whether any piece of `color` attacks `square`.
    public func isAttacked(_ square: Square, by color: PieceColor) -> Bool {
        for fileDelta in [-1, 1] {
            if let s = square.offset(fileDelta, -color.forward), board[s.index] == Piece(color, .pawn) { return true }
        }
        for (df, dr) in Position.knightOffsets {
            if let s = square.offset(df, dr), board[s.index] == Piece(color, .knight) { return true }
        }
        for (df, dr) in Position.kingOffsets {
            if let s = square.offset(df, dr), board[s.index] == Piece(color, .king) { return true }
        }
        if slidingAttack(square, by: color, directions: Position.rookDirections, kinds: [.rook, .queen]) { return true }
        if slidingAttack(square, by: color, directions: Position.bishopDirections, kinds: [.bishop, .queen]) { return true }
        return false
    }

    private func slidingAttack(_ square: Square, by color: PieceColor, directions: [(Int, Int)], kinds: [PieceKind]) -> Bool {
        for (df, dr) in directions {
            var current = square.offset(df, dr)
            while let s = current {
                if let piece = board[s.index] {
                    if piece.color == color && kinds.contains(piece.kind) { return true }
                    break
                }
                current = s.offset(df, dr)
            }
        }
        return false
    }

    public var isInCheck: Bool {
        guard let king = kingSquare(sideToMove) else { return false }
        return isAttacked(king, by: sideToMove.opposite)
    }

    // MARK: - Move generation

    public func legalMoves() -> [Move] {
        pseudoLegalMoves().filter { leavesKingSafe($0) }
    }

    public func legalMoves(from square: Square) -> [Move] {
        legalMoves().filter { $0.from == square }
    }

    public func isLegal(_ move: Move) -> Bool {
        legalMoves().contains(move)
    }

    private func leavesKingSafe(_ move: Move) -> Bool {
        let next = applying(move)
        guard let king = next.kingSquare(sideToMove) else { return true }
        return !next.isAttacked(king, by: next.sideToMove)
    }

    func pseudoLegalMoves() -> [Move] {
        var moves: [Move] = []
        moves.reserveCapacity(64)
        for index in 0..<64 {
            guard let piece = board[index], piece.color == sideToMove else { continue }
            let from = Square(index)
            switch piece.kind {
            case .pawn: addPawnMoves(from: from, into: &moves)
            case .knight: addStepMoves(from: from, offsets: Position.knightOffsets, into: &moves)
            case .bishop: addSlidingMoves(from: from, directions: Position.bishopDirections, into: &moves)
            case .rook: addSlidingMoves(from: from, directions: Position.rookDirections, into: &moves)
            case .queen: addSlidingMoves(from: from, directions: Position.queenDirections, into: &moves)
            case .king:
                addStepMoves(from: from, offsets: Position.kingOffsets, into: &moves)
                addCastlingMoves(from: from, into: &moves)
            }
        }
        return moves
    }

    private func addPawnMoves(from: Square, into moves: inout [Move]) {
        let us = sideToMove
        let direction = us.forward
        let startRank = us == .white ? 1 : 6
        let promotionRank = us == .white ? 7 : 0

        func add(_ to: Square) {
            if to.rank == promotionRank {
                for kind in PieceKind.promotionChoices {
                    moves.append(Move(from: from, to: to, promotion: kind))
                }
            } else {
                moves.append(Move(from: from, to: to))
            }
        }

        if let one = from.offset(0, direction), board[one.index] == nil {
            add(one)
            if from.rank == startRank, let two = from.offset(0, 2 * direction), board[two.index] == nil {
                moves.append(Move(from: from, to: two))
            }
        }
        for fileDelta in [-1, 1] {
            guard let to = from.offset(fileDelta, direction) else { continue }
            if let target = board[to.index] {
                if target.color != us { add(to) }
            } else if to == enPassantSquare,
                      board[Square(file: to.file, rank: from.rank).index] == Piece(us.opposite, .pawn) {
                moves.append(Move(from: from, to: to))
            }
        }
    }

    private func addStepMoves(from: Square, offsets: [(Int, Int)], into moves: inout [Move]) {
        for (df, dr) in offsets {
            guard let to = from.offset(df, dr) else { continue }
            if let target = board[to.index], target.color == sideToMove { continue }
            moves.append(Move(from: from, to: to))
        }
    }

    private func addSlidingMoves(from: Square, directions: [(Int, Int)], into moves: inout [Move]) {
        for (df, dr) in directions {
            var current = from.offset(df, dr)
            while let to = current {
                if let target = board[to.index] {
                    if target.color != sideToMove { moves.append(Move(from: from, to: to)) }
                    break
                }
                moves.append(Move(from: from, to: to))
                current = to.offset(df, dr)
            }
        }
    }

    private func addCastlingMoves(from: Square, into moves: inout [Move]) {
        let us = sideToMove
        let them = us.opposite
        let homeRank = us == .white ? 0 : 7
        guard from == Square(file: 4, rank: homeRank), !isAttacked(from, by: them) else { return }

        func empty(_ file: Int) -> Bool { board[Square(file: file, rank: homeRank).index] == nil }
        func safe(_ file: Int) -> Bool { !isAttacked(Square(file: file, rank: homeRank), by: them) }

        if castlingRights.contains(.kingside(us)),
           board[Square(file: 7, rank: homeRank).index] == Piece(us, .rook),
           empty(5), empty(6), safe(5), safe(6) {
            moves.append(Move(from: from, to: Square(file: 6, rank: homeRank)))
        }
        if castlingRights.contains(.queenside(us)),
           board[Square(file: 0, rank: homeRank).index] == Piece(us, .rook),
           empty(1), empty(2), empty(3), safe(3), safe(2) {
            moves.append(Move(from: from, to: Square(file: 2, rank: homeRank)))
        }
    }

    // MARK: - Making moves

    public func isCapture(_ move: Move) -> Bool {
        if board[move.to.index] != nil { return true }
        return isEnPassant(move)
    }

    public func isEnPassant(_ move: Move) -> Bool {
        guard let piece = board[move.from.index], piece.kind == .pawn else { return false }
        return move.to == enPassantSquare && move.from.file != move.to.file && board[move.to.index] == nil
    }

    public func isCastling(_ move: Move) -> Bool {
        guard let piece = board[move.from.index], piece.kind == .king else { return false }
        return abs(move.to.file - move.from.file) == 2
    }

    /// Returns the position after `move`. The move is assumed to be at least pseudo-legal.
    public func applying(_ move: Move) -> Position {
        var next = self
        guard let piece = board[move.from.index] else { return next }
        let us = piece.color
        let capture = isCapture(move)

        if isEnPassant(move) {
            next.board[Square(file: move.to.file, rank: move.from.rank).index] = nil
        }
        if isCastling(move) {
            let rank = move.from.rank
            let (rookFrom, rookTo) = move.to.file == 6 ? (7, 5) : (0, 3)
            next.board[Square(file: rookTo, rank: rank).index] = next.board[Square(file: rookFrom, rank: rank).index]
            next.board[Square(file: rookFrom, rank: rank).index] = nil
        }
        next.board[move.from.index] = nil
        if let promotion = move.promotion {
            next.board[move.to.index] = Piece(us, promotion)
        } else {
            next.board[move.to.index] = piece
        }

        if piece.kind == .king {
            next.castlingRights.subtract([.kingside(us), .queenside(us)])
        }
        for square in [move.from, move.to] {
            switch square.index {
            case 0: next.castlingRights.remove(.whiteQueenside)
            case 7: next.castlingRights.remove(.whiteKingside)
            case 56: next.castlingRights.remove(.blackQueenside)
            case 63: next.castlingRights.remove(.blackKingside)
            default: break
            }
        }

        if piece.kind == .pawn && abs(move.to.rank - move.from.rank) == 2 {
            next.enPassantSquare = Square(file: move.from.file, rank: (move.from.rank + move.to.rank) / 2)
        } else {
            next.enPassantSquare = nil
        }
        next.halfmoveClock = (piece.kind == .pawn || capture) ? 0 : halfmoveClock + 1
        if us == .black { next.fullmoveNumber += 1 }
        next.sideToMove = us.opposite
        return next
    }

    // MARK: - SAN

    /// Standard Algebraic Notation for a legal move, including check/mate suffix.
    public func san(for move: Move) -> String {
        guard let piece = board[move.from.index] else { return move.uci }
        var text: String
        if isCastling(move) {
            text = move.to.file == 6 ? "O-O" : "O-O-O"
        } else {
            let capture = isCapture(move)
            text = piece.kind.sanLetter
            if piece.kind == .pawn {
                if capture { text.append(Square.fileLetters[move.from.file]) }
            } else {
                let rivals = legalMoves().filter {
                    $0.to == move.to && $0.from != move.from && board[$0.from.index]?.kind == piece.kind
                }
                if !rivals.isEmpty {
                    let fileClash = rivals.contains { $0.from.file == move.from.file }
                    let rankClash = rivals.contains { $0.from.rank == move.from.rank }
                    if !fileClash {
                        text.append(Square.fileLetters[move.from.file])
                    } else if !rankClash {
                        text += String(move.from.rank + 1)
                    } else {
                        text += move.from.name
                    }
                }
            }
            if capture { text += "x" }
            text += move.to.name
            if let promotion = move.promotion { text += "=" + promotion.sanLetter }
        }
        let next = applying(move)
        if next.isInCheck {
            text += next.legalMoves().isEmpty ? "#" : "+"
        }
        return text
    }

    /// Finds the legal move written in SAN (tolerates missing/extra check marks and annotations).
    public func move(fromSAN san: String) -> Move? {
        let wanted = Position.normalizeSAN(san)
        return legalMoves().first { Position.normalizeSAN(self.san(for: $0)) == wanted }
    }

    static func normalizeSAN(_ san: String) -> String {
        san.replacingOccurrences(of: "0", with: "O")
            .filter { !"+#!?".contains($0) }
    }

    // MARK: - Material

    /// True when neither side can possibly checkmate (automatic draw).
    public var isInsufficientMaterial: Bool {
        var minors: [(kind: PieceKind, square: Square)] = []
        for index in 0..<64 {
            guard let piece = board[index], piece.kind != .king else { continue }
            switch piece.kind {
            case .pawn, .rook, .queen: return false
            default: minors.append((piece.kind, Square(index)))
            }
        }
        if minors.count <= 1 { return true }
        if minors.allSatisfy({ $0.kind == .bishop }) {
            let firstIsLight = minors[0].square.isLight
            return minors.allSatisfy { $0.square.isLight == firstIsLight }
        }
        return false
    }

    /// Whether `color` has enough material that it could ever deliver mate.
    /// Used to turn a flag fall into a draw when the opponent could not have won.
    public func canPossiblyMate(_ color: PieceColor) -> Bool {
        var minors = 0
        for piece in board.compactMap({ $0 }) where piece.color == color && piece.kind != .king {
            switch piece.kind {
            case .pawn, .rook, .queen: return true
            default: minors += 1
            }
        }
        return minors >= 2
    }

    /// Sum of piece values for `color`.
    public func material(for color: PieceColor) -> Int {
        board.compactMap { $0 }.filter { $0.color == color }.reduce(0) { $0 + $1.kind.materialValue }
    }

    /// Pieces of `color` no longer on the board (relative to the standard starting set),
    /// most valuable first.
    public func missingPieces(of color: PieceColor) -> [Piece] {
        let startingCounts: [(PieceKind, Int)] = [(.queen, 1), (.rook, 2), (.bishop, 2), (.knight, 2), (.pawn, 8)]
        var result: [Piece] = []
        for (kind, count) in startingCounts {
            let onBoard = board.filter { $0 == Piece(color, kind) }.count
            for _ in 0..<max(0, count - onBoard) { result.append(Piece(color, kind)) }
        }
        return result
    }

    // MARK: - Repetition

    public struct RepetitionKey: Hashable {
        let board: [Piece?]
        let sideToMove: PieceColor
        let castlingRights: CastlingRights
        let enPassantSquare: Square?
    }

    /// Identity used for threefold repetition. The en-passant square only counts
    /// when an en-passant capture is actually legal.
    public var repetitionKey: RepetitionKey {
        var enPassant = enPassantSquare
        if enPassant != nil && !legalMoves().contains(where: { isEnPassant($0) }) {
            enPassant = nil
        }
        return RepetitionKey(board: board, sideToMove: sideToMove, castlingRights: castlingRights, enPassantSquare: enPassant)
    }
}
