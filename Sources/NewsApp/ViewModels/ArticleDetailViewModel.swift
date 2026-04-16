import Foundation

@MainActor
final class ArticleDetailViewModel: ObservableObject {
	@Published var isLoadingContent = false
	@Published var isProcessingAI = false
	@Published var isGeneratingQuiz = false
	@Published var quizQuestions: [QuizQuestion] = []
	@Published var errorMessage: String?

	private let articleRepo = ArticleRepository()
	private let quizRepo = QuizRepository()
	private var rewriteTask: Task<OllamaArticleResult?, Never>?

	func loadContent(for article: Article) async -> ReadabilityResult? {
		// Fast path: return cached Readability HTML from DB without touching WKWebView.
		do {
			if let html = try articleRepo.fetchReadableContent(id: article.id) {
				return ReadabilityResult(
					title: article.title,
					byline: article.author,
					htmlContent: html,
					textContent: html.strippingHTML,
					excerpt: article.summary
				)
			}
		} catch {}

		guard let url = URL(string: article.articleURL) else { return nil }

		isLoadingContent = true
		defer { isLoadingContent = false }

		do {
			let result = try await ReadabilityService.shared.extract(from: url)
			// Persist for future opens so WKWebView is never needed again for this article.
			try? articleRepo.updateContent(
				id: article.id,
				rawContent: result.htmlContent,
				readableContent: result.htmlContent
			)
			return result
		} catch {
			errorMessage = "Could not load article: \(error.localizedDescription)"
			return nil
		}
	}

	func generateQuiz(
		article: Article,
		content: String,
		endpoint: String,
		model: String
	) async {
		guard !isGeneratingQuiz else { return }
		isGeneratingQuiz = true
		quizQuestions = []
		defer { isGeneratingQuiz = false }

		do {
			quizQuestions = try await OllamaService.shared.generateQuiz(
				title: article.title,
				content: content,
				endpoint: endpoint,
				model: model
			)
		} catch {
			errorMessage = "Quiz generation failed: \(error.localizedDescription)"
		}
	}

	func saveQuizResult(articleId: String, articleTitle: String, score: Int, total: Int) {
		let result = QuizResult(
			id: nil,
			articleId: articleId,
			articleTitle: articleTitle,
			score: score,
			totalQuestions: total,
			completedAt: Date()
		)
		try? quizRepo.insert(result)
	}

	func rewriteWithAI(
		article: Article,
		content: String,
		endpoint: String,
		model: String,
		customPrompt: String = ""
	) async -> OllamaArticleResult? {
		// Cancel any in-flight rewrite before starting a new one so rapid successive
		// taps don't queue up multiple Ollama requests.
		rewriteTask?.cancel()

		isProcessingAI = true
		defer { isProcessingAI = false }

		let task: Task<OllamaArticleResult?, Never> = Task {
			do {
				return try await OllamaService.shared.rewriteAndSummarize(
					title: article.title,
					content: content,
					endpoint: endpoint,
					model: model,
					customPromptTemplate: customPrompt
				)
			} catch {
				if !Task.isCancelled {
					self.errorMessage = "AI summary failed: \(error.localizedDescription)"
				}
				return nil
			}
		}
		rewriteTask = task
		return await task.value
	}
}
