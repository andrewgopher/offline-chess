import Foundation

/// Something the UI may want to react to (sounds, banners, notifications).
public enum MatchEvent: Hashable {
    case moved(san: String, byLocalPlayer: Bool, capture: Bool, check: Bool)
    case gameOver(GameResult)
    case drawOffered
    case drawDeclined
    case takebackRequested
    case takebackDeclined
    case takebackApplied
    case chatReceived(ChatMessage)
    case resynced
}

/// Result of applying a local action or a remote message: what to send and what happened.
public struct MatchUpdate {
    public var outgoing: [GameMessage] = []
    public var events: [MatchEvent] = []
    public init() {}
}

/// One game between the local player and an opponent, as seen from one Mac.
///
/// Both Macs run an identical `Match`. Each side is authoritative for its own moves and its
/// own clock. Every local action produces messages for the peer, and every received message
/// is validated before it is applied. On (re)connect both sides exchange a snapshot and run
/// the same deterministic `merge`, so they converge on the same game.
public struct Match {
    public let gameID: UUID
    public private(set) var white: PlayerInfo
    public private(set) var black: PlayerInfo
    public let localColor: PieceColor
    public let timeControl: TimeControl
    public let createdAt: Date
    public private(set) var updatedAt: Date

    public private(set) var game: ChessGame
    public private(set) var clock: ChessClock?
    public private(set) var result: GameResult?
    public private(set) var chat: [ChatMessage] = []
    /// Which side has an open draw offer.
    public private(set) var drawOfferFrom: PieceColor?
    public private(set) var takebackRequest: TakebackRequest?

    public struct TakebackRequest: Hashable {
        public let requester: PieceColor
        public let atPly: Int
    }

    public static let maxChatLength = 500

    // MARK: - Creating

    /// Builds a new game from a challenge. Call on both Macs with the same challenge.
    public init(challenge: Challenge, accepter: PlayerInfo, localPlayerID: String, now: Date) {
        gameID = challenge.gameID
        if challenge.challengerColor == .white {
            white = challenge.challenger
            black = accepter
        } else {
            white = accepter
            black = challenge.challenger
        }
        localColor = localPlayerID == white.id ? .white : .black
        timeControl = challenge.timeControl
        createdAt = now
        updatedAt = now
        game = ChessGame()
        if let initial = challenge.timeControl.initialSeconds {
            clock = ChessClock(white: Double(initial), black: Double(initial))
        }
    }

    /// Restores a saved game. Fails if the local player isn't in it or its moves are invalid.
    public init?(snapshot: MatchSnapshot, localPlayerID: String) {
        guard let color = snapshot.color(of: localPlayerID),
              let game = ChessGame(uciMoves: snapshot.moves)
        else { return nil }
        gameID = snapshot.gameID
        white = snapshot.white
        black = snapshot.black
        localColor = color
        timeControl = snapshot.timeControl
        createdAt = snapshot.createdAt
        updatedAt = snapshot.updatedAt
        self.game = game
        result = snapshot.result ?? game.outcome
        chat = snapshot.chat
        if let initial = snapshot.timeControl.initialSeconds {
            clock = ChessClock(white: snapshot.whiteRemaining ?? Double(initial),
                               black: snapshot.blackRemaining ?? Double(initial))
        }
    }

