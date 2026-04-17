import SwiftUI

@MainActor
final class AppState: ObservableObject {
	@Published var showSourceManager = false
	@Published var showSettings = false

	// Settings — persisted via UserDefaults
	static let defaultOllamaEndpoint = "http://localhost:11434"
	static let defaultOllamaModel    = "gemma4:e4b"

	/// Raw stored value — empty means "use default". Bind UI fields to this.
	@AppStorage("ollamaEndpoint") var ollamaEndpoint: String = ""
	/// Raw stored value — empty means "use default". Bind UI fields to this.
	@AppStorage("ollamaModel") var ollamaModel: String = ""

	/// Effective endpoint passed to services — falls back to the default when the stored value is empty.
	var resolvedEndpoint: String {
		ollamaEndpoint.trimmingCharacters(in: .whitespaces).isEmpty
			? Self.defaultOllamaEndpoint
			: ollamaEndpoint
	}
	/// Effective model passed to services — falls back to the default when the stored value is empty.
	var resolvedModel: String {
		ollamaModel.trimmingCharacters(in: .whitespaces).isEmpty
			? Self.defaultOllamaModel
			: ollamaModel
	}
	/// Auto-refresh interval in minutes. 0 = off.
	@AppStorage("autoRefreshInterval") var autoRefreshInterval: Int = 0
	/// Article retention window in days. 0 = keep forever.
	@AppStorage("articleRetentionDays") var articleRetentionDays: Int = 30
	/// Body font size for article detail view, in points.
	@AppStorage("articleFontSize") var articleFontSize: Int = 17
	/// Custom Ollama prompt template. Use {title} and {content} as placeholders.
	/// When empty the built-in default prompt is used.
	@AppStorage("ollamaPrompt") var ollamaPrompt: String = ""
	/// Whether the AI Summary button is shown in article detail. Enabled by default.
	@AppStorage("aiSummaryEnabled") var aiSummaryEnabled: Bool = true
	/// Whether the Daily Summary feature is active. Disabled by default.
	@AppStorage("dailySummaryEnabled") var dailySummaryEnabled: Bool = false
	/// Whether the Suggested Sources feature is active. Disabled by default.
	@AppStorage("suggestedSourcesEnabled") var suggestedSourcesEnabled: Bool = false
	/// Whether the article comprehension quiz feature is active. Disabled by default.
	@AppStorage("quizEnabled") var quizEnabled: Bool = false

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
