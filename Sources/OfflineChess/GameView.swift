import ChessCore
import SwiftUI

struct GameView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        if let match = model.match {
            GameLayout(match: match)
        } else {
            VStack(spacing: 12) {
                ProgressView()
                Button("Back to Lobby") { model.leaveGame() }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct GameLayout: View {
    @EnvironmentObject private var model: AppModel
    let match: Match

    private var bottomColor: PieceColor { model.boardFlipped ? match.localColor.opposite : match.localColor }
    private var displayedPosition: Position { match.game.positions[model.displayedPly] }
    private var displayedLastMove: Move? {
        let ply = model.displayedPly
        return ply > 0 ? match.game.moves[ply - 1] : nil
    }

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(spacing: 10) {
                PlayerBar(match: match, color: bottomColor.opposite, position: displayedPosition)
                BoardView(
                    position: displayedPosition,
                    bottomColor: bottomColor,
                    lastMove: displayedLastMove,
                    movableColor: model.canMove ? match.localColor : nil,
                    onMove: { model.play($0) }
                )
                PlayerBar(match: match, color: bottomColor, position: displayedPosition)
            }
            .frame(minWidth: 460, maxWidth: .infinity, maxHeight: .infinity)

            SidePanel(match: match)
                .frame(width: 330)
        }
        .padding(20)
    }
}

// MARK: - Player bar & clock

private struct PlayerBar: View {
    @EnvironmentObject private var model: AppModel
    let match: Match
    let color: PieceColor
    let position: Position

    private var isLocal: Bool { color == match.localColor }
    private var isTurn: Bool { !match.isOver && match.sideToMove == color }

    var body: some View {
        let captured = position.missingPieces(of: color.opposite)
        let advantage = position.material(for: color) - position.material(for: color.opposite)
        HStack(spacing: 10) {
            Circle()
                .fill(color == .white ? Color.white : Color.black)
                .overlay(Circle().stroke(Color.secondary, lineWidth: 1))
                .frame(width: 14, height: 14)
            Text(match.player(color).name)
                .font(.headline)
                .lineLimit(1)
            if isLocal {
                Text("(you)").foregroundColor(.secondary)
            }
            HStack(spacing: -4) {
                ForEach(Array(captured.enumerated()), id: \.offset) { _, piece in
                    PieceView(piece: piece, size: 18)
                }
            }
            if advantage > 0 {
                Text("+\(advantage)")
                    .font(.caption.bold())
                    .foregroundColor(.secondary)
            }
            Spacer()
            if let clock = match.clock {
                ClockView(clock: clock, color: color, isTurn: isTurn)
            } else if isTurn {
                Text("to move")
                    .font(.caption.bold())
                    .foregroundColor(.accentColor)
            }
        }
        .frame(height: 34)
    }
}

private struct ClockView: View {
    let clock: ChessClock
    let color: PieceColor
    let isTurn: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.1, paused: clock.running != color)) { context in
            let remaining = max(0, clock.remaining(color, at: context.date))
            let running = clock.running == color
            let low = remaining < 20
            Text(ClockView.format(remaining))
                .font(.system(size: 22, weight: .semibold, design: .monospaced))
                .padding(.horizontal, 12)
                .padding(.vertical, 3)
                .foregroundColor(running ? .white : .primary)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(running ? (low ? Color.red : Color.accentColor) : Color.secondary.opacity(isTurn ? 0.3 : 0.12))
                )
        }
    }

    static func format(_ seconds: Double) -> String {
        if seconds < 10 {
            return String(format: "0:%04.1f", floor(seconds * 10) / 10)
        }
        let total = Int(seconds.rounded(.down))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, secs) }
        return String(format: "%d:%02d", minutes, secs)
    }
}

// MARK: - Side panel

private struct SidePanel: View {
    @EnvironmentObject private var model: AppModel
    let match: Match

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button {
                    model.leaveGame()
                } label: {
                    Label("Lobby", systemImage: "chevron.left")
                }
                Spacer()
                Text(match.timeControl.displayName)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            StatusCard(match: match)
            PromptsView(match: match)
            MoveListView(match: match)
                .frame(maxHeight: .infinity)
            NavigationButtons(match: match)
            ActionButtons(match: match)
            Divider()
            ChatView(match: match)
                .frame(height: 190)
        }
    }
}

