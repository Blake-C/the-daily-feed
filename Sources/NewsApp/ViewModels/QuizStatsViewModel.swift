import Foundation

@MainActor
final class QuizStatsViewModel: ObservableObject {
	@Published var todayStats = QuizPeriodStats(correct: 0, total: 0, quizCount: 0)
	@Published var monthStats = QuizPeriodStats(correct: 0, total: 0, quizCount: 0)
	@Published var yearStats  = QuizPeriodStats(correct: 0, total: 0, quizCount: 0)
	@Published var recentResults: [QuizResult] = []

	private let repo = QuizRepository()

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
