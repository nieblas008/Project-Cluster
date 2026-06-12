import ClusterNet
import ClusterProtocol
import ClusterVoice
import SpriteKit
import SwiftUI

/// Hosts the SpriteKit world with a SwiftUI HUD on top. Owns the keyboard
/// monitors (WASD + arrows) and bridges scene ⇄ lobby model.
struct WorldView: View {
    enum Mode {
        case host
        case join
    }

    let mode: Mode
    @Bindable var model: AppModel

    @State private var scene: WorldScene?
    @State private var keys = KeyState()

    var body: some View {
        ZStack(alignment: .top) {
            if let scene {
                SpriteView(scene: scene)
                    .ignoresSafeArea()
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            hud
        }
        .onAppear(perform: enterWorld)
        .onDisappear(perform: leaveWorldUI)
    }

    private var voice: VoiceController {
        switch mode {
        case .host: model.hostLobby.voice
        case .join: model.joinLobby.voice
        }
    }

    @ViewBuilder
    private var micControls: some View {
        HStack(spacing: 8) {
            Button {
                voice.micMuted.toggle()
            } label: {
                Image(systemName: voice.micMuted ? "mic.slash.fill" : "mic.fill")
                    .foregroundStyle(voice.micMuted ? .red : .white)
            }
            .buttonStyle(.borderless)
            .help(voice.micMuted ? "Unmute microphone" : "Mute microphone")

            Circle()
                .fill(voice.micMuted ? Color.gray : Color.green)
                .frame(width: 7, height: 7)
                .opacity(0.25 + Double(min(voice.micLevel * 12, 0.75)))

            Menu {
                ForEach(voice.inputDevices) { device in
                    Button(device.name) { voice.selectedInputDevice = device.id }
                }
            } label: {
                Image(systemName: "chevron.down")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 24)
            .help("Choose microphone")

            if let error = voice.errorMessage {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                    .help(error)
            }
        }
        .hudChip()
    }

    @ViewBuilder
    private var hud: some View {
        HStack(spacing: 12) {
            micControls
            switch mode {
            case .host:
                if case .hosting(let code) = model.hostLobby.state {
                    HStack(spacing: 6) {
                        Text(code)
                            .font(.headline.monospaced())
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(code, forType: .string)
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.5), in: Capsule())
                }
                Text("\(model.hostLobby.roster.count) here")
                    .hudChip()
                if !model.hostLobby.knocks.isEmpty {
                    Button {
                        model.hostLobby.inWorld = false  // knocks live in the lobby screen
                    } label: {
                        Label("\(model.hostLobby.knocks.count) knocking", systemImage: "hand.raised.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                }
                Spacer()
                Button("Lobby") { model.hostLobby.inWorld = false }
                    .hudChip()
            case .join:
                if case .joined(let spaceName) = model.joinLobby.state {
                    Text(spaceName).hudChip()
                }
                if let usingUDP = model.joinLobby.usingUDP {
                    Text(usingUDP ? "UDP" : "TCP")
                        .font(.caption.monospaced().weight(.bold))
                        .foregroundStyle(usingUDP ? .green : .orange)
                        .hudChip()
                        .help(
                            usingUDP
                                ? "Movement rides UDP datagrams — the fast road."
                                : "Movement rides the TCP tunnel — works everywhere, a touch more latency. Configurable in Settings → Connection."
                        )
                }
                Text("\(model.joinLobby.roster.count) here").hudChip()
                Spacer()
                Button("Leave") { model.joinLobby.leave() }
                    .hudChip()
            }
        }
        .foregroundStyle(.white)
        .padding(12)
    }

    private func enterWorld() {
        guard let map = model.worldMap, let identity = model.identity else { return }
        let newScene = WorldScene(
            map: map,
            localWireID: PlayerWireID.prefix(fromHexID: identity.playerID),
            localDisplayName: model.displayName,
            localPreset: model.avatarPreset
        )
        let wireID = PlayerWireID.prefix(fromHexID: identity.playerID)
        switch mode {
        case .host:
            newScene.worldDelegate = model.hostLobby
            model.hostLobby.scene = newScene
            model.hostLobby.startVoice(localWireID: wireID)
        case .join:
            newScene.worldDelegate = model.joinLobby
            model.joinLobby.scene = newScene
            model.joinLobby.startVoice(localWireID: wireID)
        }
        scene = newScene
        keys.install { [weak newScene] input in
            newScene?.setInput(input)
        }
    }

    private func leaveWorldUI() {
        keys.remove()
        voice.stop()
        switch mode {
        case .host: model.hostLobby.scene = nil
        case .join: model.joinLobby.scene = nil
        }
        scene = nil
    }
}

extension View {
    fileprivate func hudChip() -> some View {
        padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.black.opacity(0.5), in: Capsule())
    }
}

/// Tracks pressed movement keys via local NSEvent monitors. WASD + arrows;
/// handled keys are swallowed so the system doesn't beep at every step.
@MainActor
final class KeyState {
    private var pressed: Set<UInt16> = []
    private var monitors: [Any] = []

    private static let keyMap: [UInt16: MoveInput] = [
        0: MoveInput(dirX: -1, dirY: 0),  // A
        2: MoveInput(dirX: 1, dirY: 0),  // D
        13: MoveInput(dirX: 0, dirY: -1),  // W
        1: MoveInput(dirX: 0, dirY: 1),  // S
        123: MoveInput(dirX: -1, dirY: 0),  // ←
        124: MoveInput(dirX: 1, dirY: 0),  // →
        126: MoveInput(dirX: 0, dirY: -1),  // ↑
        125: MoveInput(dirX: 0, dirY: 1),  // ↓
    ]

    func install(onChange: @escaping (MoveInput) -> Void) {
        remove()
        let down = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, Self.keyMap[event.keyCode] != nil, !event.isARepeat else {
                return event
            }
            self.pressed.insert(event.keyCode)
            onChange(self.combinedInput())
            return nil
        }
        let up = NSEvent.addLocalMonitorForEvents(matching: .keyUp) { [weak self] event in
            guard let self, Self.keyMap[event.keyCode] != nil else { return event }
            self.pressed.remove(event.keyCode)
            onChange(self.combinedInput())
            return nil
        }
        monitors = [down, up].compactMap { $0 }
    }

    func remove() {
        for monitor in monitors {
            NSEvent.removeMonitor(monitor)
        }
        monitors = []
        pressed = []
    }

    private func combinedInput() -> MoveInput {
        var dx = 0
        var dy = 0
        for code in pressed {
            guard let input = Self.keyMap[code] else { continue }
            dx += Int(input.dirX)
            dy += Int(input.dirY)
        }
        return MoveInput(dirX: Int8(clamping: dx), dirY: Int8(clamping: dy))
    }
}
