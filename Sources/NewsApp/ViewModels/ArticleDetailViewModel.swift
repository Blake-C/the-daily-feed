import Foundation

@MainActor
final class ArticleDetailViewModel: ObservableObject {
	@Published var isLoadingContent = false
	@Published var isProcessingAI = false
	@Published var errorMessage: String?

	private let articleRepo = ArticleRepository()
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
					self.errorMessage = "AI rewrite failed: \(error.localizedDescription)"
				}
				return nil
			}
		}
		rewriteTask = task
		return await task.value
	}
}
