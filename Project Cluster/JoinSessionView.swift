import ClusterNet
import SwiftUI

struct JoinSessionView: View {
    @Bindable var model: AppModel
    @State private var sessionCode = ""

    private var lobby: JoinLobbyModel { model.joinLobby }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Button {
                    lobby.leave()
                    model.route = .welcome
                } label: {
                    Label("Back", systemImage: "chevron.left")
                }
                .buttonStyle(.borderless)
                Spacer()
            }

            Label("Join a Session", systemImage: "person.2.fill")
                .font(.largeTitle.weight(.semibold))

            switch lobby.state {
            case .idle:
                entryContent
            case .connecting(let status):
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text(status).foregroundStyle(.secondary)
                }
            case .knocking:
                VStack(alignment: .leading, spacing: 8) {
                    Label("Knock knock…", systemImage: "hand.raised.fill")
                        .font(.title3)
                    Text("Waiting for the host to let you in. They can see your name.")
                        .foregroundStyle(.secondary)
                    Button("Cancel") { lobby.leave() }
                }
            case .joined(let spaceName):
                VStack(alignment: .leading, spacing: 16) {
                    Label("Welcome to \(spaceName)", systemImage: "checkmark.seal.fill")
                        .font(.title2)
                        .foregroundStyle(.green)
                    RosterListView(roster: lobby.roster, selfID: model.identity?.playerID)
                    Button("Leave", role: .destructive) { lobby.leave() }
                }
            case .denied(let reason):
                VStack(alignment: .leading, spacing: 8) {
                    Label(reason, systemImage: "xmark.octagon.fill")
                        .foregroundStyle(.red)
                    Button("Try Again") { lobby.reset() }
                }
            }

            Spacer()
        }
        .padding(32)
    }

    @ViewBuilder
    private var entryContent: some View {
        if !model.relayEndpoint.isConfigured {
            Text("Joining needs the relay configured (ask your host for the values).")
                .foregroundStyle(.secondary)
            Button("Open Settings…") { model.showSettings = true }
        } else {
            Text("Paste the code your host shared.")
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                TextField("CODE", text: $sessionCode)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.large)
                    .font(.title3.monospaced())
                    .frame(maxWidth: 200)
                    .onSubmit(join)

                Button("Join", action: join)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(sessionCode.trimmingCharacters(in: .whitespaces).count < 6)
            }
        }
    }

    private func join() {
        guard let identity = model.identity else { return }
        lobby.join(
            code: sessionCode, endpoint: model.relayEndpoint, identity: identity,
            displayName: model.displayName, avatarPreset: model.avatarPreset)
    }
}

#Preview {
    JoinSessionView(model: AppModel())
}
