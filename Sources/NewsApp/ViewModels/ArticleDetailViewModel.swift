import Foundation

@MainActor
final class ArticleDetailViewModel: ObservableObject {
	@Published var isLoadingContent = false
	@Published var isProcessingAI = false
	@Published var errorMessage: String?

	private let articleRepo = ArticleRepository()

	func loadContent(for article: Article) async -> ReadabilityResult? {
		// Return cached content if available
		if article.readableContent != nil { return nil }

		guard let url = URL(string: article.articleURL) else { return nil }

		isLoadingContent = true
		defer { isLoadingContent = false }

		do {
			let result = try await ReadabilityService.shared.extract(from: url)
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
		model: String
	) async -> OllamaArticleResult? {
		isProcessingAI = true
		defer { isProcessingAI = false }

		do {
			let result = try await OllamaService.shared.rewriteAndSummarize(
				title: article.title,
				content: content,
				endpoint: endpoint,
				model: model
			)
			return result
		} catch {
			errorMessage = "AI rewrite failed: \(error.localizedDescription)"
			return nil
		}
	}
}
