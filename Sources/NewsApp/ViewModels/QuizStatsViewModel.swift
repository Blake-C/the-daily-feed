import Foundation

@Observable
@MainActor
final class QuizStatsViewModel {
	var todayStats = QuizPeriodStats(correct: 0, total: 0, quizCount: 0)
	var monthStats = QuizPeriodStats(correct: 0, total: 0, quizCount: 0)
	var yearStats  = QuizPeriodStats(correct: 0, total: 0, quizCount: 0)
	var recentResults: [QuizResult] = []

	private let repo = QuizRepository()
	private let articleRepo = ArticleRepository()

	func fetchArticle(id: String) -> Article? {
		try? articleRepo.fetchById(id)
	}

	func load() {
		let cal = Calendar.current
		let now = Date()
		let startOfDay   = cal.startOfDay(for: now)
		let startOfMonth = cal.date(from: cal.dateComponents([.year, .month], from: now)) ?? startOfDay
		let startOfYear  = cal.date(from: cal.dateComponents([.year], from: now)) ?? startOfDay

		todayStats  = (try? repo.fetchStats(from: startOfDay))   ?? todayStats
		monthStats  = (try? repo.fetchStats(from: startOfMonth)) ?? monthStats
		yearStats   = (try? repo.fetchStats(from: startOfYear))  ?? yearStats
		recentResults = (try? repo.fetchAll(limit: 50)) ?? []
	}
}
