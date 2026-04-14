import Foundation
import GRDB

final class TagRepository: @unchecked Sendable {
	private let db: DatabaseQueue

	init(db: DatabaseQueue = DatabaseManager.shared.dbQueue) {
		self.db = db
	}

	func fetchAll() throws -> [Tag] {
		try db.read { conn in
			try Tag.order(Tag.Columns.name).fetchAll(conn)
		}
	}

	func fetchActive() throws -> [Tag] {
		try db.read { conn in
			try Tag.filter(Tag.Columns.isActive == true).order(Tag.Columns.name).fetchAll(conn)
		}
	}

	func insert(_ tag: inout Tag) throws {
		try db.write { conn in
			try tag.insert(conn)
		}
	}

	func toggle(id: Int64, isActive: Bool) throws {
		try db.write { conn in
			try conn.execute(
				sql: "UPDATE tags SET isActive = ? WHERE id = ?",
				arguments: [isActive, id]
			)
		}
	}

	func delete(id: Int64) throws {
		try db.write { conn in
			_ = try Tag.deleteOne(conn, key: id)
		}
	}

	func seedDefaultTags() throws {
		try db.write { conn in
			for name in Tag.defaultTags {
				let exists = try Int.fetchOne(
					conn,
					sql: "SELECT COUNT(*) FROM tags WHERE name = ?",
					arguments: [name]
				) ?? 0
				if exists == 0 {
					var tag = Tag(id: nil, name: name, isBuiltIn: true, isActive: false)
					try tag.insert(conn)
				}
			}
		}
	}
}
