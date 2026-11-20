import Foundation

public struct TimeControl: Codable, Hashable {
    /// Starting time per player in seconds; `nil` means no clock.
    public var initialSeconds: Int?
    public var incrementSeconds: Int

    public init(initialSeconds: Int?, incrementSeconds: Int = 0) {
        self.initialSeconds = initialSeconds
        self.incrementSeconds = incrementSeconds
    }

    public static let unlimited = TimeControl(initialSeconds: nil)

    public static let presets: [TimeControl] = [
        .unlimited,
        TimeControl(initialSeconds: 60, incrementSeconds: 0),
        TimeControl(initialSeconds: 120, incrementSeconds: 1),
        TimeControl(initialSeconds: 180, incrementSeconds: 0),
        TimeControl(initialSeconds: 180, incrementSeconds: 2),
        TimeControl(initialSeconds: 300, incrementSeconds: 0),
        TimeControl(initialSeconds: 300, incrementSeconds: 3),
        TimeControl(initialSeconds: 600, incrementSeconds: 0),
        TimeControl(initialSeconds: 600, incrementSeconds: 5),
        TimeControl(initialSeconds: 900, incrementSeconds: 10),
        TimeControl(initialSeconds: 1800, incrementSeconds: 0),
        TimeControl(initialSeconds: 1800, incrementSeconds: 20),
    ]

    public var isUnlimited: Bool { initialSeconds == nil }

    /// "5+3", "Unlimited", ...
    public var label: String {
        guard let initial = initialSeconds else { return "Unlimited" }
        let minutes: String
        if initial % 60 == 0 {
            minutes = String(initial / 60)
        } else {
            minutes = String(format: "%.1f", Double(initial) / 60)
        }
        return "\(minutes)+\(incrementSeconds)"
    }

    /// Speed category (estimated for a 40-move game, as on most chess servers).
    public var category: String {
        guard let initial = initialSeconds else { return "Correspondence-style" }
        let estimate = initial + 40 * incrementSeconds
        if estimate < 180 { return "Bullet" }
        if estimate < 480 { return "Blitz" }
        if estimate < 1500 { return "Rapid" }
        return "Classical"
    }

    public var displayName: String {
        isUnlimited ? "Unlimited" : "\(label) \(category)"
    }

    /// PGN `TimeControl` tag value.
    public var pgnTag: String {
        guard let initial = initialSeconds else { return "-" }
        return incrementSeconds > 0 ? "\(initial)+\(incrementSeconds)" : "\(initial)"
    }
}

/// A two-sided chess clock driven by explicit timestamps so it is deterministic and testable.
public struct ChessClock: Codable, Hashable {
    public private(set) var whiteSeconds: Double
    public private(set) var blackSeconds: Double
    public private(set) var running: PieceColor?
    public private(set) var runningSince: Date?

    public init(white: Double, black: Double) {
        self.whiteSeconds = white
        self.blackSeconds = black
    }

    /// Remaining time for `color` at `now` (may be negative once the flag has fallen).
    public func remaining(_ color: PieceColor, at now: Date) -> Double {
        var value = color == .white ? whiteSeconds : blackSeconds
        if running == color, let since = runningSince {
            value -= now.timeIntervalSince(since)
        }
        return value
    }

    public var isRunning: Bool { running != nil }

    /// Stops whichever side is running, banking its elapsed time.
    public mutating func stop(at now: Date) {
        if let color = running {
            set(color, remaining(color, at: now))
        }
        running = nil
        runningSince = nil
    }

    public mutating func start(_ color: PieceColor, at now: Date) {
        stop(at: now)
        running = color
        runningSince = now
    }

    /// Overwrites a side's banked time. Stop the clock first if that side is running.
    public mutating func set(_ color: PieceColor, _ seconds: Double) {
        if color == .white { whiteSeconds = seconds } else { blackSeconds = seconds }
    }

    public mutating func add(_ seconds: Double, to color: PieceColor) {
        set(color, (color == .white ? whiteSeconds : blackSeconds) + seconds)
    }
}
