import ClusterNet
import ClusterProtocol
import ClusterServer
import Foundation
import Observation

/// UI-facing mirror of a HostSession actor's events.
@MainActor
@Observable
final class HostLobbyModel {
    enum State: Equatable {
        case idle
        case starting
        case hosting(code: String)
    }

    struct Knock: Identifiable, Equatable {
        var id: String  // playerID
        var displayName: String
    }

    private(set) var state: State = .idle
    private(set) var roster: [RosterEntry] = []
    private(set) var knocks: [Knock] = []
    private(set) var errorMessage: String?

    private var session: HostSession?
    private var eventsTask: Task<Void, Never>?

    func start(endpoint: RelayEndpoint, identity: PlayerIdentity, displayName: String, avatarPreset: String) {
        guard state == .idle else { return }
        state = .starting
        errorMessage = nil
        Task {
            do {
                let database = try WorldDatabase(fileURL: WorldDatabase.defaultFileURL())
                let space = try database.ensureSpace(named: "The Mansion")
                let session = HostSession(
                    endpoint: endpoint,
                    identity: identity,
                    directory: WorldDirectoryAdapter(database: database),
                    spaceName: space.name,
                    hostDisplayName: displayName,
                    hostAvatarPreset: avatarPreset
                )
                self.session = session
                self.consumeEvents(of: session)
                let code = try await session.start()
                self.state = .hosting(code: code)
            } catch {
                self.errorMessage = "Could not start hosting: \(error.localizedDescription)"
                self.state = .idle
            }
        }
    }

    private func consumeEvents(of session: HostSession) {
        eventsTask = Task {
            for await event in session.events {
                switch event {
                case .registered(let code):
                    self.state = .hosting(code: code)
                case .knock(let playerID, let displayName):
                    self.knocks.append(Knock(id: playerID, displayName: displayName))
                case .rosterChanged(let roster):
                    self.roster = roster
                case .ended(let reason):
                    if self.state != .idle {
                        self.errorMessage = reason
                    }
                    self.state = .idle
                    self.roster = []
                    self.knocks = []
                }
            }
        }
    }

    func resolveKnock(_ knock: Knock, approve: Bool) {
        knocks.removeAll { $0.id == knock.id }
        let session = session
        Task { await session?.resolveKnock(playerID: knock.id, approve: approve) }
    }

    func stop() {
        let session = session
        self.session = nil
        eventsTask?.cancel()
        eventsTask = nil
        state = .idle
        roster = []
        knocks = []
        Task { await session?.stop() }
    }
}

/// UI-facing mirror of a JoinSession actor's events.
@MainActor
@Observable
final class JoinLobbyModel {
    enum State: Equatable {
        case idle
        case connecting(status: String)
        case knocking
        case joined(spaceName: String)
        case denied(reason: String)
    }

    private(set) var state: State = .idle
    private(set) var roster: [RosterEntry] = []

    private var session: JoinSession?
    private var eventsTask: Task<Void, Never>?

    func join(
        code: String, endpoint: RelayEndpoint, identity: PlayerIdentity, displayName: String, avatarPreset: String
    ) {
        guard case .idle = state else { return }
        state = .connecting(status: "Connecting…")
        let session = JoinSession(
            endpoint: endpoint, identity: identity,
            displayName: displayName, avatarPreset: avatarPreset)
        self.session = session
        eventsTask = Task {
            for await event in session.events {
                switch event {
                case .status(let status):
                    if case .connecting = self.state {
                        self.state = .connecting(status: status)
                    }
                case .knockPending:
                    self.state = .knocking
                case .welcomed(let spaceName, let roster):
                    self.state = .joined(spaceName: spaceName)
                    self.roster = roster
                case .rosterChanged(let roster):
                    self.roster = roster
                case .denied(let reason):
                    self.state = .denied(reason: reason)
                    self.roster = []
                case .ended(let reason):
                    if case .joined = self.state {
                        self.state = .denied(reason: reason)
                    } else if case .idle = self.state {
                        // already reset
                    } else if case .denied = self.state {
                        // keep the more specific denial
                    } else {
                        self.state = .denied(reason: reason)
                    }
                    self.roster = []
                }
            }
        }
        Task { await session.start(code: code) }
    }

    func leave() {
        let session = session
        self.session = nil
        eventsTask?.cancel()
        eventsTask = nil
        state = .idle
        roster = []
        Task { await session?.leave() }
    }

    func reset() {
        leave()
    }
}
