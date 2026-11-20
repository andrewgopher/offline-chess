import Foundation
import ChessCore

/// Saves each game as JSON in ~/Library/Application Support/OfflineChess/Games.
final class GameStore {
    let directory: URL

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        directory = base.appendingPathComponent("OfflineChess/Games", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func loadAll() -> [MatchSnapshot] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { url in try? Wire.decode(MatchSnapshot.self, from: Data(contentsOf: url)) }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    func save(_ snapshot: MatchSnapshot) {
        do {
            let data = try Wire.encode(snapshot)
            try data.write(to: url(for: snapshot.gameID), options: .atomic)
        } catch {
            NSLog("Offline Chess: could not save game: \(error.localizedDescription)")
        }
    }

    func delete(_ gameID: UUID) {
        try? FileManager.default.removeItem(at: url(for: gameID))
    }

    private func url(for gameID: UUID) -> URL {
        directory.appendingPathComponent("\(gameID.uuidString).json")
    }
}
