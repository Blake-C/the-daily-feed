import SwiftUI

struct NewspaperHeaderView: View {
	@Environment(AppState.self) var appState
	private var weatherService = WeatherService.shared

	private var dateString: String {
		let formatter = DateFormatter()
		formatter.dateFormat = "EEEE, MMMM d, yyyy"
		return formatter.string(from: Date())
	}

	var body: some View {
		VStack(spacing: 0) {
			// Masthead
			ZStack {
				// Left: Date
				HStack {
					Text(dateString)
						.font(.system(size: 11, weight: .regular, design: .serif))
						.foregroundStyle(.secondary)
					Spacer()
				}

				// Center: Title
				Text("THE DAILY FEED")
					.font(.system(size: 36, weight: .bold, design: .serif))
					.tracking(4)
					.foregroundStyle(.primary)

				// Right: Weather
				HStack {
					Spacer()
					if appState.hasWeather, let weather = weatherService.weather {
						WeatherChipView(weather: weather)
					}
				}
			}
			.padding(.horizontal, 24)
			.padding(.vertical, 14)

			// Rule lines
			Rectangle()
				.fill(.primary)
				.frame(height: 3)

			Rectangle()
				.fill(.primary.opacity(0.3))
				.frame(height: 1)
				.padding(.top, 2)
		}
	}
}

// MARK: - Weather chip

private struct WeatherChipView: View {
	let weather: WeatherData

	@AppStorage("useCelsius") private var useCelsius = false

	private var tempString: String {
		let temp = useCelsius ? weather.temperatureCelsius : weather.temperatureFahrenheit
		let unit = useCelsius ? "°C" : "°F"
		return String(format: "%.0f%@", temp, unit)
	}

	var body: some View {
		HStack(spacing: 6) {
			AsyncImage(url: weather.iconURL) { image in
				image.resizable().scaledToFit()
			} placeholder: {
				Image(systemName: "cloud")
			}
			.frame(width: 28, height: 28)

			VStack(alignment: .leading, spacing: 1) {
				Text(tempString)
					.font(.system(size: 13, weight: .semibold))
				Text(weather.cityName)
					.font(.system(size: 10))
					.foregroundStyle(.secondary)
					.lineLimit(1)
			}
		}
		.padding(.horizontal, 10)
		.padding(.vertical, 6)
		.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
	}
}
