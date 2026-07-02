import ClusterProtocol
import Foundation

/// Desk persistence, abstracted the same way HostDirectory is: the app adapts
/// `WorldDatabase`; tests and the smoke harness use the in-memory version
/// (ADR 0005). Item ids are store-assigned and stable.
public protocol DeskStore: Sendable {
    func loadDeskState() throws -> DeskState
    /// Empty ownerID releases the claim.
    func setClaim(zone: String, ownerID: String) throws
    func clearItems(zone: String) throws
    func insertItem(zone: String, catalogID: UInt16, x: Float, y: Float, rotation: UInt8) throws
        -> UInt32
    func removeItem(id: UInt32) throws
    func moveItem(id: UInt32, x: Float, y: Float, rotation: UInt8) throws
}

public final class InMemoryDeskStore: DeskStore, @unchecked Sendable {
    private let lock = NSLock()
    private var state = DeskState()
    private var nextID: UInt32 = 1

    public init() {}

    public func loadDeskState() throws -> DeskState {
        lock.withLock { state }
    }

    public func setClaim(zone: String, ownerID: String) throws {
        lock.withLock {
            state.claims.removeAll { $0.zone == zone }
            if !ownerID.isEmpty {
                state.claims.append(DeskClaim(zone: zone, ownerID: ownerID))
            }
        }
    }

    public func clearItems(zone: String) throws {
        lock.withLock {
            state.items.removeAll { $0.zone == zone }
        }
    }

    public func insertItem(
        zone: String, catalogID: UInt16, x: Float, y: Float, rotation: UInt8
    ) throws -> UInt32 {
        lock.withLock {
            let id = nextID
            nextID &+= 1
            state.items.append(
                PlacedItem(id: id, zone: zone, catalogID: catalogID, x: x, y: y, rotation: rotation))
            return id
        }
    }

    public func removeItem(id: UInt32) throws {
        lock.withLock {
            state.items.removeAll { $0.id == id }
        }
    }

    public func moveItem(id: UInt32, x: Float, y: Float, rotation: UInt8) throws {
        lock.withLock {
            guard let index = state.items.firstIndex(where: { $0.id == id }) else { return }
            state.items[index].x = x
            state.items[index].y = y
            state.items[index].rotation = rotation
        }
    }
}
