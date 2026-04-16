import Foundation

@MainActor
final class DailySummaryViewModel: ObservableObject {
	@Published var articles: [Article] = []

	private let articleRepo = ArticleRepository()
	private var notificationTask: Task<Void, Never>?

	init() {
		notificationTask = Task { [weak self] in
			for await _ in NotificationCenter.default.notifications(named: .dailySummaryUpdated) {
				self?.load()
			}
		}
	}

	deinit {
		notificationTask?.cancel()
	}

	func load() {
		articles = (try? articleRepo.fetchTodaysReadArticles()) ?? []
	}
}
