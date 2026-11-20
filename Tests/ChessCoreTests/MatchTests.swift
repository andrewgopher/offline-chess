import XCTest
import ChessCore

/// Simulates the two Macs: `a` is White, `b` is Black. Messages go through JSON like on the wire.
private struct Table {
    var a: Match
    var b: Match
    var now = Date(timeIntervalSinceReferenceDate: 10_000)

    static let alice = PlayerInfo(id: "A", name: "Alice")
    static let bob = PlayerInfo(id: "B", name: "Bob")

    init(timeControl: TimeControl = TimeControl(initialSeconds: 60, incrementSeconds: 2)) {
        let challenge = Challenge(challenger: Table.alice, challengerColor: .white, timeControl: timeControl)
        a = Match(challenge: challenge, accepter: Table.bob, localPlayerID: "A", now: now)
        b = Match(challenge: challenge, accepter: Table.bob, localPlayerID: "B", now: now)
    }

    mutating func advance(_ seconds: Double) { now = now.addingTimeInterval(seconds) }

    static func wire(_ message: GameMessage) -> GameMessage {
        let envelope = WireEnvelope(gameID: UUID(), message: message)
        let data = try! Wire.encode(envelope)
        return try! Wire.decode(WireEnvelope.self, from: data).message
    }

    /// Delivers everything `update` wants to send from `a` to `b` (or the reverse), recursively.
    mutating func deliver(_ update: MatchUpdate?, fromA: Bool) {
        for message in update?.outgoing ?? [] {
            let reply: MatchUpdate
            if fromA { reply = b.receive(Table.wire(message), at: now) } else { reply = a.receive(Table.wire(message), at: now) }
            deliver(reply, fromA: !fromA)
        }
    }

    mutating func moveA(_ uci: String) { let u = a.playLocalMove(Move(uci: uci)!, at: now); XCTAssertNotNil(u); deliver(u, fromA: true) }
    mutating func moveB(_ uci: String) { let u = b.playLocalMove(Move(uci: uci)!, at: now); XCTAssertNotNil(u); deliver(u, fromA: false) }

    func assertInSync(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(a.game.moves, b.game.moves, file: file, line: line)
        XCTAssertEqual(a.result, b.result, file: file, line: line)
        XCTAssertEqual(a.chat, b.chat, file: file, line: line)
        XCTAssertEqual(a.drawOfferFrom, b.drawOfferFrom, file: file, line: line)
    }
}

final class MatchTests: XCTestCase {
    func testColorsAndTurns() {
        var t = Table()
        XCTAssertEqual(t.a.localColor, .white)
        XCTAssertEqual(t.b.localColor, .black)
        XCTAssertTrue(t.a.isLocalTurn)
        XCTAssertFalse(t.b.isLocalTurn)
        XCTAssertNil(t.b.playLocalMove(Move(uci: "e7e5")!, at: t.now), "not Black's turn")
        XCTAssertNil(t.a.playLocalMove(Move(uci: "e2e5")!, at: t.now), "illegal")
        t.moveA("e2e4")
        t.moveB("e7e5")
        t.assertInSync()
        XCTAssertEqual(t.a.game.sanMoves, ["e4", "e5"])
    }

    func testClockAndIncrement() {
        var t = Table()
        t.moveA("e2e4")  // no clock before White's first move
        XCTAssertEqual(t.a.clock?.remaining(.white, at: t.now), 60)
        XCTAssertEqual(t.b.clock?.running, .black)
        t.advance(5)
        t.moveB("e7e5")  // 60 - 5 + 2
        XCTAssertEqual(t.b.clock?.remaining(.black, at: t.now), 57)
        XCTAssertEqual(t.a.clock?.remaining(.black, at: t.now), 57)
        t.advance(10)
        XCTAssertEqual(t.a.clock?.remaining(.white, at: t.now), 50)
        t.moveA("g1f3")
        XCTAssertEqual(t.b.clock?.remaining(.white, at: t.now), 52)
    }

    func testFlagFall() {
        var t = Table()
        t.moveA("e2e4")
        t.moveB("e7e5")
        t.advance(30)
        XCTAssertNil(t.a.checkFlag(at: t.now))
        t.advance(31)
        XCTAssertNil(t.b.checkFlag(at: t.now), "only the clock's owner declares a flag")
        let update = t.a.checkFlag(at: t.now)
        XCTAssertNotNil(update)
        t.deliver(update, fromA: true)
        XCTAssertEqual(t.a.result, GameResult(winner: .black, reason: .timeout))
        t.assertInSync()
    }

