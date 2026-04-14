import Foundation

struct WeatherData: Codable {
	let cityName: String
	let temperature: Double
	let feelsLike: Double
	let description: String
	let iconCode: String
	let humidity: Int
	let windSpeed: Double

	var temperatureFahrenheit: Double { (temperature - 273.15) * 9 / 5 + 32 }
	var temperatureCelsius: Double { temperature - 273.15 }

	var iconURL: URL? {
		URL(string: "https://openweathermap.org/img/wn/\(iconCode)@2x.png")
	}
}

// MARK: - OpenWeatherMap API response shapes

struct OWMResponse: Codable {
	let name: String
	let main: OWMMain
	let weather: [OWMWeather]
	let wind: OWMWind

	struct OWMMain: Codable {
		let temp: Double
		let feelsLike: Double
		let humidity: Int
		enum CodingKeys: String, CodingKey {
			case temp, humidity
			case feelsLike = "feels_like"
		}
	}

	struct OWMWeather: Codable {
		let description: String
		let icon: String
	}

	struct OWMWind: Codable {
		let speed: Double
	}

	func toWeatherData() -> WeatherData {
		WeatherData(
			cityName: name,
			temperature: main.temp,
			feelsLike: main.feelsLike,
			description: weather.first?.description.capitalized ?? "",
			iconCode: weather.first?.icon ?? "01d",
			humidity: main.humidity,
			windSpeed: wind.speed
		)
	}
}
