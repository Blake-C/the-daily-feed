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
		let safeTitle = String(title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))
		let prompt = template
			.replacingOccurrences(of: "{title}", with: safeTitle)
			.replacingOccurrences(of: "{content}", with: String(content.prefix(4000)))

		let responseText = try await generate(prompt: prompt, endpoint: endpoint, model: model, jsonFormat: true)
		return try parseArticleResult(from: responseText)
	}

	// MARK: - Article Quiz

	/// Generates a single quiz question (1-based index 1–5).
	/// Questions 1–3 are multiple-choice; 4–5 are true/false.
	/// Uses JSON-format mode and a 90 s timeout for better reliability.
	/// Splits plain text into non-empty paragraphs and returns them as
	/// "[1] text\n[2] text…" — capped so the whole string stays under `limit` chars.
	static func numberParagraphs(_ text: String, limit: Int = 3_500) -> String {
		let paras = text
			.components(separatedBy: "\n")
			.map { $0.trimmingCharacters(in: .whitespaces) }
			.filter { !$0.isEmpty }
		var result = ""
		for (i, para) in paras.enumerated() {
			let line = "[\(i + 1)] \(para)\n"
			if result.count + line.count > limit { break }
			result += line
		}
		return result.trimmingCharacters(in: .whitespacesAndNewlines)
	}

	func generateQuizQuestion(
		number: Int,
		title: String,
		content: String,
		previousQuestions: [QuizQuestion] = [],
		endpoint: String,
		model: String
	) async throws -> QuizQuestion {
		let safeTitle   = String(title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))
		let numberedContent = Self.numberParagraphs(
			content.trimmingCharacters(in: .whitespacesAndNewlines)
		)
		let isMC = number <= 3

		let typeRule = isMC
			? "multiple-choice with exactly 4 answer options"
			: "true/false — options must be exactly [\"True\", \"False\"] in that order"

		let example = isMC
			? "{\"type\":\"multiplechoice\",\"question\":\"...\",\"options\":[\"opt1\",\"opt2\",\"opt3\",\"opt4\"],\"correctIndex\":0,\"explanation\":\"...\",\"sourceExcerpt\":\"...\"}"
			: "{\"type\":\"truefalse\",\"question\":\"...\",\"options\":[\"True\",\"False\"],\"correctIndex\":0,\"explanation\":\"...\",\"sourceExcerpt\":\"...\"}"

		// Build the "already used" block for semantic deduplication.
		// Paragraph-level deduplication is handled structurally — used paragraphs are
		// stripped from the content before this call, so they can't be referenced at all.
		var alreadyUsedBlock = ""
		if !previousQuestions.isEmpty {
			let lines = previousQuestions.enumerated().map { idx, q -> String in
				let safeQuestion = q.question
					.replacingOccurrences(of: "\n", with: " ")
					.replacingOccurrences(of: "\r", with: " ")
				return "Q\(idx + 1): \(String(safeQuestion.prefix(160)))"
			}
			alreadyUsedBlock = """

				ALREADY ASKED — do NOT test the same fact or event as any of these, even if phrased differently:
				\(lines.joined(separator: "\n"))

				Yes/no and true/false questions about the same event are duplicates regardless of phrasing.
				"""
		}

		let prompt = """
			Generate ONE \(typeRule) comprehension question about this news article.
			This is question \(number) of 5.\(alreadyUsedBlock)

			IMPORTANT: Every question, every answer option, and the explanation MUST be based exclusively on the article text provided below. Do NOT use your training data, general knowledge, or any information not present in this article. If a fact cannot be found in the article text, do not ask about it.

			Rules:
			- correctIndex: 0-based index of the correct answer
			- explanation: one sentence explaining why the answer is correct, citing the relevant part of the article
			- sourceExcerpt: first 12-15 words verbatim from the paragraph the question is based on (required — every question must come from a unique paragraph not used by any previous question)

			Respond with ONLY this JSON object and nothing else:
			\(example)

			Article title: \(safeTitle)

			Article content (paragraphs are numbered for your reference — use paragraph numbers to identify unique sections):
			\(numberedContent)
			"""

		let responseText = try await generate(
			prompt: prompt,
			endpoint: endpoint,
			model: model,
			jsonFormat: true,
			timeoutInterval: 90
		)
		let cleaned = extractJSONObject(from: responseText)
		guard
			let data     = cleaned.data(using: .utf8),
			let question = try? JSONDecoder().decode(QuizQuestion.self, from: data),
			!question.question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
		else {
			throw NewsError.parseFailed("Could not parse question \(number): \(cleaned.prefix(120))")
		}
		return question
	}

	// MARK: - Answer Dispute

	/// Re-examines a single quiz question when the user disputes the marked answer.
	/// Returns a verdict indicating whether the user's choice was actually correct.
	func reviewQuizAnswer(
		questionText: String,
		options: [String],
		originalCorrectIndex: Int,
		userChosenIndex: Int,
		articleExcerpt: String,
		endpoint: String,
		model: String
	) async throws -> QuizDisputeResult {
		let optionList = options.enumerated()
			.map { "\($0.offset): \($0.element)" }
			.joined(separator: "\n")
		let originalText = options.indices.contains(originalCorrectIndex) ? options[originalCorrectIndex] : "?"
		let userText     = options.indices.contains(userChosenIndex)      ? options[userChosenIndex]      : "?"

		let prompt = """
			You are a fair quiz arbiter reviewing a disputed answer for a news comprehension quiz.

			A student answered a question and was marked wrong. They believe their answer is correct.
			Review the question carefully against the article excerpt and decide who is right.
			If BOTH answers are defensible based on the article, rule in favour of the student.
			If the question cannot be answered from the article at all — because it asks about facts not present in the article — use verdict "question_invalid". This voids the question so it does not count against the student.

			Article excerpt:
			\(String(articleExcerpt.prefix(1_500)))

			Question: \(questionText)

			Answer options (0-indexed):
			\(optionList)

			Original answer key: index \(originalCorrectIndex) ("\(originalText)")
			Student's answer: index \(userChosenIndex) ("\(userText)")

			Respond ONLY with this JSON object (no preamble, no markdown):
			{"verdict": "user_correct" or "original_correct" or "question_invalid", "correctIndex": <number>, "explanation": "<one sentence>"}
			"""

		let responseText = try await generate(prompt: prompt, endpoint: endpoint, model: model, jsonFormat: true)
		return try parseDisputeResult(from: responseText, fallbackIndex: originalCorrectIndex)
	}

	private func parseDisputeResult(from text: String, fallbackIndex: Int) throws -> QuizDisputeResult {
		let cleaned = extractJSONObject(from: text)
		guard let data = cleaned.data(using: .utf8) else {
			throw NewsError.parseFailed("Could not encode dispute response")
		}
		struct DisputeResponse: Decodable {
			let verdict: String
			let correctIndex: Int?
			let explanation: String
		}
		let resp = (try? JSONDecoder().decode(DisputeResponse.self, from: data))
		let verdict = resp?.verdict.lowercased() ?? ""
		let isInvalid = verdict.contains("invalid")
		let userIsCorrect = !isInvalid && verdict.contains("user")
		let corrected = resp?.correctIndex ?? fallbackIndex
		let explanation = resp?.explanation ?? "No explanation provided."
		return QuizDisputeResult(
			userIsCorrect: userIsCorrect,
			isQuestionInvalid: isInvalid,
			correctedAnswerIndex: corrected,
			explanation: explanation
		)
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
		let responseText = try await generate(prompt: prompt, endpoint: endpoint, model: model, jsonFormat: true)
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

		let responseText = try await generate(prompt: prompt, endpoint: endpoint, model: model, jsonFormat: true)
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

	private func generate(
		prompt: String,
		endpoint: String,
		model: String,
		jsonFormat: Bool = false,
		timeoutInterval: TimeInterval = 60
	) async throws -> String {
		guard let baseURL = URL(string: endpoint) else {
			throw NewsError.invalidURL(endpoint)
		}
		// Require HTTPS for any non-localhost endpoint so article content cannot
		// be exfiltrated in plaintext to a remote server the user does not control.
		let scheme = baseURL.scheme?.lowercased() ?? ""
		let host   = baseURL.host?.lowercased() ?? ""
		let isLocal = host == "localhost" || host == "127.0.0.1"
			|| host == "::1" || host == "[::1]"
		guard isLocal || scheme == "https" else {
			throw NewsError.invalidURL("Remote Ollama endpoints must use HTTPS to protect article content in transit.")
		}
		let url = baseURL.appendingPathComponent("api/generate")

		var request = URLRequest(url: url, timeoutInterval: timeoutInterval)
		request.httpMethod = "POST"
		request.setValue("application/json", forHTTPHeaderField: "Content-Type")

		var body: [String: Any] = [
			"model": model,
			"prompt": prompt,
			"stream": false,
		]
		if jsonFormat { body["format"] = "json" }
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

struct OllamaSourceSuggestion: Codable {
	let name: String
	let website: String
	let summary: String
	let category: String
}

struct OllamaSourceSuggestionsResult: Codable {
	let suggestions: [OllamaSourceSuggestion]
}
