import SwiftUI

struct SettingsView: View {
	@Bindable var appState: AppState

	@State private var testStatus: String?
	@State private var quizClearStatus: String?

	var body: some View {
		TabView {
			generalTab
				.tabItem { Label("General", systemImage: "gearshape") }
				.tag(0)

			aiTab
				.tabItem { Label("AI", systemImage: "brain") }
				.tag(1)

			appearanceTab
				.tabItem { Label("Appearance", systemImage: "paintpalette") }
				.tag(2)
		}
		.frame(width: 500)
		.padding(20)
	}

	// MARK: - General

	private var generalTab: some View {
		Form {
			Section {
				Picker("Interval", selection: $appState.autoRefreshInterval) {
					Text("Off").tag(0)
					Text("Every 15 minutes").tag(15)
					Text("Every 30 minutes").tag(30)
					Text("Every hour").tag(60)
				}
				.pickerStyle(.radioGroup)
			} header: {
				Text("Background Refresh")
			} footer: {
				Text("Fetches new articles while the app is open. A refresh also runs automatically at launch.")
					.foregroundStyle(.secondary)
					.font(.caption)
			}

			Section {
				Picker("Remove read articles after", selection: $appState.articleRetentionDays) {
					Text("7 days").tag(7)
					Text("30 days").tag(30)
					Text("60 days").tag(60)
					Text("90 days").tag(90)
					Text("Never").tag(0)
				}
				.pickerStyle(.radioGroup)
			} header: {
				Text("Article Storage")
			} footer: {
				Text("Only read articles are cleaned up. Unread and bookmarked articles are always kept regardless of this setting.")
					.foregroundStyle(.secondary)
					.font(.caption)
			}

			Section {
				VStack(alignment: .leading, spacing: 4) {
					Text("API Key")
						.font(.system(size: 12))
						.foregroundStyle(.secondary)
					SecureField("", text: $appState.openWeatherApiKey)
						.textFieldStyle(.roundedBorder)
					Text("e.g. a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4")
						.font(.caption)
						.foregroundStyle(.tertiary)
						.frame(maxWidth: .infinity, alignment: .trailing)
				}
				Picker("Temperature Unit", selection: $appState.useCelsius) {
					Text("Fahrenheit (°F)").tag(false)
					Text("Celsius (°C)").tag(true)
				}
			} header: {
				Text("Weather")
			} footer: {
				Text("Shows current conditions in the app header. Leave the API key blank to hide the widget. A free key is available at openweathermap.org.")
					.foregroundStyle(.secondary)
					.font(.caption)
			}
		}
		.formStyle(.grouped)
	}

	// MARK: - AI

	private var isEndpointLocal: Bool {
		guard let host = URL(string: appState.resolvedEndpoint)?.host?.lowercased() else { return true }
		return host == "localhost" || host == "127.0.0.1" || host == "::1" || host == "[::1]"
	}

	private var selectedProvider: AIProvider {
		AIProvider(rawValue: appState.aiProvider) ?? .ollama
	}

