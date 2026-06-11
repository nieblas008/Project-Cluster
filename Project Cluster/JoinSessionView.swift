import SwiftUI

/// Phase 0 stub: the code field exists, the wire does not. Phase 1 connects it
/// to the relay (lookup, knock, lobby).
struct JoinSessionView: View {
    @Bindable var model: AppModel
    @State private var sessionCode = ""

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

            Label("Join a Session", systemImage: "person.2.fill")
                .font(.largeTitle.weight(.semibold))

            Text("Paste the code your host shared. Codes go live in Phase 1.")
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                TextField("Session code", text: $sessionCode)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.large)
                    .font(.title3.monospaced())
                    .frame(maxWidth: 260)

                Button("Join") {}
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(true)
                    .help("Networking arrives in Phase 1.")
            }

            Spacer()
        }
        .padding(32)
    }
}

#Preview {
    JoinSessionView(model: AppModel())
}
