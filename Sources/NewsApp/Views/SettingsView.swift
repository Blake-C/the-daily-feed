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
				Text("Read articles older than this are removed during each refresh. Unread articles and starred articles are always kept.")
					.foregroundStyle(.secondary)
					.font(.caption)
			}
		}
		.formStyle(.grouped)
	}

	// MARK: - Ollama

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
			} header: {
				Text("Ollama Connection")
					.font(.headline)
			} footer: {
				Text("Make sure Ollama is running locally with the specified model pulled. The AI rewrite feature uses this connection to generate improved headlines and summaries.")
					.foregroundStyle(.secondary)
					.font(.caption)
			}

			Section {
				Button("Test Connection") {
					Task { await testOllama() }
				}
				.buttonStyle(.bordered)
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
			Section("Display") {
				LabeledContent("Accent Color") {
					ColorPicker("Accent Color", selection: Binding(
						get: { Color.accentColor },
						set: { _ in } // macOS accent color is system-controlled
					))
					.labelsHidden()
				}
			}
		}
		.formStyle(.grouped)
	}
}
