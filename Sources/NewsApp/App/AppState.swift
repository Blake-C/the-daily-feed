import SwiftUI

@Observable
@MainActor
final class AppState {
	var showSourceManager = false
	var showSettings = false

	// MARK: - Defaults

	static let defaultOllamaEndpoint = "http://localhost:11434"
	static let defaultOllamaModel    = "gemma4:e4b"

	// MARK: - Synced settings (iCloud KV store, fall back to UserDefaults)

	var ollamaEndpoint: String = AppState.readString("ollamaEndpoint", default: "") {
		didSet { AppState.write(ollamaEndpoint, forKey: "ollamaEndpoint") }
	}
	var ollamaModel: String = AppState.readString("ollamaModel", default: "") {
		didSet { AppState.write(ollamaModel, forKey: "ollamaModel") }
	}
	/// Auto-refresh interval in minutes. 0 = off.
	var autoRefreshInterval: Int = AppState.readInt("autoRefreshInterval", default: 0) {
		didSet { AppState.write(autoRefreshInterval, forKey: "autoRefreshInterval") }
	}
	/// Article retention window in days. 0 = keep forever.
	var articleRetentionDays: Int = AppState.readInt("articleRetentionDays", default: 30) {
		didSet { AppState.write(articleRetentionDays, forKey: "articleRetentionDays") }
	}
	/// Body font size for article detail view, in points.
	var articleFontSize: Int = AppState.readInt("articleFontSize", default: 17) {
		didSet { AppState.write(articleFontSize, forKey: "articleFontSize") }
	}
	/// Custom Ollama prompt template. Empty = use built-in default.
	var ollamaPrompt: String = AppState.readString("ollamaPrompt", default: "") {
		didSet { AppState.write(ollamaPrompt, forKey: "ollamaPrompt") }
	}
	var aiSummaryEnabled: Bool = AppState.readBool("aiSummaryEnabled", default: true) {
		didSet { AppState.write(aiSummaryEnabled, forKey: "aiSummaryEnabled") }
	}
	var dailySummaryEnabled: Bool = AppState.readBool("dailySummaryEnabled", default: false) {
		didSet { AppState.write(dailySummaryEnabled, forKey: "dailySummaryEnabled") }
	}
	var suggestedSourcesEnabled: Bool = AppState.readBool("suggestedSourcesEnabled", default: false) {
		didSet { AppState.write(suggestedSourcesEnabled, forKey: "suggestedSourcesEnabled") }
	}
	var quizEnabled: Bool = AppState.readBool("quizEnabled", default: false) {
		didSet { AppState.write(quizEnabled, forKey: "quizEnabled") }
	}
	var useCelsius: Bool = AppState.readBool("useCelsius", default: false) {
		didSet { AppState.write(useCelsius, forKey: "useCelsius") }
	}

	// MARK: - Computed from raw settings

	/// Effective endpoint — falls back to the default when stored value is empty.
	var resolvedEndpoint: String {
		ollamaEndpoint.trimmingCharacters(in: .whitespaces).isEmpty
			? Self.defaultOllamaEndpoint
			: ollamaEndpoint
	}
	/// Effective model — falls back to the default when stored value is empty.
	var resolvedModel: String {
		ollamaModel.trimmingCharacters(in: .whitespaces).isEmpty
			? Self.defaultOllamaModel
			: ollamaModel
	}

	// MARK: - Sensitive credentials (Keychain — not iCloud KV)

	var openWeatherApiKey: String {
		didSet { KeychainService.shared.set(openWeatherApiKey, for: "openWeatherApiKey") }
	}

	var hasWeather: Bool { !openWeatherApiKey.isEmpty }

	// MARK: - Init

