import XCTest
import ChessCore

final class PerftTests: XCTestCase {
    private func perft(_ position: Position, _ depth: Int) -> Int {
        if depth == 0 { return 1 }
        let moves = position.legalMoves()
        if depth == 1 { return moves.count }
        return moves.reduce(0) { $0 + perft(position.applying($1), depth - 1) }
    }

    private func position(_ fen: String) -> Position {
        guard let position = Position(fen: fen) else {
            XCTFail("Bad FEN \(fen)")
            return .standard
        }
        return position
    }

    func testStartingPosition() {
        XCTAssertEqual(perft(.standard, 1), 20)
        XCTAssertEqual(perft(.standard, 2), 400)
        XCTAssertEqual(perft(.standard, 3), 8_902)
        XCTAssertEqual(perft(.standard, 4), 197_281)
    }

    func testKiwipete() {
        let p = position("r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1")
        XCTAssertEqual(perft(p, 1), 48)
        XCTAssertEqual(perft(p, 2), 2_039)
        XCTAssertEqual(perft(p, 3), 97_862)
    }

    func testEndgameWithEnPassantPins() {
        let p = position("8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1")
        XCTAssertEqual(perft(p, 1), 14)
        XCTAssertEqual(perft(p, 2), 191)
        XCTAssertEqual(perft(p, 3), 2_812)
        XCTAssertEqual(perft(p, 4), 43_238)
    }

    func testPromotionsAndCastlingRights() {
        let p = position("r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1")
        XCTAssertEqual(perft(p, 1), 6)
        XCTAssertEqual(perft(p, 2), 264)
        XCTAssertEqual(perft(p, 3), 9_467)
    }

    func testPosition5() {
        let p = position("rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8")
        XCTAssertEqual(perft(p, 1), 44)
        XCTAssertEqual(perft(p, 2), 1_486)
        XCTAssertEqual(perft(p, 3), 62_379)
    }
}

final class NotationTests: XCTestCase {
    private func san(_ fen: String, _ uci: String) -> String {
        let position = Position(fen: fen)!
        return position.san(for: Move(uci: uci)!)
    }

    func testFENRoundTrip() {
        let fens = [
            Position.startingFEN,
            "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1",
            "4k3/8/8/3pP3/8/8/8/4K3 w - d6 0 7",
        ]
        for fen in fens {
            XCTAssertEqual(Position(fen: fen)?.fen, fen)
        }
        XCTAssertNil(Position(fen: "not a fen"))
        XCTAssertNil(Position(fen: "8/8/8/8/8/8/8 w - - 0 1"))
    }

    func testBasicSAN() {
        XCTAssertEqual(san(Position.startingFEN, "e2e4"), "e4")
        XCTAssertEqual(san(Position.startingFEN, "g1f3"), "Nf3")
    }

    func testDisambiguation() {
        XCTAssertEqual(san("7k/8/8/8/8/8/8/N1N4K w - - 0 1", "a1b3"), "Nab3")
        XCTAssertEqual(san("7k/8/8/8/8/8/8/N1N4K w - - 0 1", "c1b3"), "Ncb3")
        XCTAssertEqual(san("7k/8/8/R7/8/8/8/R6K w - - 0 1", "a1a3"), "R1a3")
        XCTAssertEqual(san("7k/8/8/R7/8/8/8/R6K w - - 0 1", "a5a3"), "R5a3")
    }

    func testCastlingPromotionEnPassant() {
        XCTAssertEqual(san("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1", "e1g1"), "O-O")
        XCTAssertEqual(san("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1", "e1c1"), "O-O-O")
        XCTAssertEqual(san("7k/P7/8/8/8/8/8/K7 w - - 0 1", "a7a8q"), "a8=Q+")
        XCTAssertEqual(san("7k/P7/8/8/8/8/8/K7 w - - 0 1", "a7a8n"), "a8=N")
        XCTAssertEqual(san("4k3/8/8/3pP3/8/8/8/4K3 w - d6 0 1", "e5d6"), "exd6")
    }