    func testResignAndDrawAgreement() {
        var t = Table()
        t.moveA("e2e4")
        t.deliver(t.b.offerDraw(at: t.now), fromA: false)
        XCTAssertEqual(t.a.drawOfferFrom, .black)
        t.deliver(t.a.respondToDrawOffer(accept: false, at: t.now), fromA: true)
        XCTAssertNil(t.b.drawOfferFrom)

        t.deliver(t.b.offerDraw(at: t.now), fromA: false)
        t.deliver(t.a.respondToDrawOffer(accept: true, at: t.now), fromA: true)
        XCTAssertEqual(t.b.result, GameResult(winner: nil, reason: .agreement))
        t.assertInSync()

        var u = Table()
        u.deliver(u.b.resign(at: u.now), fromA: false)
        XCTAssertEqual(u.a.result, GameResult(winner: .white, reason: .resignation))
        u.assertInSync()
    }

    func testDrawOfferLapsesWhenRecipientMoves() {
        var t = Table()
        t.moveA("e2e4")
        t.deliver(t.a.offerDraw(at: t.now), fromA: true)
        XCTAssertEqual(t.b.drawOfferFrom, .white)
        t.moveB("e7e5")
        XCTAssertNil(t.a.drawOfferFrom)
        XCTAssertNil(t.b.drawOfferFrom)
    }

    func testTakebackAfterReply() {
        var t = Table()
        t.moveA("e2e4")
        t.moveB("e7e5")
        t.moveA("f1c4")
        t.moveB("b8c6")
        // White regrets Bc4 after Black already replied: both plies are undone.
        t.deliver(t.a.requestTakeback(at: t.now), fromA: true)
        XCTAssertEqual(t.b.takebackRequest?.requester, .white)
        t.deliver(t.b.respondToTakeback(accept: true, at: t.now), fromA: false)
        t.assertInSync()
        XCTAssertEqual(t.a.game.ply, 2)
        XCTAssertTrue(t.a.isLocalTurn)
        t.moveA("g1f3")
        t.assertInSync()
    }

    func testTakebackDeclinedAndImplicitDecline() {
        var t = Table()
        t.moveA("e2e4")
        t.deliver(t.a.requestTakeback(at: t.now), fromA: true)
        t.deliver(t.b.respondToTakeback(accept: false, at: t.now), fromA: false)
        XCTAssertNil(t.a.takebackRequest)
        XCTAssertEqual(t.a.game.ply, 1)

        t.deliver(t.a.requestTakeback(at: t.now), fromA: true)
        t.moveB("e7e5")  // moving instead of answering declines
        XCTAssertNil(t.a.takebackRequest)
        XCTAssertNil(t.b.takebackRequest)
        t.assertInSync()
    }

    func testTakebackCrossingAMove() {
        var t = Table()
        t.moveA("e2e4")
        t.moveB("e7e5")
        t.moveA("g1f3")
        t.moveB("b8c6")
        // White asks, but plays on before Black's acceptance arrives.
        let request = t.a.requestTakeback(at: t.now)
        t.deliver(request, fromA: true)
        let accept = t.b.respondToTakeback(accept: true, at: t.now)  // Black truncates to ply 2
        let whiteMove = t.a.playLocalMove(Move(uci: "f1c4")!, at: t.now)
        t.deliver(whiteMove, fromA: true)  // stale for Black, ignored
        t.deliver(accept, fromA: false)    // White follows the takeback
        t.assertInSync()
        XCTAssertEqual(t.a.game.ply, 2)
    }

    func testChat() {
        var t = Table()
        t.deliver(t.a.sendChat("  good luck!  ", at: t.now), fromA: true)
        XCTAssertNil(t.b.sendChat("   ", at: t.now))
        t.deliver(t.b.sendChat("you too", at: t.now), fromA: false)
        XCTAssertEqual(t.a.chat.map(\.text), ["good luck!", "you too"])
        t.assertInSync()
    }