private struct StatusCard: View {
    @EnvironmentObject private var model: AppModel
    let match: Match

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                Text(title).font(.headline)
            }
            if let detail = detail {
                Text(detail)
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if showsResumeButton {
                Button("Ask \(match.opponent.name) to Resume") { model.askToResume() }
                    .disabled(model.nearbyPlayer(match.opponent.id) == nil || model.outgoingInvite != nil)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(tint.opacity(0.15)))
    }

    private var opponentName: String { match.opponent.name }
    private var opponentNearby: Bool { model.nearbyPlayer(match.opponent.id) != nil }

    private var showsResumeButton: Bool {
        !match.isOver && model.linkStatus == .waiting
    }

    private var title: String {
        if let result = match.result {
            return result.summary(white: match.white.name, black: match.black.name)
        }
        switch model.linkStatus {
        case .connecting: return "Connecting to \(opponentName)…"
        case .reconnecting: return "Connection lost. Reconnecting…"
        case .waiting: return model.opponentLeftOnPurpose ? "\(opponentName) left the game" : "\(opponentName) isn't responding"
        case .offline: return "Not connected"
        case .connected:
            if match.isLocalTurn { return match.game.position.isInCheck ? "Check! Your move" : "Your move" }
            return "\(opponentName) is thinking…"
        }
    }

    private var detail: String? {
        if match.isOver {
            switch model.linkStatus {
            case .connected: return nil
            case .offline: return "Reviewing a saved game."
            default: return "\(opponentName) has disconnected."
            }
        }
        switch model.linkStatus {
        case .connecting:
            return "Waiting for \(opponentName)'s Mac to answer."
        case .reconnecting:
            return opponentNearby
                ? "Clocks are paused. Trying to reach \(opponentName) again…"
                : "Clocks are paused. Waiting for \(opponentName) to come back in range with Offline Chess open."
        case .waiting:
            return "The game is saved and the clocks are paused. You can resume whenever you're both ready."
        case .offline, .connected:
            return nil
        }
    }

    private var icon: String {
        if match.isOver { return "flag.checkered" }
        switch model.linkStatus {
        case .connected: return match.isLocalTurn ? "hand.point.right.fill" : "hourglass"
        case .connecting, .reconnecting: return "antenna.radiowaves.left.and.right"
        case .waiting, .offline: return "pause.circle"
        }
    }

    private var tint: Color {
        if match.isOver { return .purple }
        switch model.linkStatus {
        case .connected: return match.isLocalTurn ? .green : .secondary
        case .connecting, .reconnecting, .waiting: return .orange
        case .offline: return .secondary
        }
    }
}

/// Pending offers from the opponent (and our own pending requests).
private struct PromptsView: View {
    @EnvironmentObject private var model: AppModel
    let match: Match

    var body: some View {
        VStack(spacing: 8) {
            if match.drawOfferFrom == match.opponentColor {
                PromptRow(text: "\(match.opponent.name) offers a draw.",
                          accept: { model.respondToDraw(accept: true) },
                          decline: { model.respondToDraw(accept: false) })
            }
            if let request = match.takebackRequest, request.requester == match.opponentColor {
                PromptRow(text: "\(match.opponent.name) asks to take back their last move.",
                          accept: { model.respondToTakeback(accept: true) },
                          decline: { model.respondToTakeback(accept: false) })
            }
            if model.rematchOfferIn != nil {
                PromptRow(text: "\(match.opponent.name) wants a rematch (colors swapped).",
                          accept: { model.respondToRematch(accept: true) },
                          decline: { model.respondToRematch(accept: false) })
            }
            if match.drawOfferFrom == match.localColor {
                InfoRow(text: "You offered a draw.")
            }
            if let request = match.takebackRequest, request.requester == match.localColor {
                InfoRow(text: "Takeback requested. Waiting for \(match.opponent.name)…")
            }
            if model.rematchOfferOut != nil {
                InfoRow(text: "Rematch offered. Waiting for \(match.opponent.name)…")
            }
        }
    }
}

private struct PromptRow: View {
    let text: String
    let accept: () -> Void
    let decline: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(text).font(.callout.bold()).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Decline", action: decline)
                Button("Accept", action: accept)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.15)))
    }
}

private struct InfoRow: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Moves

private struct MoveListView: View {
    @EnvironmentObject private var model: AppModel
    let match: Match

