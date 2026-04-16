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
		let cleaned = text
			.replacingOccurrences(of: "```json", with: "")
			.replacingOccurrences(of: "```", with: "")
			.trimmingCharacters(in: .whitespacesAndNewlines)
		guard
			let data = cleaned.data(using: .utf8),
			let result = try? JSONDecoder().decode(OllamaDailySummaryResult.self, from: data)
		else {
			throw NewsError.parseFailed("Could not parse daily summary JSON: \(cleaned.prefix(200))")
		}
		return result.briefing
	}

	// MARK: - Private

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
		// Strip possible markdown code fences
		let cleaned = text
			.replacingOccurrences(of: "```json", with: "")
			.replacingOccurrences(of: "```", with: "")
			.trimmingCharacters(in: .whitespacesAndNewlines)

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
