import SwiftUI

@Observable
@MainActor
final class AppState {
	var showSourceManager = false
	var showSettings = false

	// Settings — persisted via UserDefaults
	static let defaultOllamaEndpoint = "http://localhost:11434"
	static let defaultOllamaModel    = "gemma4:e4b"

	/// Raw stored value — empty means "use default". Bind UI fields to this.
	var ollamaEndpoint: String = UserDefaults.standard.string(forKey: "ollamaEndpoint") ?? "" {
		didSet { UserDefaults.standard.set(ollamaEndpoint, forKey: "ollamaEndpoint") }
	}
	/// Raw stored value — empty means "use default". Bind UI fields to this.
	var ollamaModel: String = UserDefaults.standard.string(forKey: "ollamaModel") ?? "" {
		didSet { UserDefaults.standard.set(ollamaModel, forKey: "ollamaModel") }
	}

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
	var autoRefreshInterval: Int = (UserDefaults.standard.object(forKey: "autoRefreshInterval") as? Int) ?? 0 {
		didSet { UserDefaults.standard.set(autoRefreshInterval, forKey: "autoRefreshInterval") }
	}
	/// Article retention window in days. 0 = keep forever.
	var articleRetentionDays: Int = (UserDefaults.standard.object(forKey: "articleRetentionDays") as? Int) ?? 30 {
		didSet { UserDefaults.standard.set(articleRetentionDays, forKey: "articleRetentionDays") }
	}
	/// Body font size for article detail view, in points.
	var articleFontSize: Int = (UserDefaults.standard.object(forKey: "articleFontSize") as? Int) ?? 17 {
		didSet { UserDefaults.standard.set(articleFontSize, forKey: "articleFontSize") }
	}
	/// Custom Ollama prompt template. Use {title} and {content} as placeholders.
	/// When empty the built-in default prompt is used.
	var ollamaPrompt: String = UserDefaults.standard.string(forKey: "ollamaPrompt") ?? "" {
		didSet { UserDefaults.standard.set(ollamaPrompt, forKey: "ollamaPrompt") }
	}
	/// Whether the AI Summary button is shown in article detail. Enabled by default.
	var aiSummaryEnabled: Bool = (UserDefaults.standard.object(forKey: "aiSummaryEnabled") as? Bool) ?? true {
		didSet { UserDefaults.standard.set(aiSummaryEnabled, forKey: "aiSummaryEnabled") }
	}
	/// Whether the Daily Summary feature is active. Disabled by default.
	var dailySummaryEnabled: Bool = (UserDefaults.standard.object(forKey: "dailySummaryEnabled") as? Bool) ?? false {
		didSet { UserDefaults.standard.set(dailySummaryEnabled, forKey: "dailySummaryEnabled") }
	}
	/// Whether the Suggested Sources feature is active. Disabled by default.
	var suggestedSourcesEnabled: Bool = (UserDefaults.standard.object(forKey: "suggestedSourcesEnabled") as? Bool) ?? false {
		didSet { UserDefaults.standard.set(suggestedSourcesEnabled, forKey: "suggestedSourcesEnabled") }
	}
	/// Whether the article comprehension quiz feature is active. Disabled by default.
	var quizEnabled: Bool = (UserDefaults.standard.object(forKey: "quizEnabled") as? Bool) ?? false {
		didSet { UserDefaults.standard.set(quizEnabled, forKey: "quizEnabled") }
	}

	// Sensitive credentials — stored in the macOS Keychain, not UserDefaults.
	var openWeatherApiKey: String {
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
