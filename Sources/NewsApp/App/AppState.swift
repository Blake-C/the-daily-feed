import SwiftUI
import Combine

@MainActor
final class AppState: ObservableObject {
	@Published var showSourceManager = false
	@Published var showSettings = false

	// Settings — persisted via UserDefaults
	@AppStorage("ollamaEndpoint") var ollamaEndpoint: String = "http://localhost:11434"
	@AppStorage("ollamaModel") var ollamaModel: String = "gemma4:e4b"
	@AppStorage("openWeatherApiKey") var openWeatherApiKey: String = ""
	@AppStorage("weatherCity") var weatherCity: String = ""

	var hasWeather: Bool { !openWeatherApiKey.isEmpty }
}
