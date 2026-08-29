import SwiftUI

@main
struct SayHiApp: App {
    @StateObject private var app = AppState()

    /// Three states worth distinguishing at a glance: off, watching but not
    /// acting, and fully active.
    private var menuBarSymbol: String {
        guard app.isEnabled else { return "hand.raised.slash" }
        return app.settings.actionsEnabled ? "hand.raised.fill" : "hand.raised"
    }

    var body: some Scene {
        Window("SayHi", id: "main") {
            ContentView()
                .environmentObject(app)
                .environmentObject(app.settings)
                .environmentObject(app.mappingStore)
        }
        .defaultSize(width: 900, height: 660)
        // The window draws its own header, so the system title bar would only
        // add a second, differently-styled strip above it.
        .windowStyle(.hiddenTitleBar)

        MenuBarExtra {
            MenuBarView()
                .environmentObject(app)
                .environmentObject(app.settings)
        } label: {
            Image(systemName: menuBarSymbol)
        }
    }
}
