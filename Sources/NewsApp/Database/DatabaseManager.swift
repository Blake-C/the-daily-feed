import Foundation
import GRDB

final class DatabaseManager: @unchecked Sendable {
	static let shared = DatabaseManager()

	let dbQueue: DatabaseQueue

	private init() {
		let appSupport = FileManager.default
			.urls(for: .applicationSupportDirectory, in: .userDomainMask)
			.first!
			.appendingPathComponent("The Daily Feed", isDirectory: true)

		try! FileManager.default.createDirectory(
			at: appSupport,
			withIntermediateDirectories: true,
			attributes: [.posixPermissions: 0o700]
		)

		let dbURL = appSupport.appendingPathComponent("news.sqlite")

		// Security note (CWE-922 / Insecure Storage):
		// The database is a plaintext SQLite file. Full-disk encryption (SQLCipher)
		// is not used because:
		//   • The database contains only publicly available news articles and
		//     lightweight user preferences (read status, ratings). No credentials,
		//     PII, or sensitive personal data are stored here.
		//   • API keys are stored in UserDefaults via @AppStorage, not in this file.
		//   • macOS system-level Full Disk Encryption (FileVault) provides
		//     at-rest protection on the user's machine.
		//
		// The mitigations below provide defence-in-depth for the residual risk:
		//   1. POSIX 0o600 permissions — only the owning user can read or write.
		//   2. isExcludedFromBackup — file is not synced to iCloud or Time Machine,
		//      reducing the attack surface to the local machine only.

		// Exclude the database from iCloud and Time Machine backups.
		var excludedURL = dbURL
		var resourceValues = URLResourceValues()
		resourceValues.isExcludedFromBackup = true
		try? excludedURL.setResourceValues(resourceValues)

		// Restrict file permissions to owner read/write only (0600).
		let dbPath = dbURL.path
		if FileManager.default.fileExists(atPath: dbPath) {
			try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: dbPath)
		}

		dbQueue = try! DatabaseQueue(path: dbPath)

		// After creation, apply permissions again for new files.
		try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: dbPath)

		try! migrate()
	}

	private func migrate() throws {
		var migrator = DatabaseMigrator()

		migrator.registerMigration("v1_initial") { db in
			// Tags
			try db.create(table: "tags", ifNotExists: true) { t in
				t.autoIncrementedPrimaryKey("id")
				t.column("name", .text).notNull().unique()
				t.column("isBuiltIn", .boolean).notNull().defaults(to: false)
				t.column("isActive", .boolean).notNull().defaults(to: false)
			}

			// News sources
			try db.create(table: "news_sources", ifNotExists: true) { t in
				t.autoIncrementedPrimaryKey("id")
				t.column("name", .text).notNull()
				t.column("url", .text).notNull().unique()
				t.column("type", .text).notNull().defaults(to: "rss")
				t.column("faviconURL", .text)
				t.column("rating", .integer).notNull().defaults(to: 0)
				t.column("isEnabled", .boolean).notNull().defaults(to: true)
				t.column("tags", .text).notNull().defaults(to: "")
				t.column("addedAt", .datetime).notNull()
				t.column("lastFetchedAt", .datetime)
			}

			// Articles
			try db.create(table: "articles", ifNotExists: true) { t in
				t.primaryKey("id", .text)
				t.column("sourceId", .integer).notNull().references("news_sources", onDelete: .cascade)
				t.column("title", .text).notNull()
				t.column("rewrittenTitle", .text)
				t.column("author", .text)
				t.column("summary", .text)
				t.column("thumbnailURL", .text)
				t.column("articleURL", .text).notNull()
				t.column("publishedAt", .datetime).notNull()
				t.column("fetchedAt", .datetime).notNull()
				t.column("tags", .text).notNull().defaults(to: "")
				t.column("isRead", .boolean).notNull().defaults(to: false)
				t.column("starRating", .integer).notNull().defaults(to: 0)
				t.column("rawContent", .text)
				t.column("readableContent", .text)
			}

			try db.create(index: "articles_publishedAt", on: "articles", columns: ["publishedAt"])
			try db.create(index: "articles_sourceId", on: "articles", columns: ["sourceId"])
			try db.create(index: "articles_isRead", on: "articles", columns: ["isRead"])
		}

		migrator.registerMigration("v2_hidden_sort_error") { db in
			try db.alter(table: "articles") { t in
				t.add(column: "isHidden", .boolean).notNull().defaults(to: false)
			}
			try db.alter(table: "news_sources") { t in
				t.add(column: "sortOrder", .integer).notNull().defaults(to: 0)
				t.add(column: "lastError", .text)
			}
			// Assign initial sort order based on existing insertion order
			let rows = try Row.fetchAll(db, sql: "SELECT id FROM news_sources ORDER BY id")
			for (index, row) in rows.enumerated() {
				let id: Int64 = row["id"]
				try db.execute(
					sql: "UPDATE news_sources SET sortOrder = ? WHERE id = ?",
					arguments: [index, id]
				)
			}
		}

		migrator.registerMigration("v3_fts5") { db in
			// Standalone FTS5 table for full-text search across title, author,
			// summary, and extracted readable body. article_id is UNINDEXED so it
			// acts as a foreign key without being tokenised.
			try db.execute(sql: """
				CREATE VIRTUAL TABLE IF NOT EXISTS articles_fts USING fts5(
					article_id UNINDEXED,
					title,
					author,
					summary,
					body,
					tokenize = 'unicode61 remove_diacritics 2'
				)
				""")

			// Backfill existing articles into the FTS index.
			try db.execute(sql: """
				INSERT INTO articles_fts (article_id, title, author, summary, body)
				SELECT id,
				       COALESCE(title, ''),
				       COALESCE(author, ''),
				       COALESCE(summary, ''),
				       COALESCE(readableContent, '')
				FROM articles
				""")
		}

		try migrator.migrate(dbQueue)
	}
}
