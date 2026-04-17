import Observation
import SwiftUI

/// Stores per-source accent colors chosen by the user.
///
/// Colors are persisted to UserDefaults and exposed as an @Observable so any
/// view that reads ``color(for:)`` automatically re-renders when a color changes.
@MainActor
@Observable
final class SourceColorStore {
	static let shared = SourceColorStore()

	// Internal storage: String key ("sourceId") → Color
	// Must be internal (not private) so @Observable can track accesses from view bodies.
	var stored: [String: Color] = [:]

	private init() {
		// Restore any previously saved colors from UserDefaults.
		for (key, value) in UserDefaults.standard.dictionaryRepresentation() {
			guard key.hasPrefix("source_color_"), let str = value as? String else { continue }
			let idStr = String(key.dropFirst("source_color_".count))
			guard let id = Int64(idStr), let color = decoded(from: str) else { continue }
			stored["\(id)"] = color
		}
	}

	// MARK: - Public API

	/// Returns the user-assigned color for a source, falling back to a
	/// deterministic hash-based color when none has been set.
	func color(for id: Int64) -> Color {
		stored["\(id)"] ?? Self.defaultColor(for: id)
	}

	func set(_ color: Color, for id: Int64) {
		stored["\(id)"] = color
		persist(color, for: id)
	}

	private static func defaultColor(for id: Int64) -> Color {
		let hue = Double(abs(id.hashValue) % 360) / 360.0
		return Color(hue: hue, saturation: 0.55, brightness: 0.75)
	}

	// MARK: - Persistence

	private func persist(_ color: Color, for id: Int64) {
		let r = color.resolve(in: EnvironmentValues())
		let str = "\(r.red) \(r.green) \(r.blue)"
		UserDefaults.standard.set(str, forKey: "source_color_\(id)")
	}

	private func decoded(from str: String) -> Color? {
		let parts = str.split(separator: " ").compactMap { Double($0) }
		guard parts.count == 3 else { return nil }
		return Color(red: parts[0], green: parts[1], blue: parts[2])
	}
}
