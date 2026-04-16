import Foundation

@MainActor
final class SuggestedSourcesViewModel: ObservableObject {
	@Published var suggestions: [SuggestedSource] = []
	@Published var isRefreshing = false

	private var notificationTask: Task<Void, Never>?

	init() {
		load()
		notificationTask = Task { [weak self] in
			for await _ in NotificationCenter.default.notifications(named: .suggestedSourcesUpdated) {
				self?.load()
			}
		}
	}

	deinit {
		notificationTask?.cancel()
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

	func refresh(currentSourceNames: String, endpoint: String, model: String) {
		guard !isRefreshing else { return }
		isRefreshing = true
		Task {
			defer { isRefreshing = false }
			await SuggestedSourcesService.shared.refresh(
				currentSourceNames: currentSourceNames,
				endpoint: endpoint,
				model: model
			)
			load()
		}
	}

	func refreshIfNeeded(currentSourceNames: String, endpoint: String, model: String) {
		Task {
			let needed = await SuggestedSourcesService.shared.needsRefresh()
			guard needed else { return }
			isRefreshing = true
			defer { isRefreshing = false }
			await SuggestedSourcesService.shared.refresh(
				currentSourceNames: currentSourceNames,
				endpoint: endpoint,
				model: model
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
