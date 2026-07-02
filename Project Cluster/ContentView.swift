import ClusterNet
import SwiftUI

struct ContentView: View {
    @Bindable var model: AppModel

    var body: some View {
        Group {
            switch model.route {
            case .welcome:
                WelcomeView(model: model)
            case .host:
                HostSessionView(model: model)
            case .join:
                JoinSessionView(model: model)
            }
        }
        .frame(minWidth: 760, minHeight: 520)
        .sheet(isPresented: $model.showSettings) {
            SettingsView(model: model)
        }
    }
}

struct WelcomeView: View {
    @Bindable var model: AppModel
    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button {
                    model.showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.borderless)
                .help("Relay settings & Connectivity Doctor")
            }

            Spacer()

            VStack(spacing: 8) {
                Image(systemName: "circle.hexagongrid.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.tint)
                Text("Project Cluster")
                    .font(.largeTitle.weight(.bold))
                Text("Your team's mansion. Desks, voices, go-karts.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 16) {
                TextField("Your display name", text: $model.displayName)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.large)
                    .frame(maxWidth: 320)
                    .focused($nameFocused)

                Picker("Avatar", selection: $model.avatarPreset) {
                    ForEach(AppModel.avatarPresets, id: \.self) { preset in
                        Image(systemName: "person.crop.circle.fill")
                            .foregroundStyle(AvatarPalette.color(for: preset))
                            .tag(preset)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 320)

                HStack(spacing: 16) {
                    Button {
                        model.route = .host
                    } label: {
                        Label("Host & Play", systemImage: "house.fill")
                            .frame(width: 160)
                    }
                    .controlSize(.extraLarge)
                    .buttonStyle(.borderedProminent)

                    Button {
                        model.route = .join
                    } label: {
                        Label("Join", systemImage: "person.2.fill")
                            .frame(width: 160)
                    }
                    .controlSize(.extraLarge)
                    .buttonStyle(.bordered)
                }
                .disabled(!model.hasUsableProfile)

                if !model.hasUsableProfile && model.identityError == nil {
                    Text("Pick a display name to continue.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 32)

            Spacer()

            footer
        }
        .padding(24)
        .onAppear { nameFocused = model.displayName.isEmpty }
    }

    @ViewBuilder
    private var footer: some View {
        if let identity = model.identity {
            Text("This Mac's identity: \(identity.shortID)")
                .font(.footnote.monospaced())
                .foregroundStyle(.tertiary)
                .help(
                    "Your identity is a keypair in the Keychain — no account, no password. "
                        + "Player ID: \(identity.playerID)"
                )
        } else if let error = model.identityError {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .font(.footnote)
                .foregroundStyle(.red)
        }
    }
}

#Preview {
    ContentView(model: AppModel())
}
