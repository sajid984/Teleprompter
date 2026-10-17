import SwiftUI

@main
struct TeleprompterApp: App {
    @State private var scriptStore: ScriptStore
    @State private var settingsStore: SettingsStore
    @State private var session: PrompterSession
    @State private var remoteServer: RemoteServer
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let scripts = ScriptStore()
        let settings = SettingsStore()
        let session = PrompterSession()
        _scriptStore = State(initialValue: scripts)
        _settingsStore = State(initialValue: settings)
        _session = State(initialValue: session)
        _remoteServer = State(initialValue: RemoteServer(scripts: scripts, settings: settings, session: session))
    }

    var body: some Scene {
        WindowGroup {
            LibraryView()
                .environment(scriptStore)
                .environment(settingsStore)
                .environment(session)
                .environment(remoteServer)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                remoteServer.appBecameActive()
            case .background:
                scriptStore.saveNow()
                remoteServer.appEnteredBackground()
            default:
                scriptStore.saveNow()
            }
        }
    }
}
