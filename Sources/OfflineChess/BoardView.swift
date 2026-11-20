import ChessCore
import SwiftUI

enum BoardColors {
    static let light = Color(red: 0.941, green: 0.851, blue: 0.710)
    static let dark = Color(red: 0.710, green: 0.533, blue: 0.388)
    static let lastMove = Color(red: 0.80, green: 0.82, blue: 0.25).opacity(0.55)
    static let selected = Color(red: 0.08, green: 0.47, blue: 0.20).opacity(0.5)
    static let hint = Color.black.opacity(0.22)
}

/// Renders a chess piece from Unicode glyphs: white pieces are a white-filled solid glyph
/// under a black outline glyph; black pieces are a dark solid glyph.
struct PieceView: View {
    let piece: Piece
    let size: CGFloat

    var body: some View {
        ZStack {
            Text(piece.solidGlyph)
                .foregroundColor(piece.color == .white ? .white : Color(white: 0.1))
            if piece.color == .white {
                Text(piece.outlineGlyph)
                    .foregroundColor(.black)
            }
        }
        .font(.custom("Apple Symbols", size: size))
        .shadow(color: .black.opacity(0.3), radius: 1, x: 0, y: 1)
        .allowsHitTesting(false)
    }
}

private struct PromotionRequest: Equatable {
    let from: Square
    let to: Square
}

struct BoardView: View {
    let position: Position
    /// The color shown at the bottom.
    let bottomColor: PieceColor
    let lastMove: Move?
    /// The side the user may move right now, or nil when the board is read-only.
    let movableColor: PieceColor?
    let onMove: (Move) -> Void

    @State private var selected: Square?
    @State private var dragFrom: Square?
    @State private var dragLocation: CGPoint?
    @State private var selectedByThisPress = false
    @State private var pressStarted = false
    @State private var promotion: PromotionRequest?

    private var canInteract: Bool {
        guard let color = movableColor else { return false }
        return position.sideToMove == color
    }

    var body: some View {
        GeometryReader { geometry in
            let side = floor(min(geometry.size.width, geometry.size.height))
            let squareSize = side / 8
            ZStack(alignment: .topLeading) {
                ZStack(alignment: .topLeading) {
                    squares(squareSize)
                    pieces(squareSize)
                }
                // Children are placed with .offset, which doesn't affect layout, so size explicitly.
                .frame(width: side, height: side, alignment: .topLeading)
                .contentShape(Rectangle())
                .gesture(boardGesture(squareSize))

                if let dragFrom = dragFrom, let location = dragLocation, let piece = position[dragFrom] {
                    PieceView(piece: piece, size: squareSize * 0.9)
                        .frame(width: squareSize, height: squareSize)
                        .position(location)
                }

                if let request = promotion {
                    promotionPicker(request, squareSize: squareSize, side: side)
                }
            }
            .frame(width: side, height: side)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }
        .aspectRatio(1, contentMode: .fit)
        .onChange(of: position) { _ in
            selected = nil
            promotion = nil
            dragFrom = nil
            dragLocation = nil
        }
        .onChange(of: movableColor) { _ in
            selected = nil
            promotion = nil
        }
    }

    // MARK: - Geometry

    private func column(_ square: Square) -> Int { bottomColor == .white ? square.file : 7 - square.file }
    private func row(_ square: Square) -> Int { bottomColor == .white ? 7 - square.rank : square.rank }

    private func origin(_ square: Square, _ size: CGFloat) -> CGPoint {
        CGPoint(x: CGFloat(column(square)) * size, y: CGFloat(row(square)) * size)
    }

    private func square(at point: CGPoint, _ size: CGFloat) -> Square? {
        let col = Int(floor(point.x / size))
        let row = Int(floor(point.y / size))
        guard (0..<8).contains(col), (0..<8).contains(row) else { return nil }
        let file = bottomColor == .white ? col : 7 - col
        let rank = bottomColor == .white ? 7 - row : row
        return Square(file: file, rank: rank)
    }

    // MARK: - Layers

    private var legalTargets: [Move] {
        guard canInteract, let from = selected ?? dragFrom else { return [] }
        return position.legalMoves(from: from)
    }

    private var checkedKing: Square? {
        position.isInCheck ? position.kingSquare(position.sideToMove) : nil
    }

    private func squares(_ size: CGFloat) -> some View {
        let targets = Set(legalTargets.map(\.to))
        let checked = checkedKing
        return ForEach(Square.all, id: \.self) { square in
            SquareView(
                square: square,
                size: size,
                isLastMove: lastMove.map { $0.from == square || $0.to == square } ?? false,
                isSelected: square == (selected ?? dragFrom),
                isTarget: targets.contains(square),
                isOccupied: position[square] != nil,
                isChecked: square == checked,
                fileLabel: row(square) == 7 ? String(Square.fileLetters[square.file]) : nil,
                rankLabel: column(square) == 0 ? String(square.rank + 1) : nil
            )
            .offset(x: origin(square, size).x, y: origin(square, size).y)
        }
    }

