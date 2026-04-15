import Foundation
import FeedKit

/// Attempts to resolve a user-supplied URL to a valid RSS/Atom/JSON feed.
///
/// Resolution order:
///   1. Try parsing the URL directly with FeedKit — covers cases where the
///      user pastes a feed URL that just happens to have an HTML-ish extension.
///   2. If that fails, fetch the page and look for `<link rel="alternate">`
///      tags advertising a feed (standard HTML feed autodiscovery).
///
/// Returns `nil` if neither strategy finds a usable feed.
final class FeedDiscoveryService: @unchecked Sendable {
	static let shared = FeedDiscoveryService()
	private init() {}

	struct DiscoveryResult {
		/// The resolved feed URL (may differ from the original if autodiscovered).
		let feedURL: String
		/// A suggested display name pulled from the page `<title>`, if available.
		let suggestedName: String?
		/// `true` when the feed URL was found via autodiscovery rather than being
		/// the URL the user typed.
		let wasDiscovered: Bool
	}

	/// Resolves `urlString` to a feed. Returns `nil` if no feed can be found.
	func discover(urlString: String) async -> DiscoveryResult? {
		guard let url = URL(string: urlString) else { return nil }

		// Fast path: try to parse the URL directly as a feed.
		if await isFeed(url: url) {
			return DiscoveryResult(feedURL: urlString, suggestedName: nil, wasDiscovered: false)
		}

		// Slow path: fetch HTML and look for <link rel="alternate"> tags.
		return await discoverFromHTML(pageURL: url)
	}

	// MARK: - Private

	private func isFeed(url: URL) async -> Bool {
		await withCheckedContinuation { continuation in
			FeedParser(URL: url).parseAsync { result in
				switch result {
				case .success: continuation.resume(returning: true)
				case .failure: continuation.resume(returning: false)
				}
			}
		}
	}

	private func discoverFromHTML(pageURL: URL) async -> DiscoveryResult? {
		guard let html = try? await fetchHTML(from: pageURL) else { return nil }

		// Extract <link rel="alternate" type="application/rss+xml" href="..."> and
		// equivalent Atom/JSON feed link tags.
		let feedURL = extractFeedLink(from: html, baseURL: pageURL)
		let pageTitle = extractTitle(from: html)

		guard let feedURL else { return nil }
		return DiscoveryResult(feedURL: feedURL, suggestedName: pageTitle, wasDiscovered: true)
	}

	private func fetchHTML(from url: URL) async throws -> String {
		var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
		request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
		let (data, _) = try await URLSession.shared.data(for: request)
		return String(data: data, encoding: .utf8)
			?? String(data: data, encoding: .isoLatin1)
			?? ""
	}

	/// Parses `<link rel="alternate" type="application/rss+xml" href="...">` and
	/// its Atom/JSON equivalents from raw HTML. Returns an absolute URL string or nil.
	private func extractFeedLink(from html: String, baseURL: URL) -> String? {
		// Accepted MIME types for feed autodiscovery (ordered by preference).
		let feedTypes = [
			"application/rss+xml",
			"application/atom+xml",
			"application/feed+json",
			"application/json",
		]

		// Regex to find <link> tags. We search case-insensitively across the
		// whole document but only need the <head> in practice.
		let linkPattern = #"<link[^>]+>"#
		guard let regex = try? NSRegularExpression(pattern: linkPattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
			return nil
		}

		let nsHTML = html as NSString
		let matches = regex.matches(in: html, range: NSRange(location: 0, length: nsHTML.length))

		for match in matches {
			let tag = nsHTML.substring(with: match.range).lowercased()

			// Must have rel="alternate"
			guard tag.contains(#"rel="alternate""#) || tag.contains("rel='alternate'") else { continue }

			// Must be one of the accepted feed types
			guard feedTypes.contains(where: { tag.contains($0) }) else { continue }

			// Extract the href value
			if let href = extractAttribute("href", from: nsHTML.substring(with: match.range)) {
				return resolveURL(href, relativeTo: baseURL)
			}
		}
		return nil
	}

	/// Extracts `<title>...</title>` text from HTML for use as a suggested source name.
	private func extractTitle(from html: String) -> String? {
		guard
			let start = html.range(of: "<title", options: .caseInsensitive),
			let openClose = html[start.upperBound...].range(of: ">"),
			let titleEnd = html[openClose.upperBound...].range(of: "</title>", options: .caseInsensitive)
		else { return nil }

		let title = String(html[openClose.upperBound..<titleEnd.lowerBound])
			.trimmingCharacters(in: .whitespacesAndNewlines)
		return title.isEmpty ? nil : title
	}

	/// Extracts the value of a named attribute from a raw HTML tag string.
	private func extractAttribute(_ name: String, from tag: String) -> String? {
		let patterns = [
			"\(name)=\"([^\"]+)\"",
			"\(name)='([^']+)'",
		]
		for pattern in patterns {
			guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { continue }
			let nsTag = tag as NSString
			if let match = regex.firstMatch(in: tag, range: NSRange(location: 0, length: nsTag.length)),
				match.numberOfRanges > 1
			{
				let valueRange = match.range(at: 1)
				if valueRange.location != NSNotFound {
					return nsTag.substring(with: valueRange)
				}
			}
		}
		return nil
	}

	/// Resolves a potentially relative URL against a base URL.
	private func resolveURL(_ href: String, relativeTo base: URL) -> String? {
		if let absolute = URL(string: href), absolute.scheme != nil {
			return absolute.absoluteString
		}
		return URL(string: href, relativeTo: base)?.absoluteString
	}
}
