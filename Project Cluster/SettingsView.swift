import ClusterNet
import ClusterServer
import SwiftUI
import UniformTypeIdentifiers

/// Plain bytes for the export panels (world file, identity key).
struct DataDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.data]
    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

/// Relay configuration + the Connectivity Doctor. Values come from
/// `deploy/provision-relay.sh` output (see docs/runbooks/relay.md);
/// for local development, from `scripts/dev-relay.sh`.
struct SettingsView: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var exportingWorld = false
    @State private var worldDocument = DataDocument(data: Data())
    @State private var exportingIdentity = false
    @State private var importingIdentity = false
    @State private var transferMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Form {
                Section("Relay") {
                    TextField("Address (IP)", text: $model.relayHost)
                        .font(.body.monospaced())
                    TextField("Control port", text: $model.relayControlPort)
                    TextField("UDP port", text: $model.relayUDPPort)
                    TextField("Certificate fingerprint (SHA-256 hex)", text: $model.relayFingerprint)
                        .font(.caption.monospaced())
                }

                Section("Connection") {
                    Picker("Transport", selection: $model.transportMode) {
                        Text("Automatic (recommended)").tag("auto")
                        Text("TCP only (compatibility)").tag("tcp")
                    }
                    Text(
                        "Automatic probes the fast UDP road and falls back by itself. "
                            + "Pick TCP only if your network blocks UDP and you want to skip the probe."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Section("Voice") {
                    Toggle("Push-to-talk (hold ⌥ Option)", isOn: $model.pushToTalk)
                    Text(
                        model.pushToTalk
                            ? "Your mic is muted until you hold the Option key."
                            : "Open mic: you transmit automatically when you speak. "
                                + "Switch to push-to-talk for noisy rooms."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    Text("Microphone & output devices are chosen from the in-world toolbar.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("World & Identity") {
                    Button("Export World…") {
                        do {
                            let url = try WorldDatabase.defaultFileURL()
                            worldDocument = DataDocument(data: try Data(contentsOf: url))
                            exportingWorld = true
                        } catch {
                            transferMessage = "Nothing to export yet — host once first."
                        }
                    }
                    Text(
                        "The whole world — desks, lap records, known players — is one file. "
                            + "Export it before risky changes; restoring is copying it back "
                            + "(see docs/runbooks/restore.md). Export while not hosting."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    Button("Export Identity…") { exportingIdentity = true }
                        .disabled(model.identity == nil)
                    Button("Import Identity…") { importingIdentity = true }
                    Text(
                        "Your identity is a key: whoever holds the exported file IS you in "
                            + "every world that knows you. Store it like a password. Importing "
                            + "replaces this Mac's identity after relaunch."
                    )
                    .font(.caption)
                    .foregroundStyle(.red.opacity(0.85))

                    if let transferMessage {
                        Text(transferMessage).font(.caption)
                    }
                }

                Section {
                    HStack {
                        Button("Run Connectivity Doctor") {
                            model.runDoctor()
                        }
                        .disabled(model.doctorRunning)
                        if model.doctorRunning {
                            ProgressView().controlSize(.small)
                        }
                    }

                    ForEach(model.doctorChecks) { check in
                        VStack(alignment: .leading, spacing: 4) {
                            Label(check.name, systemImage: icon(for: check.verdict))
                                .foregroundStyle(color(for: check.verdict))
                            Text(check.detail)
                                .font(.callout)
                            if let remedy = check.remedy {
                                Text(remedy)
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 520, height: 560)
        .fileExporter(
            isPresented: $exportingWorld, document: worldDocument,
            contentType: .data, defaultFilename: "cluster-world-backup.sqlite"
        ) { result in
            if case .success = result { transferMessage = "World exported." }
        }
        .fileExporter(
            isPresented: $exportingIdentity,
            document: DataDocument(data: model.identity?.exportedPrivateKey ?? Data()),
            contentType: .data, defaultFilename: "cluster-identity.key"
        ) { result in
            if case .success = result { transferMessage = "Identity exported — guard that file." }
        }
        .fileImporter(isPresented: $importingIdentity, allowedContentTypes: [.data]) { result in
            guard case .success(let url) = result else { return }
            transferMessage = model.importIdentity(from: url)
        }
    }

    private func icon(for verdict: DoctorCheck.Verdict) -> String {
        switch verdict {
        case .pass: "checkmark.circle.fill"
        case .fail: "xmark.octagon.fill"
        case .info: "info.circle.fill"
        }
    }

    private func color(for verdict: DoctorCheck.Verdict) -> Color {
        switch verdict {
        case .pass: .green
        case .fail: .red
        case .info: .orange
        }
    }
}

#Preview {
    SettingsView(model: AppModel())
}
