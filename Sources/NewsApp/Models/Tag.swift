import Foundation
import GRDB

struct Tag: Identifiable, Codable, FetchableRecord, PersistableRecord, Hashable {
	var id: Int64?
	var name: String
	var isBuiltIn: Bool
	var isActive: Bool  // Whether the user has this tag filter enabled

	static let databaseTableName = "tags"

	mutating func didInsert(_ inserted: InsertionSuccess) {
		id = inserted.rowID
	}

	enum Columns: String, ColumnExpression {
		case id, name, isBuiltIn, isActive
	}
}

extension Tag {
	/// Default curated topic tags bundled with the app.
	static let defaultTags: [String] = [
		"Science", "Technology", "Politics", "USA", "Europe", "World",
		"Business", "Finance", "Health", "Sports", "Entertainment",
		"Environment", "Climate", "Space", "AI", "Cybersecurity",
		"Education", "Culture", "Food", "Travel", "Automotive",
		"Gaming", "Media", "Law", "Military", "Energy",
		"Economy", "Social Justice", "Religion", "History",
	]
}