	private var aiTab: some View {
		Form {
			Section {
				Picker("Provider", selection: $appState.aiProvider) {
					ForEach(AIProvider.allCases, id: \.rawValue) { provider in
						Text(provider.displayName).tag(provider.rawValue)
					}
				}
				.pickerStyle(.radioGroup)
			} header: {
				Text("AI Provider")
			} footer: {
				Text("Choose where AI features run. On-device (Ollama) keeps article content local. Anthropic and OpenAI send article content to their servers.")
					.foregroundStyle(.secondary)
					.font(.caption)
			}

			// Only the active provider's connection settings are shown, so it's
			// always clear which service the app will contact.
			switch selectedProvider {
			case .ollama:    ollamaSection
			case .anthropic: anthropicSection
			case .openAI:    openAISection
			}

			Section {
				featureToggle(
					"AI Summary",
					description: "Rewrites the article headline and generates an editorial summary on demand.",
					isOn: $appState.aiSummaryEnabled
				)
				featureToggle(
					"Daily Summary",
					description: "Silently summarizes articles as you read them, collected in the Library sidebar.",
					isOn: $appState.dailySummaryEnabled
				)
				featureToggle(
					"Article Quiz",
					description: "Generates comprehension questions to test your understanding of each article.",
					isOn: $appState.quizEnabled
				)
				featureToggle(
					"Suggested Sources",
					description: "Recommends reputable RSS feeds based on what you already follow.",
					isOn: $appState.suggestedSourcesEnabled
				)
			} header: {
				Text("Features")
			} footer: {
				Text("All features require a working AI provider connection configured above.")
					.foregroundStyle(.secondary)
					.font(.caption)
			}

			Section {
				VStack(alignment: .leading, spacing: 6) {
					TextEditor(text: $appState.ollamaPrompt)
						.font(.system(size: 12, design: .monospaced))
						.frame(minHeight: 100, maxHeight: 180)
						.overlay(
							RoundedRectangle(cornerRadius: 5)
								.strokeBorder(Color.secondary.opacity(0.3), lineWidth: 1)
						)
					if appState.ollamaPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
						Text("Using the built-in default. Paste a custom template to override.")
							.font(.system(size: 11))
							.foregroundStyle(.secondary)
					}
				}
			} header: {
				Text("AI Summary Prompt")
			} footer: {
				Text("Applies to the AI Summary feature only. Use {title} and {content} as placeholders. Only use templates from sources you trust — a custom template fully replaces the built-in instructions.")
					.foregroundStyle(.secondary)
					.font(.caption)
			}

			Section {
				HStack {
					if let status = quizClearStatus {
						Text(status)
							.font(.system(size: 12))
							.foregroundStyle(.secondary)
					}
					Spacer()
					Button("Clear Quiz Data", role: .destructive) {
						clearQuizData()
					}
					.buttonStyle(.bordered)
				}
			} header: {
				Text("Data")
			} footer: {
				Text("Deletes all saved quiz scores and clears cached question sets for every article. This cannot be undone.")
					.foregroundStyle(.secondary)
					.font(.caption)
			}
		}
		.formStyle(.grouped)
	}

	// MARK: - Provider sections

	private var ollamaSection: some View {
		Section {
			VStack(alignment: .leading, spacing: 4) {
				Text("Endpoint")
					.font(.system(size: 12))
					.foregroundStyle(.secondary)
				TextField("", text: $appState.ollamaEndpoint)
					.textFieldStyle(.roundedBorder)
				Text("e.g. \(AppState.defaultOllamaEndpoint)")
					.font(.caption)
					.foregroundStyle(.tertiary)
					.frame(maxWidth: .infinity, alignment: .trailing)
			}

			VStack(alignment: .leading, spacing: 4) {
				Text("Model")
					.font(.system(size: 12))
					.foregroundStyle(.secondary)
				TextField("", text: $appState.ollamaModel)
					.textFieldStyle(.roundedBorder)
				Text("e.g. \(AppState.defaultOllamaModel)")
					.font(.caption)
					.foregroundStyle(.tertiary)
					.frame(maxWidth: .infinity, alignment: .trailing)
			}

			if !isEndpointLocal {
				offDeviceNotice("Remote endpoint — article content will be sent off-device. Only use a server you own and trust.")
			}

			testRow
		} header: {
			Text("Ollama Connection")
		} footer: {
			Text("Ollama must be running with the chosen model already pulled. Run `ollama pull <model>` in Terminal to download a model.")
				.foregroundStyle(.secondary)
				.font(.caption)
		}
	}

	private var anthropicSection: some View {
		Section {
			VStack(alignment: .leading, spacing: 4) {
				Text("API Key")
					.font(.system(size: 12))
					.foregroundStyle(.secondary)
				SecureField("", text: $appState.anthropicApiKey)
					.textFieldStyle(.roundedBorder)
				Text("Stored securely in your macOS Keychain.")
					.font(.caption)
					.foregroundStyle(.tertiary)
					.frame(maxWidth: .infinity, alignment: .trailing)
			}

			ModelPickerField(title: "Model", models: AIProvider.anthropicModels, model: $appState.anthropicModel)

			offDeviceNotice("Article content is sent to Anthropic to generate AI results.")

			testRow
		} header: {
			Text("Anthropic (Claude)")
		} footer: {
			Text("Create an API key at console.anthropic.com. Usage is billed to your Anthropic account.")
				.foregroundStyle(.secondary)
				.font(.caption)
		}
	}

	private var openAISection: some View {
		Section {
			VStack(alignment: .leading, spacing: 4) {
				Text("API Key")
					.font(.system(size: 12))
					.foregroundStyle(.secondary)
				SecureField("", text: $appState.openAIApiKey)
					.textFieldStyle(.roundedBorder)
				Text("Stored securely in your macOS Keychain.")
					.font(.caption)
					.foregroundStyle(.tertiary)
					.frame(maxWidth: .infinity, alignment: .trailing)
			}

			ModelPickerField(title: "Model", models: AIProvider.openAIModels, model: $appState.openAIModel)

			offDeviceNotice("Article content is sent to OpenAI to generate AI results.")

			testRow
		} header: {
			Text("OpenAI")
		} footer: {
			Text("Create an API key at platform.openai.com. Usage is billed to your OpenAI account.")
				.foregroundStyle(.secondary)
				.font(.caption)
		}
	}

	private var testRow: some View {
		HStack {
			if let status = testStatus {
				Text(status)
					.font(.system(size: 12))
					.foregroundStyle(.secondary)
			}
			Spacer()
			Button("Test Connection") {
				Task { await testConnection() }
			}
			.buttonStyle(.bordered)
			.disabled(testStatus == "Testing…")
		}
	}

	@ViewBuilder
	private func offDeviceNotice(_ message: String) -> some View {
		HStack(alignment: .top, spacing: 6) {
			Image(systemName: "exclamationmark.triangle.fill")
				.foregroundStyle(.orange)
				.font(.system(size: 13))
			Text(message)
				.font(.system(size: 12))
				.foregroundStyle(.secondary)
				.fixedSize(horizontal: false, vertical: true)
		}
		.padding(.vertical, 4)
	}

	@ViewBuilder
	private func featureToggle(_ title: String, description: String, isOn: Binding<Bool>) -> some View {
		Toggle(isOn: isOn) {
			VStack(alignment: .leading, spacing: 2) {
				Text(title)
				Text(description)
					.font(.caption)
					.foregroundStyle(.secondary)
			}
		}
	}

	// MARK: - Appearance

	private var appearanceTab: some View {
		Form {
			Section {
				VStack(alignment: .leading, spacing: 8) {
					HStack {
						Text("Font Size")
						Spacer()
						Text("\(appState.articleFontSize) pt")
							.foregroundStyle(.secondary)
							.monospacedDigit()
					}
					Slider(
						value: Binding(
							get: { Double(appState.articleFontSize) },
							set: { appState.articleFontSize = Int($0.rounded()) }
						),
						in: 12...28,
						step: 1
					)
					HStack {
						Text("Smaller")
							.font(.caption)
							.foregroundStyle(.tertiary)
						Spacer()
						Text("Larger")
							.font(.caption)
							.foregroundStyle(.tertiary)
					}
				}
			} header: {
				Text("Article Reading")
			} footer: {
				Text("Controls the body text size in article view. Default is 17 pt.")
					.foregroundStyle(.secondary)
					.font(.caption)
			}
		}
		.formStyle(.grouped)
	}

	// MARK: - Actions

	private func testConnection() async {
		testStatus = "Testing…"
		do {
			let result = try await AIService.shared.rewriteAndSummarize(
				title: "Test Article",
				content: "This is a test to verify the AI provider connection is working.",
				config: appState.aiConfig
			)
			testStatus = "Connected — \"\(result.headline)\""
		} catch {
			testStatus = "Failed: \(error.localizedDescription)"
		}
	}

	private func clearQuizData() {
		do {
			try QuizRepository().deleteAll()
			quizClearStatus = "Quiz data cleared."
		} catch {
			quizClearStatus = "Failed: \(error.localizedDescription)"
		}
	}
}

