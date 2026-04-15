import SwiftUI

@main
struct NewsApp: App {
	@StateObject private var appState = AppState()

	init() {
		// Give AsyncImage (and all URLSession-based requests) an explicit cache budget.
		// The default cache is tiny and unbounded; 50 MB memory + 200 MB disk is
		// appropriate for a news app where the same thumbnail can appear in both
		// the grid card and the article detail view.
		URLCache.shared = URLCache(
			memoryCapacity: 50 * 1024 * 1024,
			diskCapacity: 200 * 1024 * 1024,
			diskPath: "news_image_cache"
		)
	}

	var body: some Scene {
		WindowGroup("The Daily Feed") {
			ContentView()
				.environmentObject(appState)
				.environment(SourceColorStore.shared)
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