	init() {
		// One-time migration: move legacy plaintext key from UserDefaults to Keychain.
		if let legacy = UserDefaults.standard.string(forKey: "openWeatherApiKey"), !legacy.isEmpty {
			KeychainService.shared.set(legacy, for: "openWeatherApiKey")
			UserDefaults.standard.removeObject(forKey: "openWeatherApiKey")
		}
		openWeatherApiKey = KeychainService.shared.get("openWeatherApiKey")

		// Promote existing UserDefaults values to iCloud KV store once so other
		// devices see them on first sync. Falls back gracefully when iCloud is off.
		Self.migrateToiCloud()
		NSUbiquitousKeyValueStore.default.synchronize()

		// Receive changes pushed from other devices.
		NotificationCenter.default.addObserver(
			forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
			object: NSUbiquitousKeyValueStore.default,
			queue: .main
		) { [weak self] note in
			// Extract keys here (non-Sendable boundary) then dispatch to MainActor.
			let keys = (note.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String]) ?? []
			Task { @MainActor [weak self] in self?.applyExternalChanges(keys: keys) }
		}
	}

	// MARK: - External change handler

	private func applyExternalChanges(keys: [String]) {
		for key in keys {
			switch key {
			case "ollamaEndpoint":          ollamaEndpoint          = Self.readString(key, default: "")
			case "ollamaModel":             ollamaModel             = Self.readString(key, default: "")
			case "autoRefreshInterval":     autoRefreshInterval     = Self.readInt(key, default: 0)
			case "articleRetentionDays":    articleRetentionDays    = Self.readInt(key, default: 30)
			case "articleFontSize":         articleFontSize         = Self.readInt(key, default: 17)
			case "ollamaPrompt":            ollamaPrompt            = Self.readString(key, default: "")
			case "aiSummaryEnabled":        aiSummaryEnabled        = Self.readBool(key, default: true)
			case "dailySummaryEnabled":     dailySummaryEnabled     = Self.readBool(key, default: false)
			case "suggestedSourcesEnabled": suggestedSourcesEnabled = Self.readBool(key, default: false)
			case "quizEnabled":             quizEnabled             = Self.readBool(key, default: false)
			case "useCelsius":              useCelsius              = Self.readBool(key, default: false)
			default: break
			}
		}
	}

	// MARK: - iCloud KV / UserDefaults helpers

	/// Reads from iCloud KV first; falls back to UserDefaults, then the supplied default.
	private static func readString(_ key: String, default fallback: String) -> String {
		NSUbiquitousKeyValueStore.default.string(forKey: key)
			?? UserDefaults.standard.string(forKey: key)
			?? fallback
	}

	private static func readBool(_ key: String, default fallback: Bool) -> Bool {
		let iCloud = NSUbiquitousKeyValueStore.default
		if iCloud.object(forKey: key) != nil { return iCloud.bool(forKey: key) }
		if UserDefaults.standard.object(forKey: key) != nil { return UserDefaults.standard.bool(forKey: key) }
		return fallback
	}

	private static func readInt(_ key: String, default fallback: Int) -> Int {
		let iCloud = NSUbiquitousKeyValueStore.default
		if iCloud.object(forKey: key) != nil { return Int(iCloud.longLong(forKey: key)) }
		if UserDefaults.standard.object(forKey: key) != nil { return UserDefaults.standard.integer(forKey: key) }
		return fallback
	}

	/// Writes to both stores so the local UserDefaults stays in sync as a fallback.
	private static func write(_ value: Any, forKey key: String) {
		NSUbiquitousKeyValueStore.default.set(value, forKey: key)
		UserDefaults.standard.set(value, forKey: key)
	}

	private static func migrateToiCloud() {
		guard !UserDefaults.standard.bool(forKey: "iCloudSettingsMigrated") else { return }
		let iCloud = NSUbiquitousKeyValueStore.default
		let ud = UserDefaults.standard
		let keys = [
			"ollamaEndpoint", "ollamaModel", "autoRefreshInterval", "articleRetentionDays",
			"articleFontSize", "ollamaPrompt", "aiSummaryEnabled", "dailySummaryEnabled",
			"suggestedSourcesEnabled", "quizEnabled", "useCelsius",
		]
		for key in keys {
			if let val = ud.object(forKey: key), iCloud.object(forKey: key) == nil {
				iCloud.set(val, forKey: key)
			}
		}
		ud.set(true, forKey: "iCloudSettingsMigrated")
	}
}
