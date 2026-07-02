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
    @State private var deskEdit = DeskEditModel()

    @State private var showRoster = true

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
            if showRoster {
                RosterSidebar(roster: roster, selfID: model.identity?.playerID)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(.top, 56)
                    .padding(.trailing, 12)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
            deskPanel
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .padding(12)
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

    private var roster: [RosterEntry] {
        switch mode {
        case .host: model.hostLobby.roster
        case .join: model.joinLobby.roster
        }
    }

    private var deskState: DeskState {
        switch mode {
        case .host: model.hostLobby.deskState
        case .join: model.joinLobby.deskState
        }
    }

    private func performDesk(_ command: DeskCommand) {
        switch mode {
        case .host: model.hostLobby.performDesk(command)
        case .join: model.joinLobby.performDesk(command)
        }
    }

    /// Bottom-left desk panel: claim/release where you stand, and the item
    /// palette while decorating (ADR 0005). The zone check re-evaluates on a
    /// short cadence as you walk.
    @ViewBuilder
    private var deskPanel: some View {
        TimelineView(.periodic(from: .now, by: 0.4)) { _ in
            let myID = model.identity?.playerID ?? ""
            let standingZone = scene?.localPositionSnapshot.flatMap { position in
                model.worldMap?.zones.first {
                    $0.type == "desk"
                        && DeskRules.isInside(x: position.x, y: position.y, zone: $0)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                if let editing = deskEdit.editingZone {
                    editingPalette(zone: editing)
                } else if let zone = standingZone {
                    let owner = deskState.owner(of: zone.name)
                    HStack(spacing: 8) {
                        Image(systemName: "tablecells")
                        Text(deskLabel(zone: zone.name, owner: owner, myID: myID))
                        if owner == nil && deskState.deskOwned(by: myID) == nil {
                            Button("Claim") { performDesk(.claim(zone: zone.name)) }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                        } else if owner == myID {
                            Button("Decorate") { beginEditing(zone: zone) }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                            Button("Release", role: .destructive) {
                                performDesk(.release(zone: zone.name))
                            }
                            .controlSize(.small)
                        }
                    }
                    .hudChip()
                }
            }
        }
        .foregroundStyle(.white)
    }

    private func deskLabel(zone: String, owner: String?, myID: String) -> String {
        guard let owner else { return "\(zone) — unclaimed" }
        if owner == myID { return "\(zone) — yours" }
        let name = roster.first { $0.playerID == owner }?.displayName ?? "someone"
        return "\(zone) — \(name)'s"
    }

    private func beginEditing(zone: WorldMap.Zone) {
        deskEdit.editingZone = zone.name
        scene?.setEditing(zone: zone)
    }

    private func endEditing() {
        deskEdit.editingZone = nil
        scene?.setEditing(zone: nil)
    }

    @ViewBuilder
    private func editingPalette(zone: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Decorating \(zone)")
                    .font(.headline)
                Text("\(deskState.items(in: zone).count)/\(DeskRules.maxItemsPerDesk)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Done") { endEditing() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
            Text("Click inside the highlighted desk to place · click an item to remove it")
                .font(.caption2)
                .foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(CatalogItem.Category.allCases, id: \.self) { category in
                        ForEach(ItemCatalog.all.filter { $0.category == category }) { item in
                            Button(item.name) { deskEdit.selectedCatalogID = item.id }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .tint(deskEdit.selectedCatalogID == item.id ? .green : .gray)
                        }
                    }
                }
            }
            .frame(maxWidth: 520)
        }
        .padding(12)
        .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
    }

    private func changeStatus(_ status: PlayerStatus) {
        model.myStatus = status
        switch mode {
        case .host: model.hostLobby.setStatus(status)
        case .join: model.joinLobby.setStatus(status)
        }
    }

    /// Status picker with hotkeys (⌃1/⌃2/⌃3). The current status shows on the chip.
    @ViewBuilder
    private var statusControl: some View {
        Menu {
            Button {
                changeStatus(.available)
            } label: {
                Label("Available", systemImage: "circle.fill")
            }
            .keyboardShortcut("1", modifiers: .control)
            Button {
                changeStatus(.focus)
            } label: {
                Label("Focus", systemImage: "moon.fill")
            }
            .keyboardShortcut("2", modifiers: .control)
            Button {
                changeStatus(.dnd)
            } label: {
                Label("Do Not Disturb", systemImage: "minus.circle.fill")
            }
            .keyboardShortcut("3", modifiers: .control)
        } label: {
            HStack(spacing: 5) {
                Circle().fill(StatusStyle.color(model.myStatus)).frame(width: 8, height: 8)
                Text(model.myStatus.label)
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .hudChip()
        .help("Set your status (⌃1 Available · ⌃2 Focus · ⌃3 Do Not Disturb)")
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

            // Green when the mic is actually transmitting (open mic past the
            // gate, or PTT held); brightness tracks level.
            Circle()
                .fill(voice.micMuted ? Color.gray : (transmitting ? Color.green : Color.green.opacity(0.4)))
                .frame(width: 7, height: 7)
                .opacity(0.3 + Double(min(voice.micLevel * 12, 0.7)))

            if voice.pushToTalk {
                Text(voice.pttHeld ? "ON AIR" : "Hold ⌥")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(voice.pttHeld ? .green : .secondary)
            }

            Menu {
                Section("Microphone") {
                    ForEach(voice.inputDevices) { device in
                        Button(device.name) { voice.selectedInputDevice = device.id }
                    }
                }
                Section("Output") {
                    ForEach(voice.outputDevices) { device in
                        Button(device.name) { voice.selectedOutputDevice = device.id }
                    }
                }
            } label: {
                Image(systemName: "chevron.down")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 24)
            .help("Choose microphone & output")

            if let error = voice.errorMessage {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                    .help(error)
            }
        }
        .hudChip()
    }

    private var transmitting: Bool {
        guard !voice.micMuted else { return false }
        return voice.pushToTalk ? voice.pttHeld : voice.micLevel > 0.012
    }

    /// Connection-quality dots — only the joiner has a meaningful read (it's
    /// derived from the host's snapshot cadence reaching this client).
    @ViewBuilder
    private var qualityIndicator: some View {
        let q = voice.quality
        HStack(spacing: 2) {
            ForEach(1...3, id: \.self) { bar in
                Capsule()
                    .fill(q.rawValue >= bar ? qualityColor(q) : Color.white.opacity(0.25))
                    .frame(width: 3, height: CGFloat(4 + bar * 3))
            }
        }
        .help("Connection: \(q.label)")
        .hudChip()
    }

    private func qualityColor(_ q: ConnectionQuality) -> Color {
        switch q {
        case .good: .green
        case .fair: .yellow
        case .poor, .lost: .red
        }
    }

    private var rosterToggle: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) { showRoster.toggle() }
        } label: {
            Label("\(roster.filter(\.isOnline).count)", systemImage: "person.2.fill")
        }
        .buttonStyle(.borderless)
        .hudChip()
        .help("Toggle the roster")
    }

    @ViewBuilder
    private var hud: some View {
        HStack(spacing: 12) {
            micControls
            statusControl
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
                rosterToggle
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
                qualityIndicator
                rosterToggle
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
            model.hostLobby.startVoice(
                localWireID: wireID, pushToTalk: model.pushToTalk, status: model.myStatus)
        case .join:
            newScene.worldDelegate = model.joinLobby
            model.joinLobby.scene = newScene
            model.joinLobby.startVoice(
                localWireID: wireID, pushToTalk: model.pushToTalk, status: model.myStatus)
        }
        scene = newScene
        let deskEdit = deskEdit
        let lobbyPerform: (DeskCommand) -> Void = { [weak model] command in
            guard let model else { return }
            switch mode {
            case .host: model.hostLobby.performDesk(command)
            case .join: model.joinLobby.performDesk(command)
            }
        }
        newScene.onTilePicked = { tile in
            guard let zone = deskEdit.editingZone else { return }
            lobbyPerform(
                .place(
                    zone: zone, catalogID: deskEdit.selectedCatalogID,
                    x: Float(tile.x), y: Float(tile.y), rotation: 0))
        }
        newScene.onItemPicked = { itemID in
            guard deskEdit.editingZone != nil else { return }
            lobbyPerform(.remove(itemID: itemID))
        }
        keys.install(
            onChange: { [weak newScene] input in newScene?.setInput(input) },
            onPushToTalk: { held in voice.pttHeld = held }
        )
    }

    private func leaveWorldUI() {
        endEditing()
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

enum StatusStyle {
    static func color(_ status: PlayerStatus) -> Color {
        switch status {
        case .available: .green
        case .focus: .yellow
        case .dnd: .red
        }
    }

    static func icon(_ status: PlayerStatus) -> String {
        switch status {
        case .available: "circle.fill"
        case .focus: "moon.fill"
        case .dnd: "minus.circle.fill"
        }
    }
}

/// The presence panel: everyone the world knows, online (active before away)
/// before offline, with status, away, and last-seen (PLAN §9, ADR 0004).
struct RosterSidebar: View {
    let roster: [RosterEntry]
    let selfID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("People")
                .font(.headline)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            Divider().background(.white.opacity(0.15))
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(roster, id: \.playerID) { entry in
                        row(entry)
                    }
                }
                .padding(6)
            }
        }
        .foregroundStyle(.white)
        .frame(width: 220)
        .frame(maxHeight: 420)
        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func row(_ entry: RosterEntry) -> some View {
        HStack(spacing: 8) {
            ZStack(alignment: .bottomTrailing) {
                Circle()
                    .fill(AvatarPalette.color(for: entry.avatarPreset))
                    .frame(width: 18, height: 18)
                    .opacity(entry.isOnline ? 1 : 0.4)
                Image(systemName: StatusStyle.icon(entry.status))
                    .font(.system(size: 7))
                    .foregroundStyle(StatusStyle.color(entry.status))
                    .background(Circle().fill(.black).frame(width: 9, height: 9))
                    .opacity(entry.isOnline ? 1 : 0)
            }

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(entry.displayName)
                        .font(.callout)
                        .opacity(entry.isOnline ? 1 : 0.55)
                    if entry.playerID == selfID {
                        Text("you").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Text(subtitle(entry))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
    }

    private func subtitle(_ entry: RosterEntry) -> String {
        if !entry.isOnline {
            return entry.lastSeenEpoch > 0 ? "last seen \(Self.ago(entry.lastSeenEpoch))" : "offline"
        }
        if entry.isAway { return "away" }
        return entry.status.label
    }

    static func ago(_ epoch: Double) -> String {
        let seconds = max(0, Date().timeIntervalSince1970 - epoch)
        if seconds < 90 { return "just now" }
        if seconds < 3600 { return "\(Int(seconds / 60))m ago" }
        if seconds < 86400 { return "\(Int(seconds / 3600))h ago" }
        return "\(Int(seconds / 86400))d ago"
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

    func install(
        onChange: @escaping (MoveInput) -> Void,
        onPushToTalk: @escaping (Bool) -> Void
    ) {
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
        // Option held = push-to-talk key. A modifier never collides with
        // movement (or the future kart handbrake on Space).
        let flags = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            onPushToTalk(event.modifierFlags.contains(.option))
            return event
        }
        monitors = [down, up, flags].compactMap { $0 }
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

/// Editing state shared between the HUD and the scene's click callbacks.
@MainActor
@Observable
final class DeskEditModel {
    var editingZone: String?
    var selectedCatalogID: UInt16 = 1
}
