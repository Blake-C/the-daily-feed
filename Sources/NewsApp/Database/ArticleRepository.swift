import Foundation
import GRDB

struct ArticleQuery {
	var tags: [String] = []
	var searchText: String = ""
	var sourceId: Int64? = nil
	var hideRead: Bool = false
	var hideHidden: Bool = true   // always filter dismissed articles by default
	var limit: Int = 40
	var offset: Int = 0
}

final class ArticleRepository: @unchecked Sendable {
	private let db: DatabaseQueue

	init(db: DatabaseQueue = DatabaseManager.shared.dbQueue) {
		self.db = db
	}

	func fetch(query: ArticleQuery) throws -> [Article] {
		try db.read { conn in
			// Exclude rawContent / readableContent from the grid query — these can
			// be large HTML blobs that the card view never uses. They are fetched
			// on-demand via fetchReadableContent(id:) when the detail view opens.
			var sql = """
				SELECT id, sourceId, title, rewrittenTitle, author, summary,
				       thumbnailURL, articleURL, publishedAt, fetchedAt,
				       tags, isRead, isHidden, starRating,
				       NULL AS rawContent, NULL AS readableContent
				FROM articles WHERE 1=1
				"""
			var args: [DatabaseValueConvertible] = []

			if query.hideHidden {
				sql += " AND isHidden = 0"
			}
			if query.hideRead {
				sql += " AND isRead = 0"
			}
			if !query.searchText.isEmpty {
				sql += " AND (title LIKE ? OR author LIKE ? OR summary LIKE ?)"
				let pattern = "%\(query.searchText)%"
				args += [pattern, pattern, pattern]
			}
			if let sourceId = query.sourceId {
				sql += " AND sourceId = ?"
				args.append(sourceId)
			}
			if !query.tags.isEmpty {
				let conditions = query.tags.map { _ in "tags LIKE ?" }.joined(separator: " OR ")
				sql += " AND (\(conditions))"
				args += query.tags.map { "%\($0)%" as DatabaseValueConvertible }
			}

			sql += " ORDER BY publishedAt DESC LIMIT ? OFFSET ?"
			args += [query.limit, query.offset]

			return try Article.fetchAll(conn, sql: sql, arguments: StatementArguments(args))
		}
	}

	/// Returns only the cached Readability HTML for a single article, or nil if
	/// it hasn't been extracted yet. Used by the detail view to short-circuit
	/// the WKWebView pipeline when content is already available.
	func fetchReadableContent(id: String) throws -> String? {
		try db.read { conn in
			let row = try Row.fetchOne(
				conn,
				sql: "SELECT readableContent FROM articles WHERE id = ? AND readableContent IS NOT NULL",
				arguments: [id]
			)
			return row?["readableContent"]
		}
	}

	/// Insert new articles; update feed metadata for existing ones while
	/// preserving user-set flags (isRead, isHidden, starRating, cached content).
	func upsert(_ articles: [Article]) throws {
		guard !articles.isEmpty else { return }
		try db.write { conn in
			for article in articles {
				try conn.execute(
					sql: """
					INSERT INTO articles
					  (id, sourceId, title, rewrittenTitle, author, summary,
					   thumbnailURL, articleURL, publishedAt, fetchedAt,
					   tags, isRead, isHidden, starRating, rawContent, readableContent)
					VALUES
					  (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0, 0, 0, NULL, NULL)
					ON CONFLICT(id) DO UPDATE SET
					  title        = excluded.title,
					  author       = excluded.author,
					  thumbnailURL = excluded.thumbnailURL,
					  articleURL   = excluded.articleURL,
					  publishedAt  = excluded.publishedAt,
					  fetchedAt    = excluded.fetchedAt,
					  tags         = excluded.tags
					""",
					arguments: [
						article.id, article.sourceId, article.title, article.rewrittenTitle,
						article.author, article.summary, article.thumbnailURL, article.articleURL,
						article.publishedAt, article.fetchedAt, article.tags,
					]
				)
			}
		}
	}

	func hideArticle(id: String) throws {
		try db.write { conn in
			try conn.execute(
				sql: "UPDATE articles SET isHidden = 1 WHERE id = ?",
				arguments: [id]
			)
		}
	}

	func updateRating(id: String, rating: Int) throws {
		try db.write { conn in
			try conn.execute(
				sql: "UPDATE articles SET starRating = ? WHERE id = ?",
				arguments: [rating, id]
			)
		}
	}

	func markRead(id: String) throws {
		try db.write { conn in
			try conn.execute(
				sql: "UPDATE articles SET isRead = 1 WHERE id = ?",
				arguments: [id]
			)
		}
	}

	func updateContent(id: String, rawContent: String?, readableContent: String?) throws {
		try db.write { conn in
			try conn.execute(
				sql: "UPDATE articles SET rawContent = ?, readableContent = ? WHERE id = ?",
				arguments: [rawContent, readableContent, id]
			)
		}
	}

	func updateRewrittenTitle(id: String, title: String, summary: String) throws {
		try db.write { conn in
			try conn.execute(
				sql: "UPDATE articles SET rewrittenTitle = ?, summary = ? WHERE id = ?",
				arguments: [title, summary, id]
			)
		}
	}

	func count(query: ArticleQuery) throws -> Int {
		try db.read { conn in
			var sql = "SELECT COUNT(*) FROM articles WHERE 1=1"
			var args: [DatabaseValueConvertible] = []

			if query.hideHidden { sql += " AND isHidden = 0" }
			if query.hideRead   { sql += " AND isRead = 0" }
			if !query.searchText.isEmpty {
				sql += " AND (title LIKE ? OR author LIKE ? OR summary LIKE ?)"
				let pattern = "%\(query.searchText)%"
				args += [pattern, pattern, pattern]
			}
			if let sourceId = query.sourceId {
				sql += " AND sourceId = ?"
				args.append(sourceId)
			}
			if !query.tags.isEmpty {
				let conditions = query.tags.map { _ in "tags LIKE ?" }.joined(separator: " OR ")
				sql += " AND (\(conditions))"
				args += query.tags.map { "%\($0)%" as DatabaseValueConvertible }
			}

			return try Int.fetchOne(conn, sql: sql, arguments: StatementArguments(args)) ?? 0
		}
	}
}
