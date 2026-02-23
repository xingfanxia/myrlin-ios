import SwiftUI

@main
struct MyrlinMobileApp: App {
    @StateObject private var appState = AppState()
    @AppStorage("appearanceMode") private var appearanceMode: String = "dark"

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .preferredColorScheme(colorScheme(for: appearanceMode))
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                    appState.verifyTokenIfNeeded()
                }
        }
    }

    private func colorScheme(for mode: String) -> ColorScheme? {
        switch mode {
        case "dark": return .dark
        case "light": return .light
        default: return nil
        }
    }
}
