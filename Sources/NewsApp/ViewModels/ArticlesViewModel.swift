import Foundation
import Combine

@MainActor
final class ArticlesViewModel: ObservableObject {
	@Published var articles: [Article] = []
	@Published var isLoading = false
	@Published var isRefreshing = false
	@Published var searchText = ""
	@Published var activeTags: Set<String> = []
	@Published var selectedSourceId: Int64? = nil
	@Published var hideRead = false
	@Published var hasMore = true
	@Published var errorMessage: String?
	@Published var dimThumbnails = false
	/// Increments every time the article list is reset (source/filter change).
	/// Views observe this to scroll back to the top.
	@Published private(set) var scrollResetToken = 0

	/// Called whenever one or more articles are marked read so external observers
	/// (e.g. the sidebar unread badge) can update without polling.
	var onArticleRead: (() -> Void)?

	private let articleRepo = ArticleRepository()
	private let refreshService = FeedRefreshService.shared
	private let pageSize = 40
	private var currentOffset = 0
	private var loadTask: Task<Void, Never>?
	private var searchDebounceTask: Task<Void, Never>?

	// MARK: - Public

	func initialLoad() async {
		reset()
		await loadNextPage()
	}

	func loadNextPage() async {
		guard !isLoading, hasMore else { return }
		isLoading = true
		defer { isLoading = false }

		let query = buildQuery(offset: currentOffset)
		do {
			let newArticles = try articleRepo.fetch(query: query)
			if newArticles.isEmpty || newArticles.count < pageSize {
				hasMore = false
			}
			articles.append(contentsOf: newArticles)
			currentOffset += newArticles.count
		} catch {
			errorMessage = error.localizedDescription
		}
	}

	/// Call when the user scrolls near the last visible article.
	func prefetchIfNeeded(currentIndex: Int) {
		let threshold = articles.count - 20
		guard currentIndex >= threshold, !isLoading, hasMore else { return }
		loadTask?.cancel()
		loadTask = Task { await loadNextPage() }
	}

	/// Refreshes all enabled sources.
	/// - Parameter notifyIfNew: When `true`, posts a system notification if new
	///   articles are fetched. Pass `true` only for background/auto-refresh calls
	///   so the user is not notified when they manually trigger a refresh.
	func refresh(notifyIfNew: Bool = false) async {
		isRefreshing = true
		defer { isRefreshing = false }
		let result = await refreshService.refreshAll()
		if notifyIfNew {
			await NotificationService.shared.notifyNewArticles(count: result.fetched)
		}
		reset()
		await loadNextPage()
	}

	func applySearch(_ text: String) {
		searchText = text
		// Debounce: cancel any pending query and wait 300 ms before hitting the DB,
		// so rapid keystrokes don't fire a full query on every character.
		searchDebounceTask?.cancel()
		searchDebounceTask = Task {
			try? await Task.sleep(for: .milliseconds(300))
			guard !Task.isCancelled else { return }
			reset()
			await loadNextPage()
		}
	}

	func toggleTag(_ tag: String) {
		// Exclusive: selecting a tag deselects all others; tapping the active tag clears filters.
		if activeTags == [tag] {
			activeTags = []
		} else {
			activeTags = [tag]
		}
		reset()
		loadTask = Task { await loadNextPage() }
	}

	func filterBySource(_ id: Int64?) {
		selectedSourceId = id
		activeTags = []   // Clear tag filters so all articles from the source show
		reset()
		loadTask = Task { await loadNextPage() }
	}

	func clearAllTagFilters() {
		activeTags = []
		reset()
		loadTask = Task { await loadNextPage() }
	}

	func toggleHideRead() {
		hideRead.toggle()
		reset()
		loadTask = Task { await loadNextPage() }
	}

	func hideArticle(_ article: Article) {
		do {
			try articleRepo.hideArticle(id: article.id)
			articles.removeAll { $0.id == article.id }
		} catch {
			errorMessage = error.localizedDescription
		}
	}

	func rate(article: Article, stars: Int) {
		do {
			try articleRepo.updateRating(id: article.id, rating: stars)
			if let idx = articles.firstIndex(where: { $0.id == article.id }) {
				articles[idx].starRating = stars
			}
		} catch {
			errorMessage = error.localizedDescription
		}
	}

	func markRead(_ article: Article) {
		do {
			try articleRepo.markRead(id: article.id)
			if let idx = articles.firstIndex(where: { $0.id == article.id }) {
				articles[idx].isRead = true
			}
			onArticleRead?()
		} catch {
			errorMessage = error.localizedDescription
		}
	}

	func markUnread(_ article: Article) {
		do {
			try articleRepo.markUnread(id: article.id)
			if let idx = articles.firstIndex(where: { $0.id == article.id }) {
				articles[idx].isRead = false
			}
			onArticleRead?()
		} catch {
			errorMessage = error.localizedDescription
		}
	}

	/// Marks all unread articles as read, optionally scoped to a single source.
	/// Updates both the database and the in-memory articles array, then fires
	/// `onArticleRead` so the sidebar badge refreshes immediately.
	func markAllRead(sourceId: Int64?) {
		do {
			try articleRepo.markAllRead(sourceId: sourceId)
			for idx in articles.indices {
				if sourceId == nil || articles[idx].sourceId == sourceId {
					articles[idx].isRead = true
				}
			}
			onArticleRead?()
		} catch {
			errorMessage = error.localizedDescription
		}
	}

	func updateAfterRewrite(id: String, title: String, summary: String) {
		do {
			try articleRepo.updateRewrittenTitle(id: id, title: title, summary: summary)
			if let idx = articles.firstIndex(where: { $0.id == id }) {
				articles[idx].rewrittenTitle = title
				articles[idx].summary = summary
			}
		} catch {
			errorMessage = error.localizedDescription
		}
	}

	func cacheContent(id: String, rawContent: String, readableContent: String) {
		do {
			try articleRepo.updateContent(id: id, rawContent: rawContent, readableContent: readableContent)
			if let idx = articles.firstIndex(where: { $0.id == id }) {
				articles[idx].rawContent = rawContent
				articles[idx].readableContent = readableContent
			}
		} catch {
			errorMessage = error.localizedDescription
		}
	}

	// MARK: - Private

	private func reset() {
		articles = []
		currentOffset = 0
		hasMore = true
		scrollResetToken += 1
	}

	private func buildQuery(offset: Int) -> ArticleQuery {
		ArticleQuery(
			tags: Array(activeTags),
			searchText: searchText,
			sourceId: selectedSourceId,
			hideRead: hideRead,
			hideHidden: true,
			limit: pageSize,
			offset: offset
		)
	}
}
