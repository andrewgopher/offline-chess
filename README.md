# Offline Chess

A native macOS chess app for two Macs sitting next to each other with **no internet
and no Wi-Fi network**, for example on a plane.

The Macs talk directly over **peer-to-peer Wi-Fi**, the same radio link AirDrop uses
(Apple's MultipeerConnectivity / AWDL). The Wi-Fi radio has to be **on**, but it doesn't
need to join any network. Airplane mode allows Wi-Fi to be switched back on.

## Features

- Automatic discovery of nearby Macs running the app: no pairing codes or IP addresses
- Challenge a player; the challenger picks **White / Black / Random** and a time control.
  The other player gets an Accept/Decline prompt.
- Full rules: legal-move highlighting, castling, en passant, promotion, check, checkmate,
  stalemate, and automatic draws (threefold repetition, 50-move rule, insufficient material)
- **Chess clock** with increments (presets from 1+0 to 30+20, a custom time control, or unlimited).
  Clocks start after White's first move and pause automatically if the connection drops.
- **Draw offers**, **takeback requests**, **resign**, and **rematch** (colors swapped)
- **Chat** next to the board
- Games **auto-save**. If the connection drops, the app reconnects on its own; unfinished
  games can be resumed later, even after quitting the app.
- Move list with click-to-review, captured pieces and material count, board flip, sounds
- **PGN export** (save to a file or copy to the clipboard) for every saved game

## Build

Requirements: macOS 13 Ventura or later, and Xcode 15+ **or** just the Command Line Tools
(`xcode-select --install`).

```sh
./scripts/build-app.sh
open dist/OfflineChess.app
```

This produces a universal (Apple silicon + Intel) `dist/OfflineChess.app` and
`dist/OfflineChess.zip`, ad-hoc signed. You can also open `Package.swift` in Xcode and run
the `OfflineChess` scheme.

Every push also builds the app on GitHub Actions; download `OfflineChess-app` from the
workflow run's artifacts.

### Getting it onto the second Mac

Do this **before the flight**, or on the plane over AirDrop (AirDrop works offline too).

- **Easiest:** clone the repo and run `./scripts/build-app.sh` on each Mac.
- **Or copy** `OfflineChess.zip` to the other Mac. The app isn't notarized, so macOS blocks it
  the first time. Either run `xattr -dr com.apple.quarantine /path/to/OfflineChess.app`,
  or try to open it, then go to **System Settings → Privacy & Security** and click **Open Anyway**.

### First launch

Launch the app once on each Mac before you need it. macOS will ask:

- **"Allow Offline Chess to find devices on local networks?"** Click **Allow**. Without it, the
  Macs can't see each other. You can change it later in System Settings → Privacy & Security → Local Network.
- If the firewall asks whether to accept incoming connections, click **Allow**.

## Playing on a plane

1. Turn Wi-Fi **on** on both Macs (Control Center → Wi-Fi). Don't join the in-flight network.
2. Open Offline Chess on both. Each Mac shows up under **Nearby players** on the other.
3. Click **Challenge…**, pick your color and time control, and send it. The other player accepts.
4. Play by clicking a piece and then its destination, or by dragging it.

If the connection drops mid-game (lid closed, out of range…), both clocks pause and the app keeps
trying to reconnect. If one player goes back to the lobby, the game stays saved under
**Unfinished games**; click **Resume** when you're both ready.

## Project layout

```
Package.swift
Sources/ChessCore/        Pure-Swift, Foundation-only, unit-tested
  Position.swift            board, FEN, legal move generation, SAN, material
  Game.swift                move history, game-over detection, results
  Clock.swift               time controls and a deterministic two-sided clock
  Protocol.swift            wire messages, invitations, snapshots, PGN export
  Match.swift               the per-Mac game state machine (moves, clocks, offers, sync/merge)
  PGN.swift
Sources/OfflineChess/     macOS app (SwiftUI)
  PeerService.swift         MultipeerConnectivity discovery + one encrypted 1:1 link
  AppModel.swift            app state; glues UI ⇄ Match ⇄ PeerService; persistence
  LobbyView / ChallengeViews / GameView / BoardView
Tests/ChessCoreTests/     perft move-generation tests, SAN, outcomes, two-Mac protocol simulations
Support/Info.plist        bundle metadata, Local Network usage text and Bonjour service types
scripts/build-app.sh      builds and packages the .app
```

### How the two Macs stay in sync

- Both Macs run the same `Match` state machine. Each player is authoritative for **their own
  moves and their own clock**: a move message carries the mover's remaining time, and only the
  owner of a clock can declare that it ran out, so the two sides never disagree about a flag.
- Every received move is validated against the rules and tagged with its ply number. Stale
  messages, such as a move that crossed an accepted takeback, are ignored.
- On every (re)connect the two Macs exchange a full snapshot and run the same deterministic
  merge: the longer move history wins when one extends the other, each side keeps its own clock,
  results like resignations carry over, and chat is unioned. This recovers a move or a
  resignation that was sent just as the connection dropped.
- Saved games live in `~/Library/Application Support/OfflineChess/Games/` as JSON.

## Tests

```sh
swift test -c release
```

Needs a full Xcode install. The Command Line Tools alone don't ship XCTest.
