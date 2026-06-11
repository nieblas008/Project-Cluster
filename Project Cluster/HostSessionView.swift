import SwiftUI

/// Phase 0 scope: prove the world lives on this Mac. The session code, relay
/// registration, and lobby arrive with Phase 1.
struct HostSessionView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Button {
                    model.route = .welcome
                } label: {
                    Label("Back", systemImage: "chevron.left")
                }
                .buttonStyle(.borderless)
                Spacer()
            }

            Label("Host & Play", systemImage: "house.fill")
                .font(.largeTitle.weight(.semibold))

            Text(
                """
                Hosting runs the whole world from this Mac — simulation, voice routing, and \
                storage. Phase 0 sets up the storage; the relay connection and session codes \
                land in Phase 1.
                """
            )
            .foregroundStyle(.secondary)

            Button("Prepare World Storage") {
                model.prepareWorld()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            if !model.worldSummary.isEmpty {
                GroupBox("World storage ready") {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(model.worldSummary, id: \.self) { line in
                            Text(line)
                                .font(.callout.monospaced())
                                .textSelection(.enabled)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(4)
                }
            }

            if let error = model.worldError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            }

            Spacer()
        }
        .padding(32)
    }
}

#Preview {
    HostSessionView(model: AppModel())
}