    func testCheckmateEndsGameOnBothSides() {
        var t = Table()
        t.moveA("f2f3")
        t.moveB("e7e5")
        t.moveA("g2g4")
        t.moveB("d8h4")
        XCTAssertEqual(t.a.result, GameResult(winner: .black, reason: .checkmate))
        t.assertInSync()
        XCTAssertNil(t.a.clock?.running)
    }

    func testReconnectMergesLostMove() {
        var t = Table()
        t.moveA("e2e4")
        t.moveB("e7e5")
        t.advance(3)
        // White moves but the connection drops before Black receives it.
        _ = t.a.playLocalMove(Move(uci: "g1f3")!, at: t.now)
        _ = t.b.sendChat("hello?", at: t.now)  // also lost; the merge must bring it over
        t.advance(1)
        t.a.pauseClock(at: t.now)
        t.b.pauseClock(at: t.now)
        t.advance(100)  // time passes while disconnected; clocks are paused

        let snapA = t.a.snapshot(at: t.now)
        let snapB = t.b.snapshot(at: t.now)
        _ = t.a.receive(Table.wire(.sync(snapB)), at: t.now)
        _ = t.b.receive(Table.wire(.sync(snapA)), at: t.now)
        t.assertInSync()
        XCTAssertEqual(t.b.game.ply, 3)
        XCTAssertEqual(t.a.clock?.remaining(.white, at: t.now), t.b.clock?.remaining(.white, at: t.now))
        XCTAssertEqual(t.a.clock?.remaining(.black, at: t.now), t.b.clock?.remaining(.black, at: t.now))
        XCTAssertEqual(t.a.clock?.remaining(.white, at: t.now), 59)  // 60 - 3 + 2 increment
        // Black never saw move 3, so Black's own clock (authoritative for Black) never started again.
        XCTAssertEqual(t.b.clock?.remaining(.black, at: t.now), 62)  // 60 + 2 increment
        XCTAssertNil(t.a.clock?.running)
    }

    func testMergeKeepsResignationFromOtherSide() {
        var t = Table()
        t.moveA("e2e4")
        _ = t.b.resign(at: t.now)  // message lost
        let snapA = t.a.snapshot(at: t.now)
        let snapB = t.b.snapshot(at: t.now)
        _ = t.a.receive(.sync(snapB), at: t.now)
        _ = t.b.receive(.sync(snapA), at: t.now)
        t.assertInSync()
        XCTAssertEqual(t.a.result, GameResult(winner: .white, reason: .resignation))
    }

    func testSnapshotRoundTripAndPGN() throws {
        var t = Table()
        t.moveA("e2e4")
        t.moveB("c7c5")
        t.deliver(t.a.resign(at: t.now), fromA: true)
        let snapshot = t.a.snapshot(at: t.now)
        let decoded = try Wire.decode(MatchSnapshot.self, from: Wire.encode(snapshot))
        XCTAssertEqual(decoded, snapshot)
        let restored = try XCTUnwrap(Match(snapshot: decoded, localPlayerID: "B"))
        XCTAssertEqual(restored.localColor, .black)
        XCTAssertEqual(restored.game.sanMoves, ["e4", "c5"])
        XCTAssertNil(Match(snapshot: decoded, localPlayerID: "stranger"))

        let pgn = snapshot.pgn()
        XCTAssertTrue(pgn.contains("[White \"Alice\"]"))
        XCTAssertTrue(pgn.contains("[Result \"0-1\"]"))
        XCTAssertTrue(pgn.contains("[TimeControl \"60+2\"]"))
        XCTAssertTrue(pgn.contains("1. e4 c5 0-1"))
    }

    func testInvitationEncoding() throws {
        let challenge = Challenge(challenger: Table.alice, challengerColor: .black, timeControl: .unlimited)
        let envelope = InvitationEnvelope(.challenge(challenge))
        let decoded = try Wire.decode(InvitationEnvelope.self, from: Wire.encode(envelope))
        XCTAssertEqual(decoded, envelope)
        XCTAssertLessThan(try Wire.encode(envelope).count, 1_000)
    }

    func testUnlimitedHasNoClock() {
        var t = Table(timeControl: .unlimited)
        XCTAssertNil(t.a.clock)
        t.moveA("d2d4")
        t.moveB("d7d5")
        t.assertInSync()
        XCTAssertEqual(TimeControl.unlimited.pgnTag, "-")
        XCTAssertEqual(TimeControl(initialSeconds: 300, incrementSeconds: 3).label, "5+3")
    }
}
