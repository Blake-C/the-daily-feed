import Foundation
import GRDB

enum SourceType: String, Codable {
	case rss
	case website
}

struct NewsSource: Identifiable, Codable, FetchableRecord, PersistableRecord {
	var id: Int64?
	var name: String
	var url: String
	var type: SourceType
	var faviconURL: String?
	var rating: Int          // 0 = unrated, 1–5
	var isEnabled: Bool
	var tags: String         // Comma-separated default tags for this source
	var addedAt: Date
	var lastFetchedAt: Date?
	var sortOrder: Int       // User-defined display order
	var lastError: String?   // Last fetch error message, nil if last fetch succeeded

	static let databaseTableName = "news_sources"

	mutating func didInsert(_ inserted: InsertionSuccess) {
		id = inserted.rowID
	}

	enum Columns: String, ColumnExpression {
		case id, name, url, type, faviconURL, rating, isEnabled, tags, addedAt, lastFetchedAt
		case sortOrder, lastError
	}

	var tagList: [String] {
		tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
	}
}
