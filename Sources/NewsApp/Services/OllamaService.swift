import Foundation

final class OllamaService: @unchecked Sendable {
	static let shared = OllamaService()
	private init() {}

	// MARK: - Public API

	static let defaultPromptTemplate = """
		You are a concise, neutral news editor. Given the following article, do two things:
		1. Write a clear, factual, non-clickbait headline (max 12 words).
		2. Write a 2–3 sentence summary of the key facts.

		Respond ONLY in this JSON format (no markdown, no extra text):
		{"headline": "...", "summary": "..."}

		Article title: {title}

		Article content:
		{content}
		"""

	/// Returns a rewritten headline + summary for the given article text.
	/// - Parameter customPromptTemplate: Optional template overriding the default.
	///   Use `{title}` and `{content}` as placeholders. When empty the built-in default is used.
	func rewriteAndSummarize(
		title: String,
		content: String,
		endpoint: String,
		model: String,
		customPromptTemplate: String = ""
	) async throws -> OllamaArticleResult {
		let template = customPromptTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
			? Self.defaultPromptTemplate
			: customPromptTemplate
		let prompt = template
			.replacingOccurrences(of: "{title}", with: title)
			.replacingOccurrences(of: "{content}", with: String(content.prefix(4000)))

		let responseText = try await generate(prompt: prompt, endpoint: endpoint, model: model)
		return try parseArticleResult(from: responseText)
	}

	// MARK: - Article Quiz

	// Fixed template — {title}/{content} are the only substitutions, both truncated
	// before use. Output is display-only question text; never executed.
	static let quizPromptTemplate = """
		You are a comprehension quiz generator for a news reader application.
		Given the article below, generate exactly 5 questions to test the reader's understanding and encourage deeper thinking.

		Rules:
		- Include at most 2 true/false questions and at least 3 multiple-choice questions
		- 1 to 2 questions may explore related topics or broader context beyond the article text to encourage further research
		- Multiple-choice questions must have exactly 4 answer options
		- True/false questions must use exactly ["True", "False"] as the options array, in that order
		- correctIndex is the 0-based index of the correct answer in the options array
		- explanation is one sentence explaining why the answer is correct

		Respond ONLY in valid JSON with no markdown or extra text:
		{"questions": [
		  {"type": "truefalse", "question": "...", "options": ["True", "False"], "correctIndex": 0, "explanation": "..."},
		  {"type": "multiplechoice", "question": "...", "options": ["A", "B", "C", "D"], "correctIndex": 2, "explanation": "..."}
		]}

		Article title: {title}

		Article content:
		{content}
		"""

	/// Generates 5 comprehension and related-topic questions for the given article.
	func generateQuiz(
		title: String,
		content: String,
		endpoint: String,
		model: String
	) async throws -> [QuizQuestion] {
		let safeTitle = String(title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))
		let safeContent = String(content.trimmingCharacters(in: .whitespacesAndNewlines).prefix(4_000))

		let prompt = Self.quizPromptTemplate
			.replacingOccurrences(of: "{title}", with: safeTitle)
			.replacingOccurrences(of: "{content}", with: safeContent)

