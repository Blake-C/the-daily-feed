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
	var isEnabled: Bool
	var addedAt: Date
	var lastFetchedAt: Date?
	var sortOrder: Int       // User-defined display order
	var lastError: String?   // Last fetch error message, nil if last fetch succeeded
	var badgeClearedAt: Date? // When user last dismissed new-article badge for this source

	static let databaseTableName = "news_sources"

	mutating func didInsert(_ inserted: InsertionSuccess) {
		id = inserted.rowID
	}

	enum Columns: String, ColumnExpression {
		case id, name, url, type, faviconURL, isEnabled, addedAt, lastFetchedAt
		case sortOrder, lastError, badgeClearedAt
	}

}
