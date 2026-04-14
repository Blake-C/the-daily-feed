import Foundation
import GRDB

struct Article: Identifiable, Codable, FetchableRecord, PersistableRecord {
	var id: String             // GUID from feed or URL hash
	var sourceId: Int64
	var title: String
	var rewrittenTitle: String?
	var author: String?
	var summary: String?       // LLM-generated summary
	var thumbnailURL: String?
	var articleURL: String
	var publishedAt: Date
	var fetchedAt: Date
	var tags: String           // Comma-separated tag names
	var isRead: Bool
	var isHidden: Bool         // User dismissed this article
	var starRating: Int        // 0 = unrated, 1–5
	var rawContent: String?    // Cached raw HTML
	var readableContent: String? // Cached Readability-extracted content

	static let databaseTableName = "articles"

	enum Columns: String, ColumnExpression {
		case id, sourceId, title, rewrittenTitle, author, summary
		case thumbnailURL, articleURL, publishedAt, fetchedAt
		case tags, isRead, isHidden, starRating, rawContent, readableContent
	}

	var tagList: [String] {
		tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
	}
}
