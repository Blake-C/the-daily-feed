import SwiftUI
import Combine

@MainActor
final class AppState: ObservableObject {
	@Published var showSourceManager = false
	@Published var showSettings = false

	// Settings — persisted via UserDefaults
	@AppStorage("ollamaEndpoint") var ollamaEndpoint: String = "http://localhost:11434"
	@AppStorage("ollamaModel") var ollamaModel: String = "gemma4:e4b"
	@AppStorage("weatherCity") var weatherCity: String = ""
	/// Auto-refresh interval in minutes. 0 = off.
	@AppStorage("autoRefreshInterval") var autoRefreshInterval: Int = 0
	/// Article retention window in days. 0 = keep forever.
	@AppStorage("articleRetentionDays") var articleRetentionDays: Int = 30
	/// Body font size for article detail view, in points.
	@AppStorage("articleFontSize") var articleFontSize: Int = 17

	// Sensitive credentials — stored in the macOS Keychain, not UserDefaults.
	@Published var openWeatherApiKey: String {
		didSet { KeychainService.shared.set(openWeatherApiKey, for: "openWeatherApiKey") }
	}

	init() {
		// One-time migration: if a key was previously stored in UserDefaults, move it
		// to the Keychain and remove the plaintext copy.
		if let legacy = UserDefaults.standard.string(forKey: "openWeatherApiKey"), !legacy.isEmpty {
			KeychainService.shared.set(legacy, for: "openWeatherApiKey")
			UserDefaults.standard.removeObject(forKey: "openWeatherApiKey")
		}
		openWeatherApiKey = KeychainService.shared.get("openWeatherApiKey")
	}

	var hasWeather: Bool { !openWeatherApiKey.isEmpty }
}
