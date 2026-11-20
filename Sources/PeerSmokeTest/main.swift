// Headless end-to-end check of PeerKit + the match protocol, used in CI.
//
// Run two copies on the same Mac (or two Macs):
//     PeerSmokeTest guest &
//     PeerSmokeTest host
// They discover each other with the same PeerService the app uses, the host sends a
// challenge, the guest accepts, and they play Fool's Mate over the real link.
// Exit status 0 means both the transport and the protocol worked.

import ChessCore
import Foundation
import MultipeerConnectivity
import PeerKit

setvbuf(stdout, nil, _IOLBF, 0)

let role = CommandLine.arguments.dropFirst().first ?? "host"
let isHost = role == "host"
let me = PlayerInfo(id: isHost ? "smoke-host" : "smoke-guest", name: isHost ? "Smoke Host" : "Smoke Guest")
let script: [String] = isHost ? ["f2f3", "g2g4"] : ["e7e5", "d8h4"]

func say(_ text: String) {
    print("[\(role)] \(text)")
}

final class Runner: PeerServiceDelegate {
    let service: PeerService
    var match: Match?
    var pendingChallenge: Challenge?
    var pendingOpponent: PlayerInfo?
    var invited = false
    var nextScriptIndex = 0
    var finished = false
    var exitCode: Int32?

    init() {
        service = PeerService(displayName: me.name, playerID: me.id)
        service.delegate = self
    }

    func start() {
        service.start()
        say("advertising and browsing as \(me.name)")
    }

    func peerService(_ service: PeerService, didUpdateNearby peers: [DiscoveredPeer]) {
        say("nearby: \(peers.map(\.name))")
        guard isHost, !invited, let guest = peers.first(where: { $0.playerID == "smoke-guest" }) else { return }
        invited = true
        let challenge = Challenge(challenger: me, challengerColor: .white,
                                  timeControl: TimeControl(initialSeconds: 300, incrementSeconds: 2))
        pendingChallenge = challenge
        pendingOpponent = PlayerInfo(id: guest.playerID, name: guest.name)
        guard let data = try? Wire.encode(InvitationEnvelope(.challenge(challenge))) else { return fail("encode") }
        say("inviting \(guest.name)")
        service.invite(guest.peerID, context: data, timeout: 30)
    }

    func peerService(_ service: PeerService, didReceiveInvitation context: Data?, from peerID: MCPeerID,
                     reply: @escaping (Bool) -> Void) {
        guard !isHost, let context = context,
              let envelope = try? Wire.decode(InvitationEnvelope.self, from: context),
              case .challenge(let challenge) = envelope.invitation
        else {
            reply(false)
            return
        }
        say("accepting challenge from \(challenge.challenger.name)")
        match = Match(challenge: challenge, accepter: me, localPlayerID: me.id, now: Date())
        reply(true)
    }

    func peerService(_ service: PeerService, linkDidChange state: PeerLinkState, peer: MCPeerID) {
        say("link: \(state)")
        switch state {
        case .connected:
            if isHost, let challenge = pendingChallenge, let opponent = pendingOpponent {
                match = Match(challenge: challenge, accepter: opponent, localPlayerID: me.id, now: Date())
            }
            guard let current = match else { return fail("connected without a game") }
            send(.sync(current.snapshot(at: Date())))
            playIfMyTurn()
        case .disconnected:
            if !finished { fail("link dropped before the game finished") }
        case .connecting:
            break
        }
    }

    func peerService(_ service: PeerService, didReceive data: Data, from peerID: MCPeerID) {
        guard var current = match,
              let envelope = try? Wire.decode(WireEnvelope.self, from: data),
              envelope.gameID == current.gameID
        else { return }
        let update = current.receive(envelope.message, at: Date())
        match = current
        for event in update.events { say("event: \(event)") }
        for message in update.outgoing { send(message) }
        checkFinished()
        playIfMyTurn()
    }

    func playIfMyTurn() {
        guard var current = match, current.isLocalTurn, nextScriptIndex < script.count else { return }
        guard let move = Move(uci: script[nextScriptIndex]) else { return fail("bad script move") }
        nextScriptIndex += 1
        guard let update = current.playLocalMove(move, at: Date()) else { return fail("could not play \(move)") }
        match = current
        say("played \(current.game.sanMoves.last ?? move.uci)")
        for message in update.outgoing { send(message) }
        checkFinished()
    }

    func checkFinished() {
        guard !finished, let current = match, let result = current.result else { return }
        finished = true
        let moves = current.game.sanMoves.joined(separator: " ")
        say("game over: \(result.summary(white: current.white.name, black: current.black.name)) Moves: \(moves)")
        guard result == GameResult(winner: .black, reason: .checkmate), moves == "f3 e5 g4 Qh4#" else {
            return fail("unexpected result")
        }
        // Leave time for the final message to reach the other side before quitting.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self.exitCode = 0 }
    }

    func send(_ message: GameMessage) {
        guard let current = match,
              let data = try? Wire.encode(WireEnvelope(gameID: current.gameID, message: message))
        else { return }
        if !service.send(data) { say("send failed: \(message)") }
    }

    func fail(_ reason: String) {
        say("FAIL: \(reason)")
        exitCode = 1
    }
}

let runner = Runner()
runner.start()
let deadline = Date().addingTimeInterval(90)
while runner.exitCode == nil && Date() < deadline {
    _ = RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.2))
}
if runner.exitCode == nil { say("FAIL: timed out") }
let code = runner.exitCode ?? 1
runner.service.disconnect()
say(code == 0 ? "PASS" : "exiting with failure")
exit(code)