    func testCheckmateSuffixAndParsing() {
        var game = ChessGame()
        for text in ["f3", "e5", "g4", "Qh4#"] {
            guard let move = game.position.move(fromSAN: text) else { return XCTFail("Could not parse \(text)") }
            XCTAssertTrue(game.play(move))
        }
        XCTAssertEqual(game.sanMoves, ["f3", "e5", "g4", "Qh4#"])
        XCTAssertNotNil(Position.standard.move(fromSAN: "Nf3+"))  // tolerant of stray suffixes
        XCTAssertNil(Position.standard.move(fromSAN: "Ke2"))
    }

    func testPGNExport() {
        let pgn = PGN.render(tags: [("White", "A \"B\""), ("Result", "*")], sanMoves: ["e4", "e5", "Nf3"], result: "*")
        XCTAssertTrue(pgn.contains("[White \"A \\\"B\\\"\"]"))
        XCTAssertTrue(pgn.contains("1. e4 e5 2. Nf3 *"))
    }
}

final class GameOutcomeTests: XCTestCase {
    private func play(_ uciMoves: [String]) -> ChessGame {
        guard let game = ChessGame(uciMoves: uciMoves) else {
            XCTFail("Illegal move sequence")
            return ChessGame()
        }
        return game
    }

    func testFoolsMate() {
        let game = play(["f2f3", "e7e5", "g2g4", "d8h4"])
        XCTAssertEqual(game.outcome, GameResult(winner: .black, reason: .checkmate))
    }

    func testStalemate() {
        let game = ChessGame(initialPosition: Position(fen: "7k/5Q2/6K1/8/8/8/8/8 b - - 0 1")!)
        XCTAssertEqual(game.outcome, GameResult(winner: nil, reason: .stalemate))
    }

    func testThreefoldRepetition() {
        let shuffle = ["g1f3", "g8f6", "f3g1", "f6g8"]
        let twice = play(shuffle)
        XCTAssertNil(twice.outcome)
        let thrice = play(shuffle + shuffle)
        XCTAssertEqual(thrice.outcome, GameResult(winner: nil, reason: .threefoldRepetition))
    }

    func testInsufficientMaterial() {
        XCTAssertTrue(Position(fen: "8/8/4k3/8/8/3K4/8/8 w - - 0 1")!.isInsufficientMaterial)
        XCTAssertTrue(Position(fen: "8/8/4k3/8/8/3KB3/8/8 w - - 0 1")!.isInsufficientMaterial)
        XCTAssertTrue(Position(fen: "8/8/4k3/8/8/3KN3/8/8 w - - 0 1")!.isInsufficientMaterial)
        XCTAssertFalse(Position(fen: "8/8/4k3/8/8/2NKN3/8/8 w - - 0 1")!.isInsufficientMaterial)
        XCTAssertFalse(Position(fen: "8/8/4k3/8/8/3K4/4P3/8 w - - 0 1")!.isInsufficientMaterial)
        XCTAssertFalse(Position(fen: "8/8/4k3/8/8/3KB3/8/8 w - - 0 1")!.canPossiblyMate(.white))
        XCTAssertTrue(Position(fen: "8/8/4k3/8/8/3KR3/8/8 w - - 0 1")!.canPossiblyMate(.white))
    }

    func testFiftyMoveRule() {
        var game = ChessGame(initialPosition: Position(fen: "4k3/8/8/8/8/8/8/R3K3 w - - 99 80")!)
        XCTAssertNil(game.outcome)
        XCTAssertTrue(game.play(Move(uci: "a1a2")!))
        XCTAssertEqual(game.outcome, GameResult(winner: nil, reason: .fiftyMoveRule))
    }

    func testTruncate() {
        var game = play(["e2e4", "e7e5", "g1f3"])
        game.truncate(toPly: 1)
        XCTAssertEqual(game.ply, 1)
        XCTAssertEqual(game.sanMoves, ["e4"])
        XCTAssertEqual(game.positions.count, 2)
        XCTAssertEqual(game.position.sideToMove, .black)
        XCTAssertTrue(game.play(Move(uci: "c7c5")!))
    }

    func testMaterialAndMissingPieces() {
        let game = play(["e2e4", "d7d5", "e4d5"])
        XCTAssertEqual(game.position.material(for: .white) - game.position.material(for: .black), 1)
        XCTAssertEqual(game.position.missingPieces(of: .black), [Piece(.black, .pawn)])
        XCTAssertEqual(game.position.missingPieces(of: .white), [])
    }
}
