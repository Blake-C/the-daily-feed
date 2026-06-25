import Foundation

@Observable
@MainActor
final class SuggestedSourcesViewModel {
	var suggestions: [SuggestedSource] = []
	var isRefreshing = false

	private var notificationTask: Task<Void, Never>?

	init() {
		load()
		notificationTask = Task { [weak self] in
			for await _ in NotificationCenter.default.notifications(named: .suggestedSourcesUpdated) {
				self?.load()
			}
		}
	}

	func load() {
		Task {
			let loaded = await SuggestedSourcesService.shared.loadSuggestions()
			suggestions = loaded
		}
	}

	/// Marks suggestions whose feedURL is already in the user's sources.
	func syncAddedState(existingFeedURLs: Set<String>) {
		for idx in suggestions.indices {
			suggestions[idx].isAlreadyAdded = existingFeedURLs.contains(suggestions[idx].feedURL)
		}
	}

	func refresh(currentSourceNames: String, config: AIProviderConfig) {
		guard !isRefreshing else { return }
		isRefreshing = true
		Task {
			defer { isRefreshing = false }
			await SuggestedSourcesService.shared.refresh(
				currentSourceNames: currentSourceNames,
				config: config
			)
			load()
		}
	}

	func refreshIfNeeded(currentSourceNames: String, config: AIProviderConfig) {
		Task {
			let needed = await SuggestedSourcesService.shared.needsRefresh()
			guard needed else { return }
			isRefreshing = true
			defer { isRefreshing = false }
			await SuggestedSourcesService.shared.refresh(
				currentSourceNames: currentSourceNames,
				config: config
			)
			load()
		}
	}

	func markAdded(id: UUID) {
		if let idx = suggestions.firstIndex(where: { $0.id == id }) {
			suggestions[idx].isAlreadyAdded = true
		}
		Task { await SuggestedSourcesService.shared.markAdded(id: id) }
	}

	func dismiss(id: UUID) {
		suggestions.removeAll { $0.id == id }
		Task { await SuggestedSourcesService.shared.dismiss(id: id) }
	}
}
