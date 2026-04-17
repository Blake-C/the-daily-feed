import Foundation
import FeedKit

final class RSSService: @unchecked Sendable {
	static let shared = RSSService()
	private init() {}

	/// Fetch and parse articles from an RSS/Atom/JSON feed URL.
	func fetchArticles(from source: NewsSource) async throws -> [Article] {
		guard let url = URL(string: source.url), let sourceId = source.id else {
			throw NewsError.invalidURL(source.url)
		}

		return try await withCheckedThrowingContinuation { continuation in
			let parser = FeedParser(URL: url)
			parser.parseAsync { result in
				switch result {
				case .success(let feed):
					let articles = self.mapFeed(feed, sourceId: sourceId, sourceTags: source.tags)
					continuation.resume(returning: articles)
				case .failure(let error):
					continuation.resume(throwing: error)
				}
			}
		}
	}

	// MARK: - Private mapping

	private func mapFeed(_ feed: Feed, sourceId: Int64, sourceTags: String) -> [Article] {
		let now = Date()
		switch feed {
		case .rss(let rss):
			return rss.items?.compactMap { item -> Article? in
				guard let link = item.link, !link.isEmpty else { return nil }
				let id = item.guid?.value ?? link
				return Article(
					id: id,
					sourceId: sourceId,
					title: item.title ?? "Untitled",
					rewrittenTitle: nil,
					author: item.author,
					summary: nil,
					thumbnailURL: item.media?.mediaContents?.first?.attributes?.url
						?? extractImageURL(from: item.content?.contentEncoded ?? item.description),
					articleURL: link,
					publishedAt: item.pubDate ?? now,
					fetchedAt: now,
					tags: sourceTags,
					isRead: false,
					isHidden: false,
					isBookmarked: false,
					readableContent: nil
				)
			} ?? []

		case .atom(let atom):
			return atom.entries?.compactMap { entry -> Article? in
				guard let link = entry.links?.first?.attributes?.href, !link.isEmpty else { return nil }
				let id = entry.id ?? link
				return Article(
					id: id,
					sourceId: sourceId,
					title: entry.title ?? "Untitled",
					rewrittenTitle: nil,
					author: entry.authors?.first?.name,
					summary: nil,
					thumbnailURL: extractImageURL(from: entry.content?.value),
					articleURL: link,
					publishedAt: entry.published ?? entry.updated ?? now,
					fetchedAt: now,
					tags: sourceTags,
					isRead: false,
					isHidden: false,
					isBookmarked: false,
					readableContent: nil
				)
			} ?? []

		case .json(let json):
			return json.items?.compactMap { item -> Article? in
				guard let link = item.url, !link.isEmpty else { return nil }
				let id = item.id ?? link
				return Article(
					id: id,
					sourceId: sourceId,
					title: item.title ?? "Untitled",
					rewrittenTitle: nil,
					author: item.author?.name,
					summary: item.summary,
					thumbnailURL: item.image,
					articleURL: link,
					publishedAt: item.datePublished ?? now,
					fetchedAt: now,
					tags: sourceTags,
					isRead: false,
					isHidden: false,
					isBookmarked: false,
					readableContent: nil
				)
			} ?? []
		}
	}

	/// Attempt to pull the first <img> src from raw HTML.
	private func extractImageURL(from html: String?) -> String? {
		guard let html else { return nil }
		guard let range = html.range(of: #"<img[^>]+src="([^"]+)""#, options: .regularExpression) else {
			return nil
		}
		let match = String(html[range])
		guard let srcRange = match.range(of: #"src="([^"]+)""#, options: .regularExpression) else {
			return nil
		}
		let src = String(match[srcRange])
			.replacingOccurrences(of: "src=\"", with: "")
			.replacingOccurrences(of: "\"", with: "")
		return src.isEmpty ? nil : src
	}
}

enum NewsError: LocalizedError {
	case invalidURL(String)
	case fetchFailed(String)
	case parseFailed(String)
	case ollamaUnavailable
	case weatherUnavailable

	var errorDescription: String? {
		switch self {
		case .invalidURL(let url): "Invalid URL: \(url)"
		case .fetchFailed(let msg): "Fetch failed: \(msg)"
		case .parseFailed(let msg): "Parse failed: \(msg)"
		case .ollamaUnavailable: "Ollama server is unavailable"
		case .weatherUnavailable: "Weather service unavailable"
		}
	}
}
