import AppKit
import SwiftUI

@main
struct OfflineChessApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel.shared

    var body: some Scene {
        Window("Offline Chess", id: "main") {
            RootView()
                .environmentObject(model)
        }
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Needed when launched as a bare executable (`swift run`); harmless inside the .app.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppModel.shared.prepareForTermination()
    }
}

struct RootView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ZStack(alignment: .top) {
            switch model.screen {
            case .lobby: LobbyView()
            case .game: GameView()
            }
            if let banner = model.banner {
                BannerView(text: banner) { model.dismissBanner() }
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: model.banner)
        .frame(minWidth: 960, minHeight: 660)
        .sheet(item: $model.incomingInvite) { invite in
            IncomingInviteView(invite: invite)
                .environmentObject(model)
        }
    }
}

struct BannerView: View {
    let text: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "info.circle.fill")
            Text(text)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
        .shadow(radius: 4)
    }
}
