import Foundation

extension Notification.Name {
	static let suggestedSourcesUpdated = Notification.Name("com.thedailyfeed.suggestedSourcesUpdated")
}

/// Background actor that fetches reputable RSS source suggestions from Ollama,
/// validates each via FeedDiscoveryService, and caches the results in UserDefaults.
/// Refreshes at most once per 24 hours.
actor SuggestedSourcesService {
	static let shared = SuggestedSourcesService()

	private let suggestionsKey = "suggestedSources"
	private let lastFetchKey = "suggestedSourcesLastFetch"
	private let refreshInterval: TimeInterval = 86_400 // 24 hours

	private var isRefreshing = false

	private init() {}

	// MARK: - Public

	func loadSuggestions() -> [SuggestedSource] {
		guard
			let data = UserDefaults.standard.data(forKey: suggestionsKey),
			let suggestions = try? JSONDecoder().decode([SuggestedSource].self, from: data)
		else { return [] }
		return suggestions
	}

	func needsRefresh() -> Bool {
		let suggestions = loadSuggestions()
		if suggestions.isEmpty { return true }
		let lastFetch = UserDefaults.standard.object(forKey: lastFetchKey) as? Date ?? .distantPast
		return Date().timeIntervalSince(lastFetch) >= refreshInterval
	}

	func refreshIfNeeded(currentSourceNames: String, endpoint: String, model: String) async {
		guard needsRefresh() else { return }
		await refresh(currentSourceNames: currentSourceNames, endpoint: endpoint, model: model)
	}

	func refresh(currentSourceNames: String, endpoint: String, model: String) async {
		guard !isRefreshing else { return }
		isRefreshing = true
		defer { isRefreshing = false }

		do {
			let ollamaSuggestions = try await OllamaService.shared.suggestSources(
				currentSourceNames: currentSourceNames,
				endpoint: endpoint,
				model: model
			)

			var validated: [SuggestedSource] = []
			for suggestion in ollamaSuggestions {
				guard let discovery = await FeedDiscoveryService.shared.discover(urlString: suggestion.website) else {
					continue
				}
				let source = SuggestedSource(
					id: UUID(),
					name: suggestion.name,
					feedURL: discovery.feedURL,
					websiteURL: suggestion.website,
					summary: suggestion.summary,
					category: suggestion.category,
					suggestedAt: Date()
				)
				validated.append(source)
			}

			guard !validated.isEmpty else { return }

			save(validated)
			UserDefaults.standard.set(Date(), forKey: lastFetchKey)

			await MainActor.run {
				NotificationCenter.default.post(name: .suggestedSourcesUpdated, object: nil)
			}
		} catch {
			// Fail silently — suggestions are best-effort
		}
	}

	func markAdded(id: UUID) {
		var suggestions = loadSuggestions()
		guard let idx = suggestions.firstIndex(where: { $0.id == id }) else { return }
		suggestions[idx].isAlreadyAdded = true
		save(suggestions)
	}

	func dismiss(id: UUID) {
		var suggestions = loadSuggestions()
		suggestions.removeAll { $0.id == id }
		save(suggestions)
		// Reset last-fetch so the next view-appear can pull fresh suggestions sooner.
		UserDefaults.standard.removeObject(forKey: lastFetchKey)
	}

	// MARK: - Private

	private func save(_ suggestions: [SuggestedSource]) {
		guard let data = try? JSONEncoder().encode(suggestions) else { return }
		UserDefaults.standard.set(data, forKey: suggestionsKey)
	}
}
