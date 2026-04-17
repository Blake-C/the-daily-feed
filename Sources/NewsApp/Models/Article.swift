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
	var isBookmarked: Bool     // User saved for later
	var readableContent: String? // Cached Readability-extracted content
	var dailySummary: String?  // Ollama-generated daily briefing
	var readAt: Date?          // Timestamp of first read; nil until opened

	static let databaseTableName = "articles"

	enum Columns: String, ColumnExpression {
		case id, sourceId, title, rewrittenTitle, author, summary
		case thumbnailURL, articleURL, publishedAt, fetchedAt
		case tags, isRead, isHidden, isBookmarked, readableContent
		case dailySummary, readAt
	}

	var tagList: [String] {
		tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
	}
}
