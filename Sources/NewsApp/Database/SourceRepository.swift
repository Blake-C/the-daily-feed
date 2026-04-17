import Foundation
import GRDB

final class SourceRepository: @unchecked Sendable {
	private let db: DatabaseQueue

	init(db: DatabaseQueue = DatabaseManager.shared.dbQueue) {
		self.db = db
	}

	func fetchAll() throws -> [NewsSource] {
		try db.read { conn in
			try NewsSource.order(NewsSource.Columns.sortOrder).fetchAll(conn)
		}
	}

	func fetchEnabled() throws -> [NewsSource] {
		try db.read { conn in
			try NewsSource
				.filter(NewsSource.Columns.isEnabled == true)
				.order(NewsSource.Columns.sortOrder)
				.fetchAll(conn)
		}
	}

	func insert(_ source: inout NewsSource) throws {
		try db.write { conn in
			// Assign sort order after existing entries
			let max = try Int.fetchOne(conn, sql: "SELECT MAX(sortOrder) FROM news_sources") ?? -1
			source.sortOrder = max + 1
			try source.insert(conn)
		}
	}

	func update(_ source: NewsSource) throws {
		guard let id = source.id else { return }
		try db.write { conn in
			try conn.execute(
				sql: """
					UPDATE news_sources
					SET name = ?, url = ?, type = ?, faviconURL = ?, rating = ?,
					    isEnabled = ?, tags = ?, sortOrder = ?
					WHERE id = ?
					""",
				arguments: [
					source.name, source.url, source.type.rawValue,
					source.faviconURL, source.rating,
					source.isEnabled, source.tags, source.sortOrder,
					id,
				]
			)
		}
	}

	func delete(id: Int64) throws {
		try db.write { conn in
			_ = try NewsSource.deleteOne(conn, key: id)
		}
	}

	func updateLastFetched(id: Int64, date: Date) throws {
		try db.write { conn in
			try conn.execute(
				sql: "UPDATE news_sources SET lastFetchedAt = ?, lastError = NULL WHERE id = ?",
				arguments: [date, id]
			)
		}
	}

	func setError(id: Int64, message: String) throws {
		try db.write { conn in
			try conn.execute(
				sql: "UPDATE news_sources SET lastError = ? WHERE id = ?",
				arguments: [message, id]
			)
		}
	}

	/// Sets badgeClearedAt = now for one or all sources, causing the unread badge
	/// to show only articles published after this timestamp going forward.
	/// Pass nil for sourceId to clear badges for every source.
	func clearBadge(sourceId: Int64?) throws {
		let now = Date()
		try db.write { conn in
			if let sourceId {
				try conn.execute(
					sql: "UPDATE news_sources SET badgeClearedAt = ? WHERE id = ?",
					arguments: [now, sourceId]
				)
			} else {
				try conn.execute(
					sql: "UPDATE news_sources SET badgeClearedAt = ?",
					arguments: [now]
				)
			}
		}
	}

	/// Persist a new sort order after drag-and-drop reordering.
	func reorder(ids: [Int64]) throws {
		try db.write { conn in
			for (index, id) in ids.enumerated() {
				try conn.execute(
					sql: "UPDATE news_sources SET sortOrder = ? WHERE id = ?",
					arguments: [index, id]
				)
			}
		}
	}

	func seedDefaultSources() throws {
		let existing = try fetchAll()
		guard existing.isEmpty else { return }

		guard
			let url = Bundle.module.url(forResource: "DefaultSources", withExtension: "json"),
			let data = try? Data(contentsOf: url),
			let defaults = try? JSONDecoder().decode([DefaultSource].self, from: data)
		else { return }

		try db.write { conn in
			for (index, d) in defaults.enumerated() {
				var source = NewsSource(
					id: nil,
					name: d.name,
					url: d.url,
					type: SourceType(rawValue: d.type) ?? .rss,
					faviconURL: nil,
					rating: 0,
					isEnabled: true,
					tags: d.tags.joined(separator: ","),
					addedAt: Date(),
					lastFetchedAt: nil,
					sortOrder: index,
					lastError: nil
				)
				try source.insert(conn)
			}
		}
	}
}

private struct DefaultSource: Codable {
	let name: String
	let url: String
	let type: String
	let tags: [String]
}
