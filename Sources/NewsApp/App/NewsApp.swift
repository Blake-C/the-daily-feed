import SwiftUI

@main
struct NewsApp: App {
	@StateObject private var appState = AppState()

	var body: some Scene {
		WindowGroup("The Daily Feed") {
			ContentView()
				.environmentObject(appState)
				.frame(minWidth: 1024, minHeight: 700)
		}
		.windowStyle(.titleBar)
		.windowToolbarStyle(.unified)
		.commands {
			CommandGroup(replacing: .newItem) {}
			CommandMenu("Sources") {
				Button("Manage Sources…") {
					appState.showSourceManager = true
				}
				.keyboardShortcut("s", modifiers: [.command, .shift])
			}
		}

		Settings {
			SettingsView()
				.environmentObject(appState)
		}
	}
}
