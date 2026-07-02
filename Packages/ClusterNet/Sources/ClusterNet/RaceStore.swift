import ClusterProtocol
import Foundation

/// Lap-time persistence behind the host session (ADR 0006); the app adapts
/// the world database, the smoke harness stays in memory.
public protocol LapStore: Sendable {
    func insertLap(playerID: String, displayName: String, timeMs: Int) throws
    func bestLap(playerID: String) throws -> Int?
    func topLaps(limit: Int) throws -> [LapRecord]
}

public final class InMemoryLapStore: LapStore, @unchecked Sendable {
    private let lock = NSLock()
    private var laps: [(playerID: String, displayName: String, timeMs: Int)] = []

    public init() {}

    public func insertLap(playerID: String, displayName: String, timeMs: Int) throws {
        lock.withLock { laps.append((playerID, displayName, timeMs)) }
    }

    public func bestLap(playerID: String) throws -> Int? {
        lock.withLock { laps.filter { $0.playerID == playerID }.map(\.timeMs).min() }
    }

    public func topLaps(limit: Int) throws -> [LapRecord] {
        lock.withLock {
            var bestByPlayer: [String: (name: String, timeMs: Int)] = [:]
            for lap in laps {
                if let existing = bestByPlayer[lap.playerID], existing.timeMs <= lap.timeMs {
                    continue
                }
                bestByPlayer[lap.playerID] = (lap.displayName, lap.timeMs)
            }
            return
                bestByPlayer
                .map { LapRecord(playerID: $0.key, displayName: $0.value.name, timeMs: UInt32($0.value.timeMs)) }
                .sorted { $0.timeMs < $1.timeMs }
                .prefix(limit)
                .map { $0 }
        }
    }
}
