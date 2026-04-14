import SwiftUI

struct SettingsView: View {
	@EnvironmentObject var appState: AppState

	var body: some View {
		TabView {
			ollamaTab
				.tabItem { Label("AI / Ollama", systemImage: "brain") }
				.tag(0)

			weatherTab
				.tabItem { Label("Weather", systemImage: "cloud.sun") }
				.tag(1)

			appearanceTab
				.tabItem { Label("Appearance", systemImage: "paintpalette") }
				.tag(2)
		}
		.frame(width: 480)
		.padding(20)
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
