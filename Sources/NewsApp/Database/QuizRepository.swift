import Foundation
import GRDB

final class QuizRepository: @unchecked Sendable {
	private let db: DatabaseQueue

	init(db: DatabaseQueue = DatabaseManager.shared.dbQueue) {
		self.db = db
	}

	func insert(_ result: QuizResult) throws {
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
