import SwiftUI

struct SettingsView: View {
	@EnvironmentObject var appState: AppState

	var body: some View {
		TabView {
			feedTab
				.tabItem { Label("Feed", systemImage: "newspaper") }
				.tag(0)

			ollamaTab
				.tabItem { Label("AI / Ollama", systemImage: "brain") }
				.tag(1)

			weatherTab
				.tabItem { Label("Weather", systemImage: "cloud.sun") }
				.tag(2)

			appearanceTab
				.tabItem { Label("Appearance", systemImage: "paintpalette") }
				.tag(3)
		}
		.frame(width: 480)
		.padding(20)
	}

	// MARK: - Feed

	private var feedTab: some View {
		Form {
			Section {
				Picker("Auto-Refresh Interval", selection: $appState.autoRefreshInterval) {
					Text("Off").tag(0)
					Text("Every 15 minutes").tag(15)
					Text("Every 30 minutes").tag(30)
					Text("Every hour").tag(60)
				}
				.pickerStyle(.radioGroup)
			} header: {
				Text("Refresh")
					.font(.headline)
			} footer: {
				Text("Automatically fetch new articles in the background. Articles are also fetched each time the app launches.")
					.foregroundStyle(.secondary)
					.font(.caption)
			}

			Section {
				Picker("Keep read articles for", selection: $appState.articleRetentionDays) {
					Text("7 days").tag(7)
					Text("30 days").tag(30)
					Text("60 days").tag(60)
					Text("90 days").tag(90)
					Text("Forever").tag(0)
				}
				.pickerStyle(.radioGroup)
			} header: {
				Text("Storage")
					.font(.headline)
			} footer: {
				Text("Read articles older than this are removed during each refresh. Unread articles and bookmarked articles are always kept.")
					.foregroundStyle(.secondary)
					.font(.caption)
			}
		}
		.formStyle(.grouped)
	}

	// MARK: - Ollama

	private var isEndpointLocal: Bool {
		guard let host = URL(string: appState.ollamaEndpoint)?.host?.lowercased() else { return true }
		return host == "localhost" || host == "127.0.0.1" || host == "::1" || host == "[::1]"
	}

	private var ollamaTab: some View {
		Form {
			Section {
				LabeledContent("Endpoint URL") {
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
						Text("This endpoint is not localhost. Article content will be sent to a remote host. Only use a trusted server you control.")
							.font(.system(size: 12))
							.foregroundStyle(.secondary)
							.fixedSize(horizontal: false, vertical: true)
					}
					.padding(.vertical, 4)
				}
			} header: {
				Text("Ollama Connection")
					.font(.headline)
			} footer: {
				Text("Make sure Ollama is running locally with the specified model pulled. The AI rewrite feature uses this connection to generate improved headlines and summaries.")
					.foregroundStyle(.secondary)
					.font(.caption)
			}

			Section {
				Toggle("AI Rewrite", isOn: $appState.aiRewriteEnabled)
				Toggle("Daily Summary", isOn: $appState.dailySummaryEnabled)
				Toggle("Suggested Sources", isOn: $appState.suggestedSourcesEnabled)
				Toggle("Article Quiz", isOn: $appState.quizEnabled)
			} header: {
				Text("Features")
					.font(.headline)
			} footer: {
				Text("AI Rewrite rewrites headlines and generates summaries on demand. Daily Summary silently summarizes articles you read each day. Suggested Sources periodically recommends RSS feeds you might not follow. Article Quiz generates comprehension questions to test your understanding of each article.")
					.foregroundStyle(.secondary)
					.font(.caption)
			}

			Section {
				VStack(alignment: .leading, spacing: 6) {
					TextEditor(text: $appState.ollamaPrompt)
						.font(.system(size: 12, design: .monospaced))
						.frame(minHeight: 120, maxHeight: 200)
						.overlay(
							RoundedRectangle(cornerRadius: 5)
								.strokeBorder(Color.secondary.opacity(0.3), lineWidth: 1)
						)
					if appState.ollamaPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
						Text("Using built-in default prompt. Paste a custom template to override it.")
							.font(.system(size: 11))
							.foregroundStyle(.secondary)
					}
				}
			} header: {
				Text("Custom Prompt Template")
					.font(.headline)
			} footer: {
				Text("Use {title} and {content} as placeholders for the article data. Leave blank to use the default.")
					.foregroundStyle(.secondary)
					.font(.caption)
			}

			Section {
				if let status = ollamaTestStatus {
					Text(status)
						.font(.system(size: 12))
						.foregroundStyle(.secondary)
				}
				Button("Test Connection") {
					Task { await testOllama() }
				}
				.buttonStyle(.bordered)
				.disabled(ollamaTestStatus == "Testing…")
			}
		}
		.formStyle(.grouped)
	}

	@State private var ollamaTestStatus: String?

	private func testOllama() async {
		ollamaTestStatus = "Testing…"
		do {
			let result = try await OllamaService.shared.rewriteAndSummarize(
				title: "Test Article",
				content: "This is a test to verify the Ollama connection is working.",
				endpoint: appState.ollamaEndpoint,
				model: appState.ollamaModel
			)
			ollamaTestStatus = "Connected. Model responded: \"\(result.headline)\""
		} catch {
			ollamaTestStatus = "Failed: \(error.localizedDescription)"
		}
	}

	// MARK: - Weather

	private var weatherTab: some View {
		Form {
			Section {
				LabeledContent("API Key") {
					SecureField("Enter OpenWeatherMap API key", text: $appState.openWeatherApiKey)
						.textFieldStyle(.roundedBorder)
				}
			} header: {
				Text("OpenWeatherMap")
					.font(.headline)
			} footer: {
				Text("Leave blank to hide the weather widget. Get a free API key at openweathermap.org.")
					.foregroundStyle(.secondary)
					.font(.caption)
			}

			Section {
				Toggle("Use Celsius", isOn: Binding(
					get: { UserDefaults.standard.bool(forKey: "useCelsius") },
					set: { UserDefaults.standard.set($0, forKey: "useCelsius") }
				))
			}
		}
		.formStyle(.grouped)
	}

	// MARK: - Appearance

	private var appearanceTab: some View {
		Form {
			Section {
				LabeledContent("Accent Color") {
					ColorPicker("Accent Color", selection: Binding(
						get: { Color.accentColor },
						set: { _ in } // macOS accent color is system-controlled
					))
					.labelsHidden()
				}
			} header: {
				Text("Display")
					.font(.headline)
			}

			Section {
				VStack(alignment: .leading, spacing: 6) {
					HStack {
						Text("Article Font Size")
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
							.font(.system(size: 11))
							.foregroundStyle(.tertiary)
						Spacer()
						Text("Larger")
							.font(.system(size: 11))
							.foregroundStyle(.tertiary)
					}
				}
			} header: {
				Text("Reading")
					.font(.headline)
			} footer: {
				Text("Adjusts the body text size in article detail view. Default is 17 pt.")
					.foregroundStyle(.secondary)
					.font(.caption)
			}
		}
		.formStyle(.grouped)
	}
}
