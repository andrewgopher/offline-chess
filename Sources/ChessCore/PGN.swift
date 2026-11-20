import Foundation

public enum PGN {
    /// Renders a PGN game from the standard starting position.
    public static func render(tags: [(String, String)], sanMoves: [String], result: String) -> String {
        var output = ""
        for (key, value) in tags {
            output += "[\(key) \"\(escape(value))\"]\n"
        }
        output += "\n"

        var tokens: [String] = []
        for (index, san) in sanMoves.enumerated() {
            tokens.append(index % 2 == 0 ? "\(index / 2 + 1). \(san)" : san)
        }
        tokens.append(result)

        var line = ""
        for token in tokens {
            if line.isEmpty {
                line = token
            } else if line.count + 1 + token.count > 79 {
                output += line + "\n"
                line = token
            } else {
                line += " " + token
            }
        }
        output += line + "\n"
        return output
    }

    public static func dateTag(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy.MM.dd"
        return formatter.string(from: date)
    }

    static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }
}
