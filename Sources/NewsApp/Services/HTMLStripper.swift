import Foundation

extension String {
	/// Returns the receiver with all HTML tags removed and HTML entities decoded.
	/// Used to produce plain text for accessibility (TTS) from Readability HTML output.
	var strippingHTML: String {
		// Use NSAttributedString to decode entities and strip tags properly
		guard let data = data(using: .utf8) else { return self }
		let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
			.documentType: NSAttributedString.DocumentType.html,
			.characterEncoding: String.Encoding.utf8.rawValue,
		]
		if let attributed = try? NSAttributedString(data: data, options: options, documentAttributes: nil) {
			return attributed.string
		}
		// Fallback: regex strip tags
		return replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
			.replacingOccurrences(of: "\\s{2,}", with: " ", options: .regularExpression)
			.trimmingCharacters(in: .whitespacesAndNewlines)
	}
}