    private var sanMoves: [String] { match.game.sanMoves }
    private var rowCount: Int { (sanMoves.count + 1) / 2 }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    if sanMoves.isEmpty {
                        Text(match.localColor == .white ? "You have White: make the first move." : "Waiting for White's first move.")
                            .foregroundColor(.secondary)
                            .padding(6)
                    }
                    ForEach(0..<rowCount, id: \.self) { row in
                        HStack(spacing: 4) {
                            Text("\(row + 1).")
                                .foregroundColor(.secondary)
                                .frame(width: 36, alignment: .trailing)
                            moveCell(row * 2)
                            moveCell(row * 2 + 1)
                            Spacer(minLength: 0)
                        }
                        .font(.system(.body, design: .monospaced))
                        .id(row)
                    }
                }
                .padding(6)
            }
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.08)))
            .onChange(of: sanMoves.count) { _ in
                if rowCount > 0 { proxy.scrollTo(rowCount - 1, anchor: .bottom) }
            }
            .onAppear {
                if rowCount > 0 { proxy.scrollTo(rowCount - 1, anchor: .bottom) }
            }
        }
    }

    @ViewBuilder
    private func moveCell(_ index: Int) -> some View {
        if index < sanMoves.count {
            let isShown = model.displayedPly == index + 1
            Button {
                model.showPly(index + 1)
            } label: {
                Text(sanMoves[index])
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .frame(width: 96, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 4).fill(isShown ? Color.accentColor.opacity(0.3) : Color.clear))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            Color.clear.frame(width: 96, height: 1)
        }
    }
}

private struct NavigationButtons: View {
    @EnvironmentObject private var model: AppModel
    let match: Match

    var body: some View {
        let ply = model.displayedPly
        let last = match.game.ply
        HStack {
            Button { model.showPly(0) } label: { Image(systemName: "backward.end.fill") }
                .disabled(ply == 0)
                .help("First position")
            Button { model.showPly(ply - 1) } label: { Image(systemName: "chevron.left") }
                .disabled(ply == 0)
                .help("Previous move")
            Button { model.showPly(ply + 1) } label: { Image(systemName: "chevron.right") }
                .disabled(ply >= last)
                .help("Next move")
            Button { model.showLive() } label: { Image(systemName: "forward.end.fill") }
                .disabled(ply >= last)
                .help("Latest position")
            Spacer()
            if model.viewPly != nil {
                Text("Viewing move \(ply) of \(last)")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
            Button { model.boardFlipped.toggle() } label: { Image(systemName: "arrow.up.arrow.down") }
                .help("Flip board")
        }
    }
}

private struct ActionButtons: View {
    @EnvironmentObject private var model: AppModel
    let match: Match
    @State private var confirmingResign = false

    var body: some View {
        HStack {
            if match.isOver {
                if model.linkStatus == .connected {
                    Button(model.rematchOfferIn != nil ? "Accept Rematch" : "Rematch") { model.offerRematch() }
                        .disabled(model.rematchOfferOut != nil)
                }
                Spacer()
                Button("Export PGN…") { model.exportPGN(match.snapshot(at: Date())) }
                Button("Copy PGN") { model.copyPGN(match.snapshot(at: Date())) }
            } else {
                Button("Offer Draw") { model.offerDraw() }
                    .disabled(!model.canAct || !match.canOfferDraw)
                Button("Takeback") { model.requestTakeback() }
                    .disabled(!model.canAct || !match.canRequestTakeback)
                    .help("Ask to undo your last move")
                Spacer()
                Button("Resign") { confirmingResign = true }
                    .disabled(!model.canAct)
            }
        }
        .confirmationDialog("Resign this game?", isPresented: $confirmingResign) {
            Button("Resign", role: .destructive) { model.resign() }
            Button("Cancel", role: .cancel) {}
        }
    }
}

// MARK: - Chat

private struct ChatView: View {
    @EnvironmentObject private var model: AppModel
    let match: Match
    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Chat").font(.headline)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(match.chat) { message in
                            ChatBubble(message: message, isMine: message.senderID == model.playerID,
                                       senderName: message.senderID == match.white.id ? match.white.name : match.black.name)
                                .id(message.id)
                        }
                    }
                    .padding(6)
                }
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.08)))
                .onChange(of: match.chat.count) { _ in
                    if let last = match.chat.last { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
            HStack {
                TextField(model.linkStatus == .connected ? "Message \(match.opponent.name)" : "Chat is available while connected",
                          text: $draft)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(send)
                Button("Send", action: send)
                    .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty || model.linkStatus != .connected)
            }
            .disabled(model.linkStatus != .connected)
        }
    }

    private func send() {
        guard model.linkStatus == .connected else { return }
        model.sendChat(draft)
        draft = ""
    }
}

private struct ChatBubble: View {
    let message: ChatMessage
    let isMine: Bool
    let senderName: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(isMine ? "You" : senderName)
                .font(.caption.bold())
                .foregroundColor(isMine ? .accentColor : .primary)
            Text(message.text)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
