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
    @State private var showLeaderboard = false

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
                RosterSidebar(
                    roster: roster, selfID: model.identity?.playerID,
                    onKick: mode == .host
                        ? { entry in model.hostLobby.kick(playerID: entry.playerID, block: false) }
                        : nil,
                    onBlock: mode == .host
                        ? { entry in model.hostLobby.kick(playerID: entry.playerID, block: true) }
                        : nil
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(.top, 56)
                .padding(.trailing, 12)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
            if showLeaderboard {
                LeaderboardPanel(leaderboard: raceStateForMode.leaderboard)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(12)
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
                if scene?.isLocalKarted != true, scene?.mountableKartID() != nil {
                    Label("Press E to drive", systemImage: "car.fill")
                        .hudChip()
                }
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
            Text(
                "Click the desk to place · click an item to rotate it · ⌥-click to remove"
            )
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
        .help(qualityHelp(q))
        .hudChip()
    }

    private func qualityHelp(_ q: ConnectionQuality) -> String {
        let stats = voice.stats
        guard stats.concealed > 0 else { return "Connection: \(q.label)" }
        return String(
            format: "Connection: %@ · %.1f%%%% of voice frames concealed",
            q.label, stats.concealmentRate * 100)
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

    private var raceStateForMode: RaceState {
        switch mode {
        case .host: model.hostLobby.raceState
        case .join: model.joinLobby.raceState
        }
    }

    private var lapTimes: (last: UInt32?, best: UInt32?) {
        switch mode {
        case .host: (model.hostLobby.lastLapMs, model.hostLobby.bestLapMs)
        case .join: (model.joinLobby.lastLapMs, model.joinLobby.bestLapMs)
        }
    }

    static func formatMs(_ ms: UInt32) -> String {
        let totalSeconds = Double(ms) / 1000
        let minutes = Int(totalSeconds) / 60
        let seconds = totalSeconds - Double(minutes * 60)
        return String(format: "%d:%05.2f", minutes, seconds)
    }

    /// Live lap stopwatch + last/best — visible while karted.
    @ViewBuilder
    private var kartChip: some View {
        if scene?.isLocalKarted == true {
            TimelineView(.periodic(from: .now, by: 0.1)) { _ in
                HStack(spacing: 8) {
                    Image(systemName: "timer")
                    if let start = scene?.lapClockStart {
                        Text(Self.formatMs(UInt32(Date().timeIntervalSince(start) * 1000)))
                            .font(.callout.monospacedDigit())
                    } else {
                        Text("cross the line to start")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let last = lapTimes.last {
                        Text("last \(Self.formatMs(last))")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    if let best = lapTimes.best {
                        Text("best \(Self.formatMs(best))")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.yellow)
                    }
                }
            }
            .hudChip()
            .help("E hop out · Space drift · H horn")
        }
    }

    private var leaderboardToggle: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) { showLeaderboard.toggle() }
        } label: {
            Image(systemName: "trophy.fill")
                .foregroundStyle(showLeaderboard ? .yellow : .white)
        }
        .buttonStyle(.borderless)
        .hudChip()
        .help("Lap leaderboard")
    }

    @ViewBuilder
    private var hud: some View {
        HStack(spacing: 12) {
            micControls
            statusControl
            kartChip
            leaderboardToggle
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
        newScene.onItemPicked = { [weak model] itemID, wantsRemove in
            guard deskEdit.editingZone != nil, let model else { return }
            if wantsRemove {
                lobbyPerform(.remove(itemID: itemID))
                return
            }
            // Plain click rotates a quarter turn — the host validates and
            // persists it through the same path as placing (ADR 0005).
            let desks = mode == .host ? model.hostLobby.deskState : model.joinLobby.deskState
            guard let item = desks.items.first(where: { $0.id == itemID }) else { return }
            lobbyPerform(
                .move(
                    itemID: itemID, x: item.x, y: item.y,
                    rotation: (item.rotation + 1) % 4))
        }
        keys.install(
            onChange: { [weak newScene] input in newScene?.setInput(input) },
            onPushToTalk: { held in voice.pttHeld = held },
            onDrift: { [weak newScene] held in newScene?.setDrift(held) },
            onAction: { [weak newScene, weak model] in
                guard let scene = newScene, let model else { return }
                let lobbyRace: (RaceCommand) -> Void = { command in
                    switch mode {
                    case .host: model.hostLobby.performRace(command)
                    case .join: model.joinLobby.performRace(command)
                    }
                }
                if scene.isLocalKarted {
                    lobbyRace(.dismount)
                } else if let kartID = scene.mountableKartID() {
                    lobbyRace(.mount(kartID: kartID))
                }
            },
            onHorn: { [weak newScene, weak model] in
                guard let scene = newScene, let model, scene.isLocalKarted else { return }
                switch mode {
                case .host: model.hostLobby.performRace(.horn)
                case .join: model.joinLobby.performRace(.horn)
                }
            }
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
    /// Host-only moderation (Phase 7); nil for joiners.
    var onKick: ((RosterEntry) -> Void)?
    var onBlock: ((RosterEntry) -> Void)?

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
        .contextMenu {
            if entry.playerID != selfID, entry.isOnline, let onKick {
                Button("Kick \(entry.displayName)") { onKick(entry) }
            }
            if entry.playerID != selfID, let onBlock {
                Button("Block \(entry.displayName)", role: .destructive) { onBlock(entry) }
            }
        }
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

    // Space = handbrake/drift (hold) · E = mount/dismount · H = horn (ADR 0006).
    private static let driftKey: UInt16 = 49
    private static let actionKey: UInt16 = 14
    private static let hornKey: UInt16 = 4

    func install(
        onChange: @escaping (MoveInput) -> Void,
        onPushToTalk: @escaping (Bool) -> Void,
        onDrift: @escaping (Bool) -> Void = { _ in },
        onAction: @escaping () -> Void = {},
        onHorn: @escaping () -> Void = {}
    ) {
        remove()
        let down = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            switch event.keyCode {
            case Self.driftKey:
                if !event.isARepeat { onDrift(true) }
                return nil
            case Self.actionKey:
                if !event.isARepeat { onAction() }
                return nil
            case Self.hornKey:
                if !event.isARepeat { onHorn() }
                return nil
            default:
                break
            }
            guard Self.keyMap[event.keyCode] != nil, !event.isARepeat else {
                return event
            }
            self.pressed.insert(event.keyCode)
            onChange(self.combinedInput())
            return nil
        }
        let up = NSEvent.addLocalMonitorForEvents(matching: .keyUp) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == Self.driftKey {
                onDrift(false)
                return nil
            }
            if event.keyCode == Self.actionKey || event.keyCode == Self.hornKey {
                return nil
            }
            guard Self.keyMap[event.keyCode] != nil else { return event }
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

/// Best lap per player, fastest first (ADR 0006).
struct LeaderboardPanel: View {
    let leaderboard: [LapRecord]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Label("Lap Records", systemImage: "trophy.fill")
                .font(.headline)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            Divider().background(.white.opacity(0.15))
            if leaderboard.isEmpty {
                Text("No laps yet — cross the start line on the gravel loop.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(12)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(leaderboard.enumerated()), id: \.element.playerID) { rank, record in
                        HStack(spacing: 8) {
                            Text(rank == 0 ? "🏆" : "\(rank + 1).")
                                .frame(width: 26, alignment: .trailing)
                            Text(record.displayName)
                            Spacer()
                            Text(WorldView.formatMs(record.timeMs))
                                .font(.callout.monospacedDigit())
                                .foregroundStyle(rank == 0 ? .yellow : .white)
                        }
                    }
                }
                .padding(10)
            }
        }
        .foregroundStyle(.white)
        .frame(width: 250)
        .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
    }
}
