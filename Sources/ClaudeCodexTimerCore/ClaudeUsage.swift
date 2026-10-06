import Foundation

public struct ClaudeUsageSnapshot: Codable, Equatable {
    public enum State: String, Codable { case active, inactive, unavailable }
    public var checkedAt: Date
    public var state: State
    public var resetsAt: Date?
    public var usedPercent: Double?
    public var detail: String?

    public init(checkedAt: Date = Date(), state: State, resetsAt: Date? = nil, usedPercent: Double? = nil, detail: String? = nil) {
        self.checkedAt = checkedAt; self.state = state; self.resetsAt = resetsAt
        self.usedPercent = usedPercent; self.detail = detail
    }

    public var summary: String {
        switch state {
        case .active:
            guard let resetsAt else { return "Reset time unavailable" }
            return "Resets \(resetsAt.formatted(.dateTime.month(.abbreviated).day().hour().minute()))"
        case .inactive: return "No active window"
        case .unavailable: return detail ?? "Reset time unavailable"
        }
    }
}

public struct ClaudeWindowVerification: Codable, Equatable {
    public var before: ClaudeUsageSnapshot
    public var after: ClaudeUsageSnapshot
    public init(before: ClaudeUsageSnapshot, after: ClaudeUsageSnapshot) {
        self.before = before; self.after = after
    }
    public enum Status { case started, alreadyActive, active, notStarted, unverified }

    public var status: Status {
        guard after.state == .active, let reset = after.resetsAt, reset > after.checkedAt else {
            return after.state == .inactive ? .notStarted : .unverified
        }
        if before.state == .active, let previousReset = before.resetsAt,
           abs(previousReset.timeIntervalSince(reset)) <= 60 {
            return .alreadyActive
        }
        // A future reset proves an active window, not necessarily that this ping opened it.
        let previouslyInactive = before.state == .inactive || (before.resetsAt.map { $0 <= after.checkedAt } ?? false)
        if previouslyInactive, abs(reset.timeIntervalSince(after.checkedAt) - 5 * 3600) <= 180 {
            return .started
        }
        return .active
    }

    public var confirmed: Bool { [.started, .alreadyActive, .active].contains(status) }
    public var title: String {
        switch status {
        case .started: return "Usage window started"
        case .alreadyActive: return "Window already active"
        case .active: return "Usage window confirmed"
        case .notStarted: return "Window did not start"
        case .unverified: return "Window unverified"
        }
    }
    public var detail: String {
        switch status {
        case .started: return "Claude replied: pong. A new five-hour window is confirmed."
        case .alreadyActive: return "Claude replied: pong. The existing window kept its reset time."
        case .active: return "Claude replied: pong. Claude reports an active window; its start was not verified."
        case .notStarted: return "Claude replied: pong, but Claude still reports no active usage window."
        case .unverified: return "Claude replied: pong, but its usage window could not be verified. Check Claude’s Usage page."
        }
    }
}

enum ClaudeUsageParser {
    // Parse the rendered /usage screen, not a concatenation of terminal escape sequences.
    // In particular, never mistake the weekly reset or a footer warning for the session reset.
    static func parse(_ screen: String, now: Date = Date()) -> ClaudeUsageSnapshot? {
        guard let start = screen.range(of: "Current session", options: .caseInsensitive) else { return nil }
        let remainder = String(screen[start.upperBound...])
        let section = remainder.components(separatedBy: "Current week")[0]
        if section.range(of: "(?i)no active (session|window)|session (has )?not started|starts when you", options: .regularExpression) != nil {
            return ClaudeUsageSnapshot(checkedAt: now, state: .inactive)
        }
        guard let resetMatch = captures(#"(?i)Resets\s+(\d{1,2})(?::(\d{2}))?\s*(am|pm)?\s*\(([^)]+)\)"#, in: section),
              let hourValue = Int(resetMatch[0]), let zone = TimeZone(identifier: resetMatch[3]) else { return nil }
        let minute = Int(resetMatch[1]) ?? 0
        var hour = hourValue
        if !resetMatch[2].isEmpty {
            guard (1...12).contains(hour) else { return nil }
            hour = hour % 12 + (resetMatch[2].lowercased() == "pm" ? 12 : 0)
        }
        guard (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
        guard let reset = calendar.nextDate(after: now.addingTimeInterval(-60), matching: DateComponents(hour: hour, minute: minute), matchingPolicy: .nextTime),
              reset > now, reset.timeIntervalSince(now) <= 5 * 3600 + 120 else { return nil }
        let percent = captures(#"(\d+(?:\.\d+)?)%\s*used"#, in: section).flatMap { Double($0[0]) }
        guard let percent, (0...100).contains(percent) else { return nil }
        return ClaudeUsageSnapshot(checkedAt: now, state: .active, resetsAt: reset, usedPercent: percent)
    }

    private static func captures(_ pattern: String, in text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        return (1..<match.numberOfRanges).map { Range(match.range(at: $0), in: text).map { String(text[$0]) } ?? "" }
    }
}