    public func snapshot(at now: Date) -> MatchSnapshot {
        MatchSnapshot(
            gameID: gameID,
            white: white,
            black: black,
            timeControl: timeControl,
            moves: game.moves.map(\.uci),
            result: result,
            whiteRemaining: clock.map { max(0, $0.remaining(.white, at: now)) },
            blackRemaining: clock.map { max(0, $0.remaining(.black, at: now)) },
            chat: chat,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    // MARK: - Queries

    public var opponentColor: PieceColor { localColor.opposite }
    public func player(_ color: PieceColor) -> PlayerInfo { color == .white ? white : black }
    public var localPlayer: PlayerInfo { player(localColor) }
    public var opponent: PlayerInfo { player(opponentColor) }
    public var isOver: Bool { result != nil }
    public var sideToMove: PieceColor { game.position.sideToMove }
    public var isLocalTurn: Bool { result == nil && sideToMove == localColor }

    public var canRequestTakeback: Bool {
        result == nil && takebackRequest == nil && lastMoveIndex(of: localColor) != nil
    }

    public var canOfferDraw: Bool { result == nil && drawOfferFrom == nil }

    func lastMoveIndex(of color: PieceColor) -> Int? {
        guard game.ply > 0 else { return nil }
        return stride(from: game.ply - 1, through: 0, by: -1).first { game.mover(ofPly: $0) == color }
    }

    // MARK: - Local actions

    /// Plays a move for the local player. Returns nil if it isn't our turn or the move is illegal.
    public mutating func playLocalMove(_ move: Move, at now: Date) -> MatchUpdate? {
        guard isLocalTurn, game.position.isLegal(move) else { return nil }
        let ply = game.ply
        let capture = game.position.isCapture(move)
        game.play(move)

        var remaining: Double?
        if var c = clock {
            c.stop(at: now)
            // No time was used before the first move, so it earns no increment.
            if ply > 0 { c.add(Double(timeControl.incrementSeconds), to: localColor) }
            remaining = c.remaining(localColor, at: now)
            clock = c
        }
        if drawOfferFrom == opponentColor { drawOfferFrom = nil }  // moving declines their offer
        takebackRequest = nil

        var update = MatchUpdate()
        update.outgoing.append(.move(ply: ply, uci: move.uci, remaining: remaining))
        update.events.append(.moved(san: game.sanMoves.last ?? move.uci, byLocalPlayer: true,
                                    capture: capture, check: game.position.isInCheck))
        afterMove(&update, now: now)
        return update
    }

    public mutating func resign(at now: Date) -> MatchUpdate? {
        guard result == nil else { return nil }
        var update = MatchUpdate()
        update.outgoing.append(.resign(color: localColor))
        finish(GameResult(winner: opponentColor, reason: .resignation), now: now, update: &update)
        return update
    }

    public mutating func offerDraw(at now: Date) -> MatchUpdate? {
        guard canOfferDraw else { return nil }
        drawOfferFrom = localColor
        updatedAt = now
        var update = MatchUpdate()
        update.outgoing.append(.drawOffer)
        return update
    }

    public mutating func respondToDrawOffer(accept: Bool, at now: Date) -> MatchUpdate? {
        guard result == nil, drawOfferFrom == opponentColor else { return nil }
        drawOfferFrom = nil
        var update = MatchUpdate()
        if accept {
            update.outgoing.append(.drawAccepted)
            finish(GameResult(winner: nil, reason: .agreement), now: now, update: &update)
        } else {
            update.outgoing.append(.drawDeclined)
            updatedAt = now
        }
        return update
    }

    public mutating func requestTakeback(at now: Date) -> MatchUpdate? {
        guard canRequestTakeback else { return nil }
        takebackRequest = TakebackRequest(requester: localColor, atPly: game.ply)
        updatedAt = now
        var update = MatchUpdate()
        update.outgoing.append(.takebackRequest(atPly: game.ply))
        return update
    }

    public mutating func respondToTakeback(accept: Bool, at now: Date) -> MatchUpdate? {
        guard result == nil, let request = takebackRequest, request.requester == opponentColor else { return nil }
        takebackRequest = nil
        var update = MatchUpdate()
        if accept, let target = lastMoveIndex(of: opponentColor) {
            applyTakeback(toPly: target, now: now)
            update.outgoing.append(.takebackAccepted(atPly: request.atPly, toPly: target))
            update.events.append(.takebackApplied)
        } else {
            update.outgoing.append(.takebackDeclined)
            updatedAt = now
        }
        return update
    }

    public mutating func sendChat(_ text: String, at now: Date) -> MatchUpdate? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let message = ChatMessage(senderID: localPlayer.id, text: String(trimmed.prefix(Match.maxChatLength)), sentAt: now)
        chat.append(message)
        updatedAt = now
        var update = MatchUpdate()
        update.outgoing.append(.chat(message))
        return update
    }

    /// Call periodically. Ends the game if the local player's own clock has run out.
    /// Only the owner of a clock declares its flag, so both sides always agree.
    public mutating func checkFlag(at now: Date) -> MatchUpdate? {
        guard result == nil, var c = clock, c.running == localColor, c.remaining(localColor, at: now) <= 0 else { return nil }
        c.stop(at: now)
        c.set(localColor, 0)
        clock = c
        var update = MatchUpdate()
        update.outgoing.append(.flag(color: localColor))
        finish(timeoutResult(flagged: localColor), now: now, update: &update)
        return update
    }

    /// Stops the clock (e.g. while disconnected).
    public mutating func pauseClock(at now: Date) {
        clock?.stop(at: now)
    }

    /// Restarts the clock of the side to move. Clocks only run after White's first move.
    public mutating func resumeClock(at now: Date) {
        guard result == nil, game.ply > 0 else { return }
        clock?.start(sideToMove, at: now)
    }

    // MARK: - Remote messages

    public mutating func receive(_ message: GameMessage, at now: Date) -> MatchUpdate {
        var update = MatchUpdate()
        switch message {
        case .sync(let remote):
            merge(remote, at: now, update: &update)

        case let .move(ply, uci, remaining):
            // Stale or out-of-turn moves (e.g. crossing a takeback) are ignored.
            guard ply == game.ply, sideToMove == opponentColor, let move = Move(uci: uci) else { break }
            let capture = game.position.isCapture(move)
            guard game.play(move) else { break }
            if var c = clock {
                c.stop(at: now)
                if let remaining = remaining { c.set(opponentColor, remaining) }
                clock = c
            }
            if drawOfferFrom == localColor { drawOfferFrom = nil }  // they moved instead of accepting
            takebackRequest = nil
            update.events.append(.moved(san: game.sanMoves.last ?? uci, byLocalPlayer: false,
                                        capture: capture, check: game.position.isInCheck))
            if result == nil {
                afterMove(&update, now: now)
            } else {
                updatedAt = now
            }

        case .resign(let color):
            guard result == nil, color == opponentColor else { break }
            finish(GameResult(winner: localColor, reason: .resignation), now: now, update: &update)

        case .flag(let color):
            guard result == nil, color == opponentColor else { break }
            if var c = clock {
                c.stop(at: now)
                c.set(opponentColor, 0)
                clock = c
            }
            finish(timeoutResult(flagged: opponentColor), now: now, update: &update)

        case .drawOffer:
            guard result == nil else { break }
            drawOfferFrom = opponentColor
            updatedAt = now
            update.events.append(.drawOffered)

        case .drawDeclined:
            guard drawOfferFrom == localColor else { break }
            drawOfferFrom = nil
            updatedAt = now
            update.events.append(.drawDeclined)

        case .drawAccepted:
            // The opponent has already ended the game on their side; always honor it.
            guard result == nil else { break }
            drawOfferFrom = nil
            finish(GameResult(winner: nil, reason: .agreement), now: now, update: &update)

        case .takebackRequest(let atPly):
            guard result == nil, atPly == game.ply, lastMoveIndex(of: opponentColor) != nil else { break }
            takebackRequest = TakebackRequest(requester: opponentColor, atPly: atPly)
            updatedAt = now
            update.events.append(.takebackRequested)

        case .takebackDeclined:
            guard takebackRequest?.requester == localColor else { break }
            takebackRequest = nil
            updatedAt = now
            update.events.append(.takebackDeclined)

        case let .takebackAccepted(_, toPly):
            // The opponent already truncated; follow them as long as the target is one of our moves,
            // even if we moved in the meantime (that move is discarded on both sides).
            guard toPly >= 0, toPly < game.ply, game.mover(ofPly: toPly) == localColor,
                  result == nil || result?.isAutomatic == true
            else { break }
            applyTakeback(toPly: toPly, now: now)
            update.events.append(.takebackApplied)

        case .chat(let message):
            guard !chat.contains(where: { $0.id == message.id }) else { break }
            var incoming = message
            incoming.text = String(incoming.text.prefix(Match.maxChatLength))
            chat.append(incoming)
            updatedAt = now
            update.events.append(.chatReceived(incoming))

        case .rematchOffer, .rematchDeclined, .rematchAccepted, .leaving:
            break  // handled by the app (they concern the connection, not this game)
        }
        return update
    }

    // MARK: - Reconciliation

    /// Merges the peer's snapshot into ours. Deterministic and symmetric: when both sides merge
    /// each other's snapshot they end up with the same moves, result, clocks and chat.
    mutating func merge(_ remote: MatchSnapshot, at now: Date, update: inout MatchUpdate) {
        guard remote.gameID == gameID else { return }

        let localMoves = game.moves.map(\.uci)
        let chosen = Match.chooseHistory(localMoves, remote.moves)
        if chosen != localMoves, let replayed = ChessGame(uciMoves: chosen) {
            game = replayed
        }

        // Each side is authoritative for its own name and clock.
        if opponentColor == .white { white.name = remote.white.name } else { black.name = remote.black.name }
        if var c = clock {
            c.stop(at: now)
            let theirs = opponentColor == .white ? remote.whiteRemaining : remote.blackRemaining
            if let theirs = theirs { c.set(opponentColor, theirs) }
            clock = c
        }

        let localEvent = result.flatMap { $0.isAutomatic ? nil : $0 }
        let remoteEvent = remote.result.flatMap { $0.isAutomatic ? nil : $0 }
        result = game.outcome ?? Match.chooseResult(localEvent, remoteEvent)

        var known = Set(chat.map(\.id))
        for message in remote.chat where !known.contains(message.id) {
            chat.append(message)
            known.insert(message.id)
        }
        chat.sort { ($0.sentAt, $0.id.uuidString) < ($1.sentAt, $1.id.uuidString) }

        drawOfferFrom = nil
        takebackRequest = nil
        updatedAt = max(updatedAt, remote.updatedAt)
        update.events.append(.resynced)
    }

    /// If one history extends the other, the longer one wins. Otherwise (should not happen)
    /// pick deterministically so both sides still agree.
    static func chooseHistory(_ a: [String], _ b: [String]) -> [String] {
        if a.count >= b.count, Array(a.prefix(b.count)) == b { return a }
        if b.count > a.count, Array(b.prefix(a.count)) == a { return b }
        if a.count != b.count { return a.count > b.count ? a : b }
        return a.joined(separator: " ") > b.joined(separator: " ") ? a : b
    }

    static func chooseResult(_ a: GameResult?, _ b: GameResult?) -> GameResult? {
        switch (a, b) {
        case (nil, nil): return nil
        case let (x?, nil): return x
        case let (nil, y?): return y
        case let (x?, y?): return x.sortKey <= y.sortKey ? x : y
        }
    }

    // MARK: - Helpers

    private func timeoutResult(flagged: PieceColor) -> GameResult {
        game.position.canPossiblyMate(flagged.opposite)
            ? GameResult(winner: flagged.opposite, reason: .timeout)
            : GameResult(winner: nil, reason: .timeoutVsInsufficientMaterial)
    }

    /// Common bookkeeping after any move: detect game over or hand the clock to the side to move.
    private mutating func afterMove(_ update: inout MatchUpdate, now: Date) {
        if let outcome = game.outcome {
            finish(outcome, now: now, update: &update)
        } else {
            clock?.start(sideToMove, at: now)
            updatedAt = now
        }
    }

    private mutating func finish(_ outcome: GameResult, now: Date, update: inout MatchUpdate) {
        result = outcome
        clock?.stop(at: now)
        drawOfferFrom = nil
        takebackRequest = nil
        updatedAt = now
        update.events.append(.gameOver(outcome))
    }

    private mutating func applyTakeback(toPly target: Int, now: Date) {
        game.truncate(toPly: target)
        if result?.isAutomatic == true { result = nil }
        drawOfferFrom = nil
        takebackRequest = nil
        clock?.stop(at: now)
        resumeClock(at: now)
        updatedAt = now
    }
}
