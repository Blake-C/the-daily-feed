import CryptoKit
import Foundation

@Observable
@MainActor
final class ArticleDetailViewModel {
	var isLoadingContent = false
	var isProcessingAI = false
	var isGeneratingQuiz = false
	var quizQuestions: [QuizQuestion] = []
	var quizStatusMessage: String?
	var disputeResults: [Int: QuizDisputeResult] = [:]
	var disputingIndices: Set<Int> = []
	var errorMessage: String?

	private let articleRepo = ArticleRepository()
	private let quizRepo = QuizRepository()
	private var rewriteTask: Task<OllamaArticleResult?, Never>?
	private var lastSavedQuizResultId: Int64?

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
			try? articleRepo.updateContent(id: article.id, readableContent: result.htmlContent)
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

		// Serve cached questions immediately without hitting Ollama.
		if let cached = loadCachedQuiz(for: article.id) {
			quizQuestions = cached
			return
		}

		isGeneratingQuiz = true
		quizQuestions = []
		quizStatusMessage = nil
		defer { isGeneratingQuiz = false; quizStatusMessage = nil }

		var generated: [QuizQuestion] = []

		for number in 1...5 {
			quizStatusMessage = "Generating question \(number) of 5…"
			var lastError: Error?
			for _ in 0..<2 {
				do {
					let q = try await OllamaService.shared.generateQuizQuestion(
						number: number,
						title: article.title,
						content: content,
						previousQuestions: generated,
						endpoint: endpoint,
						model: model
					)
					generated.append(q)
					quizQuestions = generated
					lastError = nil
					break
				} catch {
					lastError = error
				}
			}
			if let err = lastError {
				// Skip this question but continue with the rest
				errorMessage = "Skipped question \(number): \(err.localizedDescription)"
			}
		}

		if generated.isEmpty {
			errorMessage = "Quiz generation failed — no questions could be generated."
		} else {
			cacheQuiz(generated, for: article.id)
		}
	}

	func regenerateQuiz(article: Article, content: String, endpoint: String, model: String) async {
		UserDefaults.standard.removeObject(forKey: quizCacheKey(article.id))
		quizQuestions = []
		disputeResults = [:]
		disputingIndices = []
		await generateQuiz(article: article, content: content, endpoint: endpoint, model: model)
	}

	// MARK: - Quiz cache

	private func quizCacheKey(_ articleId: String) -> String {
		let digest = SHA256.hash(data: Data(articleId.utf8))
		let hex = digest.prefix(16).map { String(format: "%02x", $0) }.joined()
		return "quiz_q_\(hex)"
	}

	private func loadCachedQuiz(for articleId: String) -> [QuizQuestion]? {
		guard
			let data = UserDefaults.standard.data(forKey: quizCacheKey(articleId)),
			let questions = try? JSONDecoder().decode([QuizQuestion].self, from: data),
			!questions.isEmpty
		else { return nil }
		return questions
	}

	private func cacheQuiz(_ questions: [QuizQuestion], for articleId: String) {
		guard let data = try? JSONEncoder().encode(questions) else { return }
		UserDefaults.standard.set(data, forKey: quizCacheKey(articleId))
	}

	func disputeAnswer(
		questionIndex: Int,
		question: QuizQuestion,
		userChosenIndex: Int,
		content: String,
		endpoint: String,
		model: String
	) async {
		guard !disputingIndices.contains(questionIndex),
			  disputeResults[questionIndex] == nil else { return }

		disputingIndices.insert(questionIndex)
		defer { disputingIndices.remove(questionIndex) }

		do {
			let result = try await OllamaService.shared.reviewQuizAnswer(
				questionText: question.question,
				options: question.options,
				originalCorrectIndex: question.correctIndex,
				userChosenIndex: userChosenIndex,
				articleExcerpt: content,
				endpoint: endpoint,
				model: model
			)
			disputeResults[questionIndex] = result
		} catch {
			errorMessage = "Dispute review failed: \(error.localizedDescription)"
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
		lastSavedQuizResultId = try? quizRepo.insert(result)
	}

	func updateLastQuizScore(_ score: Int, total: Int) {
		guard let id = lastSavedQuizResultId else { return }
		try? quizRepo.updateScore(id: id, score: score, total: total)
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
