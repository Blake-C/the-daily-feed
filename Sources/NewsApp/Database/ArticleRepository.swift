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
			let selectClause = """
				SELECT id, sourceId, title, rewrittenTitle, author, summary,
				       thumbnailURL, articleURL, publishedAt, fetchedAt,
				       tags, isRead, isHidden, starRating,
				       NULL AS rawContent, NULL AS readableContent
				FROM articles
				"""

			var sql: String
			var args: [DatabaseValueConvertible] = []

			if !query.searchText.isEmpty {
				// Route through the FTS index when a search term is present.
				// The subquery returns matching article IDs; the outer query applies
				// all remaining filters and the standard sort.
				let ftsQuery = makeFTSQuery(query.searchText)
				sql = selectClause + " WHERE id IN (SELECT article_id FROM articles_fts WHERE articles_fts MATCH ?)"
				args.append(ftsQuery)
			} else {
				sql = selectClause + " WHERE 1=1"
			}

			if query.hideHidden {
				sql += " AND isHidden = 0"
			}
			if query.hideRead {
				sql += " AND isRead = 0"
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

				// Keep the FTS index in sync. FTS5 does not support UPDATE, so
				// we delete the old entry and re-insert. readableContent is omitted
				// here since it's fetched lazily — updateContent() handles FTS sync
				// when Readability content is available.
				try conn.execute(
					sql: "DELETE FROM articles_fts WHERE article_id = ?",
					arguments: [article.id]
				)
				try conn.execute(
					sql: """
					INSERT INTO articles_fts (article_id, title, author, summary, body)
					VALUES (?, ?, ?, ?, ?)
					""",
					arguments: [
						article.id,
						article.title,
						article.author ?? "",
						article.summary ?? "",
						"",
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

	func markUnread(id: String) throws {
		try db.write { conn in
			try conn.execute(
				sql: "UPDATE articles SET isRead = 0 WHERE id = ?",
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

			// Sync FTS: re-index with the now-available body text.
			// Read current title/author/summary within the same transaction so the
			// FTS record stays consistent even if something else is updating the row.
			if let row = try Row.fetchOne(
				conn,
				sql: "SELECT title, author, summary FROM articles WHERE id = ?",
				arguments: [id]
			) {
				let title: String = row["title"] ?? ""
				let author: String = row["author"] ?? ""
				let summary: String = row["summary"] ?? ""
				let body = readableContent ?? ""

				try conn.execute(
					sql: "DELETE FROM articles_fts WHERE article_id = ?",
					arguments: [id]
				)
				try conn.execute(
					sql: """
					INSERT INTO articles_fts (article_id, title, author, summary, body)
					VALUES (?, ?, ?, ?, ?)
					""",
					arguments: [id, title, author, summary, body]
				)
			}
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

	/// Deletes read, unstarred articles published before `cutoff`.
	/// Unread articles and articles with a star rating are always preserved.
	/// Returns the number of articles removed.
	@discardableResult
	func pruneArticles(olderThan cutoff: Date) throws -> Int {
		try db.write { conn in
			// Capture IDs first so we can clean up the FTS index in the same
			// transaction without a separate DELETE … WHERE article_id IN (subquery).
			let ids = try String.fetchAll(
				conn,
				sql: """
				SELECT id FROM articles
				WHERE publishedAt < ? AND isRead = 1 AND starRating = 0
				""",
				arguments: [cutoff]
			)
			guard !ids.isEmpty else { return 0 }

			for id in ids {
				try conn.execute(
					sql: "DELETE FROM articles_fts WHERE article_id = ?",
					arguments: [id]
				)
			}
			try conn.execute(
				sql: """
				DELETE FROM articles
				WHERE publishedAt < ? AND isRead = 1 AND starRating = 0
				""",
				arguments: [cutoff]
			)
			return ids.count
		}
	}

	/// Returns a dictionary mapping source ID → unread article count for today.
	/// "Today" is defined as midnight-to-now in the device's local timezone, so
	/// the badge automatically reflects only the current day's new articles and
	/// clears itself after midnight without any explicit cleanup.
	func fetchUnreadCountsBySource() throws -> [Int64: Int] {
		let startOfToday = Calendar.current.startOfDay(for: Date())
		return try db.read { conn in
			let rows = try Row.fetchAll(
				conn,
				sql: """
					SELECT sourceId, COUNT(*) AS cnt FROM articles
					WHERE isRead = 0 AND isHidden = 0 AND publishedAt >= ?
					GROUP BY sourceId
					""",
				arguments: [startOfToday]
			)
			var result: [Int64: Int] = [:]
			for row in rows {
				let sourceId: Int64 = row["sourceId"]
				let count: Int = row["cnt"]
				result[sourceId] = count
			}
			return result
		}
	}

	/// Marks all unread articles as read, optionally scoped to a single source.
	/// Pass `nil` for `sourceId` to mark every article in the database as read.
	func markAllRead(sourceId: Int64?) throws {
		try db.write { conn in
			if let sourceId {
				try conn.execute(
					sql: "UPDATE articles SET isRead = 1 WHERE sourceId = ? AND isRead = 0",
					arguments: [sourceId]
				)
			} else {
				try conn.execute(sql: "UPDATE articles SET isRead = 1 WHERE isRead = 0")
			}
		}
	}

	func count(query: ArticleQuery) throws -> Int {
		try db.read { conn in
			var sql: String
			var args: [DatabaseValueConvertible] = []

			if !query.searchText.isEmpty {
				let ftsQuery = makeFTSQuery(query.searchText)
				sql = "SELECT COUNT(*) FROM articles WHERE id IN (SELECT article_id FROM articles_fts WHERE articles_fts MATCH ?)"
				args.append(ftsQuery)
			} else {
				sql = "SELECT COUNT(*) FROM articles WHERE 1=1"
			}

			if query.hideHidden { sql += " AND isHidden = 0" }
			if query.hideRead   { sql += " AND isRead = 0" }
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

	// MARK: - Private

	/// Converts a raw search string into a safe FTS5 MATCH expression.
	/// Each whitespace-delimited word becomes a quoted phrase (prevents FTS5
	/// syntax injection from user input like `"` or `*`).
	private func makeFTSQuery(_ text: String) -> String {
		let words = text.split(whereSeparator: \.isWhitespace).map(String.init).filter { !$0.isEmpty }
		guard !words.isEmpty else { return "\"\"" }
		return words
			.map { "\"\($0.replacingOccurrences(of: "\"", with: "\"\""))\"" }
			.joined(separator: " ")
	}
}