		let responseText = try await generate(prompt: prompt, endpoint: endpoint, model: model)
		return try parseQuiz(from: responseText)
	}

	private func parseQuiz(from text: String) throws -> [QuizQuestion] {
		let cleaned = extractJSONObject(from: text)
		guard
			let data = cleaned.data(using: .utf8),
			let result = try? JSONDecoder().decode(OllamaQuizResult.self, from: data),
			!result.questions.isEmpty
		else {
			throw NewsError.parseFailed("Could not parse quiz JSON: \(cleaned.prefix(200))")
		}
		return result.questions
	}

	// MARK: - Source Suggestions

	// Fixed template — {sources} is the only user-influenced substitution and is
	// truncated to 500 chars before use, limiting prompt-injection surface area.
	// Output is display-only (name, URL, description) and never executed.
	static let sourceSuggestionPromptTemplate = """
		You are a news feed curator. The user currently reads these news sources: {sources}

		Suggest exactly 6 reputable news sources they might enjoy but may not already follow.
		Choose only well-established outlets that:
		- Have been publishing for at least 10 years
		- Are widely recognised journalism organisations
		- Are free from misinformation and have editorial standards
		- Provide a publicly accessible RSS or Atom feed on their website
		- Cover topics related to what the user already reads, or complementary areas

		For each suggestion provide the main website homepage URL only (not the RSS feed URL).

		Respond ONLY in valid JSON with no markdown or extra text:
		{"suggestions": [
		  {"name": "...", "website": "https://...", "summary": "One sentence description.", "category": "..."},
		  ...
		]}
		"""

	/// Returns up to 6 source suggestions from Ollama based on the user's current feed names.
	/// - Parameter currentSourceNames: Comma-separated source names, used as context.
	func suggestSources(
		currentSourceNames: String,
		endpoint: String,
		model: String
	) async throws -> [OllamaSourceSuggestion] {
		let safeContext = String(currentSourceNames.trimmingCharacters(in: .whitespacesAndNewlines).prefix(500))
		let prompt = Self.sourceSuggestionPromptTemplate
			.replacingOccurrences(of: "{sources}", with: safeContext.isEmpty ? "various news sources" : safeContext)
		let responseText = try await generate(prompt: prompt, endpoint: endpoint, model: model)
		return try parseSourceSuggestions(from: responseText)
	}

	private func parseSourceSuggestions(from text: String) throws -> [OllamaSourceSuggestion] {
		let cleaned = extractJSONObject(from: text)
		guard
			let data = cleaned.data(using: .utf8),
			let result = try? JSONDecoder().decode(OllamaSourceSuggestionsResult.self, from: data)
		else {
			throw NewsError.parseFailed("Could not parse source suggestions JSON: \(cleaned.prefix(200))")
		}
		return result.suggestions
	}

	// MARK: - Daily Summary

	// Fixed prompt — never interpolated from user-controlled data except via the
	// whitelisted {title}/{content} placeholders, which are truncated before use.
	// This limits prompt-injection surface: a malicious feed title or body could
	// attempt to override instructions, but the output is display-only text so the
	// only realistic impact is garbled or irrelevant summary text.
	static let dailySummaryPromptTemplate = """
		You are a personal news briefing assistant. Summarize this article for a daily reading digest.
		In 2–3 sentences explain: what happened, why it matters, and the single key takeaway.
		Be factual and concise. Do not add opinions or speculation.

		Respond ONLY in valid JSON (no markdown, no extra text):
		{"briefing": "..."}

		Article title: {title}

		Article content:
		{content}
		"""

	/// Generates a 2–3 sentence daily briefing for a single article.
	/// - Parameters:
	///   - title: Article headline. Truncated to 200 characters before sending.
	///   - content: Article body. Truncated to 3 000 characters before sending.
	func summarizeForDaily(
		title: String,
		content: String,
		endpoint: String,
		model: String
	) async throws -> String {
		let safeTitle = String(title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))
		let safeContent = String(content.trimmingCharacters(in: .whitespacesAndNewlines).prefix(3_000))

		let prompt = Self.dailySummaryPromptTemplate
			.replacingOccurrences(of: "{title}", with: safeTitle)
			.replacingOccurrences(of: "{content}", with: safeContent)

		let responseText = try await generate(prompt: prompt, endpoint: endpoint, model: model)
		return try parseDailySummary(from: responseText)
	}

	private func parseDailySummary(from text: String) throws -> String {
		let cleaned = extractJSONObject(from: text)
		guard
			let data = cleaned.data(using: .utf8),
			let result = try? JSONDecoder().decode(OllamaDailySummaryResult.self, from: data)
		else {
			throw NewsError.parseFailed("Could not parse daily summary JSON: \(cleaned.prefix(200))")
		}
		return result.briefing
	}

	// MARK: - Private

	/// Extracts the outermost JSON object from a model response that may include
	/// preamble text, markdown code fences, or trailing commentary.
	private func extractJSONObject(from text: String) -> String {
		let stripped = text
			.replacingOccurrences(of: "```json", with: "")
			.replacingOccurrences(of: "```", with: "")
		guard
			let start = stripped.firstIndex(of: "{"),
			let end   = stripped.lastIndex(of: "}")
		else { return stripped.trimmingCharacters(in: .whitespacesAndNewlines) }
		return String(stripped[start...end])
	}

	private func generate(prompt: String, endpoint: String, model: String) async throws -> String {
		guard let baseURL = URL(string: endpoint) else {
			throw NewsError.invalidURL(endpoint)
		}
		let url = baseURL.appendingPathComponent("api/generate")

		var request = URLRequest(url: url, timeoutInterval: 60)
		request.httpMethod = "POST"
		request.setValue("application/json", forHTTPHeaderField: "Content-Type")

		let body: [String: Any] = [
			"model": model,
			"prompt": prompt,
			"stream": false,
		]
		request.httpBody = try JSONSerialization.data(withJSONObject: body)

		let (data, response) = try await URLSession.shared.data(for: request)

		guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
			throw NewsError.ollamaUnavailable
		}

		let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
		guard let text = json?["response"] as? String else {
			throw NewsError.parseFailed("Unexpected Ollama response shape")
		}
		return text
	}

	private func parseArticleResult(from text: String) throws -> OllamaArticleResult {
		let cleaned = extractJSONObject(from: text)
		guard
			let data = cleaned.data(using: .utf8),
			let result = try? JSONDecoder().decode(OllamaArticleResult.self, from: data)
		else {
			throw NewsError.parseFailed("Could not parse Ollama JSON: \(cleaned.prefix(200))")
		}
		return result
	}
}

struct OllamaArticleResult: Codable {
	let headline: String
	let summary: String
}

struct OllamaDailySummaryResult: Codable {
	let briefing: String
}

struct OllamaQuizResult: Codable {
	let questions: [QuizQuestion]
}

struct OllamaSourceSuggestion: Codable {
	let name: String
	let website: String
	let summary: String
	let category: String
}

struct OllamaSourceSuggestionsResult: Codable {
	let suggestions: [OllamaSourceSuggestion]
}
