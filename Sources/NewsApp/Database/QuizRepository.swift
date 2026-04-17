import Foundation
import GRDB

final class QuizRepository: @unchecked Sendable {
	private let db: DatabaseQueue

	init(db: DatabaseQueue = DatabaseManager.shared.dbQueue) {
		self.db = db
	}

	@discardableResult
	func insert(_ result: QuizResult) throws -> Int64 {
		try db.write { conn in
			try conn.execute(
				sql: """
					INSERT INTO quiz_results (articleId, articleTitle, score, totalQuestions, completedAt)
					VALUES (?, ?, ?, ?, ?)
					""",
				arguments: [
					result.articleId,
					result.articleTitle,
					result.score,
					result.totalQuestions,
					result.completedAt,
				]
			)
			return conn.lastInsertedRowID
		}
	}

	func updateScore(id: Int64, score: Int, total: Int) throws {
		try db.write { conn in
			try conn.execute(
				sql: "UPDATE quiz_results SET score = ?, totalQuestions = ? WHERE id = ?",
				arguments: [score, total, id]
			)
		}
	}

	func fetchAll(limit: Int = 50) throws -> [QuizResult] {
		try db.read { conn in
			let rows = try Row.fetchAll(
				conn,
				sql: "SELECT * FROM quiz_results ORDER BY completedAt DESC LIMIT ?",
				arguments: [limit]
			)
			return rows.map(QuizResult.init)
		}
	}

	func deleteAll() throws {
		try db.write { conn in
			try conn.execute(sql: "DELETE FROM quiz_results")
		}
		// Also purge all per-article cached question sets from UserDefaults.
		let defaults = UserDefaults.standard
		defaults.dictionaryRepresentation().keys
			.filter { $0.hasPrefix("quiz_q_") }
			.forEach { defaults.removeObject(forKey: $0) }
	}

	func fetchStats(from startDate: Date) throws -> QuizPeriodStats {
		try db.read { conn in
			let row = try Row.fetchOne(
				conn,
				sql: """
					SELECT COALESCE(SUM(score), 0)          AS totalScore,
					       COALESCE(SUM(totalQuestions), 0) AS totalQs,
					       COUNT(*)                          AS quizCount
					FROM quiz_results
					WHERE completedAt >= ?
					""",
				arguments: [startDate]
			)
			return QuizPeriodStats(
				correct:   row?["totalScore"]  ?? 0,
				total:     row?["totalQs"]     ?? 0,
				quizCount: row?["quizCount"]   ?? 0
			)
		}
	}
}

private extension QuizResult {
	init(row: Row) {
		id             = row["id"]
		articleId      = row["articleId"]
		articleTitle   = row["articleTitle"]
		score          = row["score"]
		totalQuestions = row["totalQuestions"]
		completedAt    = row["completedAt"]
	}
}
