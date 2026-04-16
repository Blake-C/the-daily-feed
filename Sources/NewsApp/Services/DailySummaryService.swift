import Foundation

extension Notification.Name {
	static let dailySummaryUpdated = Notification.Name("com.thedailyfeed.dailySummaryUpdated")
}

/// Background actor that generates per-article daily briefings via Ollama.
/// Called silently after an article's readable content is cached so the best
/// possible content is always available for summarization.
actor DailySummaryService {
	static let shared = DailySummaryService()

	private let articleRepo = ArticleRepository()
	private var inProgress: Set<String> = []

	private init() {}

	// MARK: - Public

	/// Summarizes a single article and persists the briefing.
	/// No-ops silently if already in progress, already summarized, or Ollama fails.
	func summarize(articleId: String, title: String, content: String, endpoint: String, model: String) async {
		guard !inProgress.contains(articleId) else { return }

		// Skip if this article already has a summary.
		if let existing = try? articleRepo.fetchDailySummary(id: articleId), !existing.isEmpty {
			return
		}

		inProgress.insert(articleId)
		defer { inProgress.remove(articleId) }

		do {
			let briefing = try await OllamaService.shared.summarizeForDaily(
				title: title,
				content: content,
				endpoint: endpoint,
				model: model
			)
			try articleRepo.updateDailySummary(id: articleId, summary: briefing)
			await MainActor.run {
				NotificationCenter.default.post(name: .dailySummaryUpdated, object: nil)
			}
		} catch {
			// Fail silently — daily summary is best-effort and must never disrupt the user.
		}
	}

	/// Processes any of today's read articles that are missing a daily summary.
	/// Called at startup so summaries are filled in for articles read in a previous session.
	func processPending(endpoint: String, model: String) async {
		guard let articles = try? articleRepo.fetchTodaysReadWithoutSummary() else { return }
		for article in articles {
			// Prefer cached readable content; fall back to feed summary or title.
			let content = (try? articleRepo.fetchReadableContent(id: article.id))
				?? article.summary
				?? article.title
			await summarize(
				articleId: article.id,
				title: article.title,
				content: content,
				endpoint: endpoint,
				model: model
			)
		}
	}
}
