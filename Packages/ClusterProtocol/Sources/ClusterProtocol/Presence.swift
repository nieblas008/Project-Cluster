import Foundation

/// User-set status. Distinct from presence (online/away/offline), which is
/// derived, never set (ADR 0004).
public enum PlayerStatus: UInt8, Equatable, Sendable, CaseIterable {
    case available = 0
    /// "Here, but heads-down." Visual signal only — voice still works.
    case focus = 1
    /// Do Not Disturb: mic muted, incoming audio paused (enforced both client
    /// and host side).
    case dnd = 2

    /// Stable string for DB persistence — survives raw-value renumbering.
    public var storageKey: String {
        switch self {
        case .available: "available"
        case .focus: "focus"
        case .dnd: "dnd"
        }
    }

    public init(storageKey: String) {
        switch storageKey {
        case "focus": self = .focus
        case "dnd": self = .dnd
        default: self = .available
        }
    }

    public var label: String {
        switch self {
        case .available: "Available"
        case .focus: "Focus"
        case .dnd: "Do Not Disturb"
        }
    }
}

public enum PresenceRules {
    /// No input or voice for this long flips an online player to "away".
    public static let autoAwaySeconds: Double = 300

    public static func isAway(idleSeconds: Double) -> Bool {
        idleSeconds >= autoAwaySeconds
    }
}

/// Merges the live online members with the offline known players the host
/// pulls from its database, into the single sorted list the sidebar shows.
/// Pure so the ordering rules are unit-tested (ADR 0004).
public enum RosterBuilder {
    /// Online first (active before away), then offline by most-recently-seen;
    /// ties broken by display name. `online` wins if an id appears in both.
    public static func build(online: [RosterEntry], offline: [RosterEntry]) -> [RosterEntry] {
        let onlineIDs = Set(online.map(\.playerID))
        let offlineOnly = offline.filter { !onlineIDs.contains($0.playerID) }

        let sortedOnline = online.sorted { a, b in
            if a.isAway != b.isAway { return !a.isAway }  // active before away
            return a.displayName.localizedCaseInsensitiveCompare(b.displayName) == .orderedAscending
        }
        let sortedOffline = offlineOnly.sorted { a, b in
            if a.lastSeenEpoch != b.lastSeenEpoch { return a.lastSeenEpoch > b.lastSeenEpoch }
            return a.displayName.localizedCaseInsensitiveCompare(b.displayName) == .orderedAscending
        }
        return sortedOnline + sortedOffline
    }
}
