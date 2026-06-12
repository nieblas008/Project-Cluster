import ClusterNet
import SwiftUI

/// Relay configuration + the Connectivity Doctor. Values come from
/// `deploy/provision-relay.sh` output (see docs/runbooks/relay.md);
/// for local development, from `scripts/dev-relay.sh`.
struct SettingsView: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss

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
        .frame(width: 520, height: 480)
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
