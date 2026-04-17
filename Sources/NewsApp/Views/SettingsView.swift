import SwiftUI

struct SettingsView: View {
	@EnvironmentObject var appState: AppState

	@State private var ollamaTestStatus: String?
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
				LabeledContent("API Key") {
					SecureField("Paste your OpenWeatherMap key", text: $appState.openWeatherApiKey)
						.textFieldStyle(.roundedBorder)
				}
				Picker("Temperature Unit", selection: Binding(
					get: { UserDefaults.standard.bool(forKey: "useCelsius") },
					set: { UserDefaults.standard.set($0, forKey: "useCelsius") }
				)) {
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
		guard let host = URL(string: appState.ollamaEndpoint)?.host?.lowercased() else { return true }
		return host == "localhost" || host == "127.0.0.1" || host == "::1" || host == "[::1]"
	}

	private var aiTab: some View {
		Form {
			Section {
				LabeledContent("Endpoint") {
					TextField("http://localhost:11434", text: $appState.ollamaEndpoint)
						.textFieldStyle(.roundedBorder)
				}
				LabeledContent("Model") {
					TextField("gemma4:e4b", text: $appState.ollamaModel)
						.textFieldStyle(.roundedBorder)
				}

				if !isEndpointLocal {
					HStack(alignment: .top, spacing: 6) {
						Image(systemName: "exclamationmark.triangle.fill")
							.foregroundStyle(.orange)
							.font(.system(size: 13))
						Text("Remote endpoint — article content will be sent off-device. Only use a server you own and trust.")
							.font(.system(size: 12))
							.foregroundStyle(.secondary)
							.fixedSize(horizontal: false, vertical: true)
					}
					.padding(.vertical, 4)
				}

				HStack {
					if let status = ollamaTestStatus {
						Text(status)
							.font(.system(size: 12))
							.foregroundStyle(.secondary)
					}
					Spacer()
					Button("Test Connection") {
						Task { await testOllama() }
					}
					.buttonStyle(.bordered)
					.disabled(ollamaTestStatus == "Testing…")
				}
			} header: {
				Text("Ollama Connection")
			} footer: {
				Text("Ollama must be running with the chosen model already pulled. Run `ollama pull <model>` in Terminal to download a model.")
					.foregroundStyle(.secondary)
					.font(.caption)
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
				Text("All features require a working Ollama connection configured above.")
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
				Text("Applies to the AI Summary feature only. Use {title} and {content} as placeholders for the article data.")
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

	private func testOllama() async {
		ollamaTestStatus = "Testing…"
		do {
			let result = try await OllamaService.shared.rewriteAndSummarize(
				title: "Test Article",
				content: "This is a test to verify the Ollama connection is working.",
				endpoint: appState.ollamaEndpoint,
				model: appState.ollamaModel
			)
			ollamaTestStatus = "Connected — \"\(result.headline)\""
		} catch {
			ollamaTestStatus = "Failed: \(error.localizedDescription)"
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
