import Foundation

/// The AI backend the app uses for every AI feature (rewrite, daily summary,
/// quiz, dispute, suggested sources). Selected globally in Settings.
enum AIProvider: String, CaseIterable, Sendable {
	case ollama
	case anthropic
	case openAI

	/// Human-readable name for the Settings picker.
	var displayName: String {
		switch self {
		case .ollama:    "On Device (Ollama)"
		case .anthropic: "Anthropic (Claude)"
		case .openAI:    "OpenAI"
		}
	}

	// MARK: - Curated model lists

	/// Claude models surfaced in Settings. First entry is the recommended default.
	static let anthropicModels = ["claude-haiku-4-5", "claude-sonnet-4-6", "claude-opus-4-8"]
	/// OpenAI models surfaced in Settings. First entry is the recommended default.
	static let openAIModels = ["gpt-4o-mini", "gpt-4o", "gpt-4.1-mini", "gpt-4.1"]

	static let defaultAnthropicModel = anthropicModels[0]
	static let defaultOpenAIModel = openAIModels[0]
}

/// A `Sendable` snapshot of the active provider's configuration, produced on the
/// main actor by `AppState.aiConfig` and passed to `AIService` so background
/// actors never touch `@MainActor` state directly.
struct AIProviderConfig: Sendable {
	let provider: AIProvider
	/// Model identifier (Ollama tag, Claude model id, or OpenAI model id).
	let model: String
	/// Base endpoint URL — Ollama only.
	let endpoint: String
	/// API key — Anthropic / OpenAI only. Empty for Ollama.
	let apiKey: String
}