// MARK: - Model picker

/// A model selector showing a provider's curated models plus a "Custom…" option
/// that reveals a free-text field, so users aren't locked to the bundled list if a
/// provider's model identifiers change.
private struct ModelPickerField: View {
	let title: String
	let models: [String]
	@Binding var model: String
	@State private var isCustom: Bool

	private static let customTag = "__custom__"

	init(title: String, models: [String], model: Binding<String>) {
		self.title = title
		self.models = models
		self._model = model
		let stored = model.wrappedValue.trimmingCharacters(in: .whitespaces)
		// Treat a stored value that isn't one of the curated options as custom.
		self._isCustom = State(initialValue: !stored.isEmpty && !models.contains(stored))
	}

	var body: some View {
		VStack(alignment: .leading, spacing: 4) {
			Text(title)
				.font(.system(size: 12))
				.foregroundStyle(.secondary)
			Picker("", selection: pickerSelection) {
				ForEach(models, id: \.self) { Text($0).tag($0) }
				Text("Custom…").tag(Self.customTag)
			}
			.labelsHidden()
			if isCustom {
				TextField("Model identifier", text: $model)
					.textFieldStyle(.roundedBorder)
			}
		}
	}

	private var pickerSelection: Binding<String> {
		Binding(
			get: {
				if isCustom { return Self.customTag }
				return models.contains(model) ? model : models[0]
			},
			set: { newValue in
				if newValue == Self.customTag {
					isCustom = true
					// Start the custom field empty unless an off-list value is already stored.
					if models.contains(model) { model = "" }
				} else {
					isCustom = false
					model = newValue
				}
			}
		)
	}
}