    private func pieces(_ size: CGFloat) -> some View {
        ForEach(Square.all.filter { position[$0] != nil }, id: \.self) { square in
            PieceView(piece: position[square]!, size: size * 0.85)
                .frame(width: size, height: size)
                .opacity(square == dragFrom && dragLocation != nil ? 0.25 : 1)
                .offset(x: origin(square, size).x, y: origin(square, size).y)
        }
    }

    private func promotionPicker(_ request: PromotionRequest, squareSize: CGFloat, side: CGFloat) -> some View {
        let color = position.sideToMove
        return ZStack {
            Color.black.opacity(0.35)
                .contentShape(Rectangle())
                .onTapGesture { promotion = nil }
            VStack(spacing: 10) {
                Text("Promote to").font(.headline).foregroundColor(.primary)
                HStack(spacing: 8) {
                    ForEach(PieceKind.promotionChoices, id: \.self) { kind in
                        Button {
                            promotion = nil
                            selected = nil
                            onMove(Move(from: request.from, to: request.to, promotion: kind))
                        } label: {
                            PieceView(piece: Piece(color, kind), size: squareSize * 0.8)
                                .frame(width: squareSize, height: squareSize)
                                .background(RoundedRectangle(cornerRadius: 6).fill(BoardColors.light))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 10).fill(.regularMaterial))
        }
        .frame(width: side, height: side)
    }

    // MARK: - Input

    private func boardGesture(_ size: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                beginPress(at: value.startLocation, size)
                if dragFrom != nil, hypot(value.translation.width, value.translation.height) > 4 {
                    dragLocation = value.location
                }
            }
            .onEnded { value in
                let moved = dragLocation != nil
                let start = dragFrom
                let target = square(at: value.location, size)
                let keepSelection = selectedByThisPress
                dragFrom = nil
                dragLocation = nil
                selectedByThisPress = false
                pressStarted = false

                if moved, let from = start {
                    if let to = target, to != from {
                        attemptMove(from: from, to: to)
                    }
                    return
                }
                guard let to = target else { return }
                if let from = start, from == to {
                    // Click on one of our pieces: select it, or deselect it if it was already selected.
                    if !keepSelection { selected = nil }
                    return
                }
                if let from = selected, position.legalMoves(from: from).contains(where: { $0.to == to }) {
                    attemptMove(from: from, to: to)
                } else {
                    selected = nil
                }
            }
    }

    /// Runs once per mouse press: picks up (and selects) one of our pieces if there is one.
    private func beginPress(at point: CGPoint, _ size: CGFloat) {
        guard !pressStarted else { return }
        pressStarted = true
        guard canInteract, promotion == nil, let square = square(at: point, size),
              let piece = position[square], piece.color == movableColor
        else { return }
        dragFrom = square
        if selected != square {
            selected = square
            selectedByThisPress = true
        }
    }

    private func attemptMove(from: Square, to: Square) {
        guard canInteract else { return }
        let candidates = position.legalMoves().filter { $0.from == from && $0.to == to }
        if candidates.isEmpty {
            selected = position[to]?.color == movableColor ? to : from
            return
        }
        if candidates.count > 1 {
            selected = from
            promotion = PromotionRequest(from: from, to: to)
            return
        }
        selected = nil
        onMove(candidates[0])
    }
}

private struct SquareView: View {
    let square: Square
    let size: CGFloat
    let isLastMove: Bool
    let isSelected: Bool
    let isTarget: Bool
    let isOccupied: Bool
    let isChecked: Bool
    let fileLabel: String?
    let rankLabel: String?

    var body: some View {
        let base = square.isLight ? BoardColors.light : BoardColors.dark
        let labelColor = square.isLight ? BoardColors.dark : BoardColors.light
        ZStack {
            Rectangle().fill(base)
            if isLastMove { Rectangle().fill(BoardColors.lastMove) }
            if isSelected { Rectangle().fill(BoardColors.selected) }
            if isChecked {
                RadialGradient(colors: [Color.red.opacity(0.9), Color.red.opacity(0.0)],
                               center: .center, startRadius: 0, endRadius: size * 0.6)
            }
            if isTarget {
                if isOccupied {
                    Circle()
                        .strokeBorder(BoardColors.hint, lineWidth: size * 0.08)
                        .frame(width: size * 0.92, height: size * 0.92)
                } else {
                    Circle()
                        .fill(BoardColors.hint)
                        .frame(width: size * 0.3, height: size * 0.3)
                }
            }
            if let rankLabel = rankLabel {
                Text(rankLabel)
                    .font(.system(size: max(9, size * 0.15), weight: .bold))
                    .foregroundColor(labelColor)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(size * 0.05)
            }
            if let fileLabel = fileLabel {
                Text(fileLabel)
                    .font(.system(size: max(9, size * 0.15), weight: .bold))
                    .foregroundColor(labelColor)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(size * 0.05)
            }
        }
        .frame(width: size, height: size)
        .allowsHitTesting(false)
    }
}
