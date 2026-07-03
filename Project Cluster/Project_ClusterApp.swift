//
//  Project_ClusterApp.swift
//  Project Cluster
//
//  Created by Ricardo Nieblas on 6/10/26.
//

import SwiftUI

@main
struct Project_ClusterApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView(model: model)
        }

        // Menu-bar presence while hosting (Phase 7): the world stays up with
        // the window closed, and the code is one click away all day.
        MenuBarExtra(
            "Project Cluster", systemImage: "house.fill",
            isInserted: Binding(
                get: { model.hostLobby.state != .idle },
                set: { _ in })
        ) {
            MenuBarContent(model: model)
        }
    }
}

/// Menu-bar body split out so it can reach the openWindow environment —
/// bare NSApp.activate cannot recreate a closed WindowGroup window.
private struct MenuBarContent: View {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if case .hosting(let code) = model.hostLobby.state {
            Text("Hosting — code \(code)")
            Text("\(model.hostLobby.roster.filter(\.isOnline).count) online")
            Divider()
            Button("Copy Session Code") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(code, forType: .string)
            }
            Button("Open Window") {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            }
            Divider()
            Button("Stop Hosting") {
                model.hostLobby.stop()
            }
        } else {
            Text("Starting…")
        }
    }
}
