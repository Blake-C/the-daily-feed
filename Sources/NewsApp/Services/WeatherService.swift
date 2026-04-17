import Foundation
import CoreLocation

@Observable
@MainActor
final class WeatherService: NSObject {
	static let shared = WeatherService()

	var weather: WeatherData?
	var error: String?

	private let locationManager = CLLocationManager()
	private var locationContinuation: CheckedContinuation<CLLocation, Error>?

	private override init() {
		super.init()
		locationManager.delegate = self
		locationManager.desiredAccuracy = kCLLocationAccuracyKilometer
	}

	func fetchWeather(apiKey: String) async {
		guard !apiKey.isEmpty else {
			weather = nil
			return
		}

		do {
			let location = try await requestLocation()
			let result = try await fetchFromAPI(
				lat: location.coordinate.latitude,
				lon: location.coordinate.longitude,
				apiKey: apiKey
			)
			weather = result
			error = nil
		} catch {
			self.error = error.localizedDescription
		}
	}

	// MARK: - Private

	private func requestLocation() async throws -> CLLocation {
		let status = locationManager.authorizationStatus
		if status == .notDetermined {
			locationManager.requestWhenInUseAuthorization()
		}

		if let last = locationManager.location {
			return last
		}

		return try await withCheckedThrowingContinuation { continuation in
			self.locationContinuation = continuation
			locationManager.requestLocation()
		}
	}

	private func fetchFromAPI(lat: Double, lon: Double, apiKey: String) async throws -> WeatherData {
		var components = URLComponents(string: "https://api.openweathermap.org/data/2.5/weather")!
		components.queryItems = [
			.init(name: "lat", value: String(lat)),
			.init(name: "lon", value: String(lon)),
			.init(name: "appid", value: apiKey),
		]

		guard let url = components.url else {
			throw NewsError.weatherUnavailable
		}

		let (data, response) = try await URLSession.shared.data(from: url)
		guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
			throw NewsError.weatherUnavailable
		}

		let owm = try JSONDecoder().decode(OWMResponse.self, from: data)
		return owm.toWeatherData()
	}
}

// MARK: - CLLocationManagerDelegate

extension WeatherService: CLLocationManagerDelegate {
	nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
		Task { @MainActor in
			if let location = locations.last {
				self.locationContinuation?.resume(returning: location)
				self.locationContinuation = nil
			}
		}
	}

	nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
		Task { @MainActor in
			self.locationContinuation?.resume(throwing: error)
			self.locationContinuation = nil
		}
	}
}
