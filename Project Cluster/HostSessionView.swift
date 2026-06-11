import ClusterNet
import ClusterProtocol
import SwiftUI

struct HostSessionView: View {
    @Bindable var model: AppModel

    private var lobby: HostLobbyModel { model.hostLobby }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Button {
                    lobby.stop()
                    model.route = .welcome
                } label: {
                    Label("Back", systemImage: "chevron.left")
                }
                .buttonStyle(.borderless)
                Spacer()
            }

            Label("Host & Play", systemImage: "house.fill")
                .font(.largeTitle.weight(.semibold))

            switch lobby.state {
            case .idle:
                idleContent
            case .starting:
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("Registering with the relay…")
                        .foregroundStyle(.secondary)
                }
            case .hosting(let code):
                hostingContent(code: code)
            }

            if let error = lobby.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            }

            Spacer()
        }
        .padding(32)
    }

    @ViewBuilder
    private var idleContent: some View {
        if !model.relayEndpoint.isConfigured {
            Text("Hosting needs a relay. Configure its address and certificate fingerprint first.")
                .foregroundStyle(.secondary)
            Button("Open Settings…") { model.showSettings = true }
        } else {
            Text(
                "Your Mac runs the world — simulation and storage stay here. "
                    + "Coworkers join with the code below once you start."
            )
            .foregroundStyle(.secondary)
            Button("Start Hosting") {
                guard let identity = model.identity else { return }
                lobby.start(
                    endpoint: model.relayEndpoint, identity: identity,
                    displayName: model.displayName, avatarPreset: model.avatarPreset)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.extraLarge)
        }
    }

    @ViewBuilder
    private func hostingContent(code: String) -> some View {
        GroupBox {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Session code")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(code)
                        .font(.system(size: 42, weight: .bold, design: .monospaced))
                        .textSelection(.enabled)
                }
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(code, forType: .string)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
            }
            .padding(8)
        }

        if !lobby.knocks.isEmpty {
            GroupBox("Knocking") {
                ForEach(lobby.knocks) { knock in
                    HStack {
                        Label(knock.displayName, systemImage: "hand.raised.fill")
                        Spacer()
                        Button("Approve") { lobby.resolveKnock(knock, approve: true) }
                            .buttonStyle(.borderedProminent)
                        Button("Deny", role: .destructive) {
                            lobby.resolveKnock(knock, approve: false)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .padding(4)
            }
        }

        RosterListView(roster: lobby.roster, selfID: model.identity?.playerID)

        Button("Stop Hosting", role: .destructive) {
            lobby.stop()
        }
    }
}

/// Shared roster list for both lobbies.
struct RosterListView: View {
    var roster: [RosterEntry]
    var selfID: String?

    var body: some View {
        GroupBox("In the lobby (\(roster.count))") {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(roster, id: \.playerID) { entry in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(AvatarPalette.color(for: entry.avatarPreset))
                            .frame(width: 12, height: 12)
                        Text(entry.displayName)
                        if entry.playerID == selfID {
                            Text("you")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Circle()
                            .fill(entry.isOnline ? Color.green : Color.gray)
                            .frame(width: 8, height: 8)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(6)
        }
    }
}

enum AvatarPalette {
    static func color(for preset: String) -> Color {
        switch preset {
        case "sky": .blue
        case "mint": .mint
        case "coral": .orange
        case "violet": .purple
        default: .teal
        }
    }
}

#Preview {
    HostSessionView(model: AppModel())
}
