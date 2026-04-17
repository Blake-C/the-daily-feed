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
		var availableContent = content

		for number in 1...5 {
			quizStatusMessage = "Generating question \(number) of 5…"
			var accepted: QuizQuestion?
			var lastError: Error?
			// Up to 3 attempts: handles both transient errors and duplicate questions.
			for _ in 0..<3 {
				do {
					let q = try await OllamaService.shared.generateQuizQuestion(
						number: number,
						title: article.title,
						content: availableContent,
						previousQuestions: generated,
						endpoint: endpoint,
						model: model
					)
					if Self.isDuplicate(q, among: generated) { continue }
					accepted = q
					lastError = nil
					break
				} catch {
					lastError = error
				}
			}
			if let q = accepted {
				generated.append(q)
				quizQuestions = generated
				// Strip the used paragraph so subsequent questions can't draw from it.
				if let hint = q.paragraphHint, !hint.isEmpty {
					availableContent = Self.stripParagraph(containing: hint, from: availableContent)
				}
			} else if let err = lastError {
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

	private static let similarityStopWords: Set<String> = [
		"the", "a", "an", "is", "are", "was", "were", "did", "do", "does",
		"in", "on", "at", "to", "of", "and", "or", "but", "not", "this",
		"that", "it", "its", "for", "with", "by", "from", "be", "been",
		"have", "has", "had", "which", "what", "when", "how", "who",
	]

	/// Returns true if `candidate` tests the same fact as any question in `existing`,
	/// measured by Jaccard similarity on content words (threshold: 0.45).
	private static func isDuplicate(_ candidate: QuizQuestion, among existing: [QuizQuestion]) -> Bool {
		let words: (String) -> Set<String> = { text in
			Set(
				text.lowercased()
					.components(separatedBy: .alphanumerics.inverted)
					.filter { !$0.isEmpty && !similarityStopWords.contains($0) }
			)
		}
		let candidateWords = words(candidate.question)
		guard candidateWords.count >= 3 else { return false }
		return existing.contains { q in
			let existingWords = words(q.question)
			guard existingWords.count >= 3 else { return false }
			let intersection = candidateWords.intersection(existingWords).count
			let union = candidateWords.union(existingWords).count
			return Double(intersection) / Double(union) >= 0.45
		}
	}

	/// Removes the paragraph containing `hint` from `content` so it can't be reused.
	/// Matches on the first 40 characters of the hint for robustness against minor truncation.
	private static func stripParagraph(containing hint: String, from content: String) -> String {
		let needle = String(hint.lowercased().prefix(40))
		return content
			.components(separatedBy: "\n")
			.filter { !$0.lowercased().contains(needle) }
			.joined(separator: "\n")
	}

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
