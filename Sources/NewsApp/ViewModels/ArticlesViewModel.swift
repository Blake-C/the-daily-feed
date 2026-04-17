import Foundation

@Observable
@MainActor
final class ArticlesViewModel {
	var articles: [Article] = []
	var isLoading = false
	var isRefreshing = false
	var searchText = ""
	var activeTags: Set<String> = []
	var selectedSourceId: Int64? = nil
	var hideRead = false
	var hasMore = true
	var errorMessage: String?
	var dimThumbnails = false
	var dateRangeFilter: DateRangeFilter = .all
	var showBookmarksOnly = false
	var showHiddenOnly = false
	var showDailySummary = false
	var showSuggestedSources = false
	var showQuizStats = false
	/// Tag names that have at least one article in the current source+dateRange context.
	/// The filter bar uses this to hide chips that would return zero results.
	private(set) var availableTagNames: Set<String> = []
	/// Total number of bookmarked articles — drives the sidebar badge.
	private(set) var bookmarkCount: Int = 0
	/// Total number of hidden (dismissed) articles — drives the sidebar badge.
	private(set) var hiddenCount: Int = 0
	/// Increments every time the article list is reset (source/filter change).
	/// Views observe this to scroll back to the top.
	private(set) var scrollResetToken = 0

	/// Called whenever one or more articles are marked read so external observers
	/// (e.g. the sidebar unread badge) can update without polling.
	var onArticleRead: (() -> Void)?
	/// Fired when a read article's Readability content is cached; passes (id, title, content).
	/// ContentView uses this to trigger background daily summarization via DailySummaryService.
	var onReadArticleContentCached: ((String, String, String) -> Void)?

	/// Non-nil while the undo toast is visible after hiding an article.
	private(set) var pendingUndoHide: Article? = nil

	private let articleRepo = ArticleRepository()
	private let refreshService = FeedRefreshService.shared
	private let pageSize = 40
	private var currentOffset = 0
	private var loadTask: Task<Void, Never>?
	private var searchDebounceTask: Task<Void, Never>?
	private var undoHideTask: Task<Void, Never>?

	private static let selectedSourceKey = "articlesVM.selectedSourceId"

	init() {
		// Restore last-selected source so the sidebar selection survives restarts.
		if let stored = UserDefaults.standard.object(forKey: Self.selectedSourceKey) as? Int64 {
			selectedSourceId = stored
		}
	}

	// MARK: - Public

	func initialLoad() async {
		reset()
		await loadNextPage()
	}

	func loadNextPage() async {
		guard !isLoading, hasMore else { return }
		isLoading = true
		defer { isLoading = false }

		// Refresh available tag names and bookmark count on the first page load.
		if currentOffset == 0 {
			availableTagNames = (try? articleRepo.fetchAvailableTagNames(
				sourceId: selectedSourceId,
				dateRange: dateRangeFilter
			)) ?? []
			bookmarkCount = (try? articleRepo.fetchBookmarkCount()) ?? bookmarkCount
			hiddenCount = (try? articleRepo.fetchHiddenCount()) ?? hiddenCount
		}

		let query = buildQuery(offset: currentOffset)
		do {
			let newArticles = try articleRepo.fetch(query: query)
			guard !Task.isCancelled else { return }
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
		guard currentIndex >= threshold, !isLoading, !isRefreshing, hasMore else { return }
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
		// Cancel any in-flight page load so stale results don't overwrite the refresh.
		loadTask?.cancel()
		// Reload in-place so active filters, selection, and scroll position are preserved.
		// Only a hard reset (filter change or initial load) should scroll back to the top.
		await reloadInPlace()
	}

	/// Replaces the current page of articles without clearing the array first,
	/// avoiding the blank-flash and scroll-reset that `reset()` + `loadNextPage()` causes.
	private func reloadInPlace() async {
		availableTagNames = (try? articleRepo.fetchAvailableTagNames(
			sourceId: selectedSourceId,
			dateRange: dateRangeFilter
		)) ?? []
		bookmarkCount = (try? articleRepo.fetchBookmarkCount()) ?? bookmarkCount
		hiddenCount   = (try? articleRepo.fetchHiddenCount()) ?? hiddenCount

		let query = buildQuery(offset: 0)
		do {
			let fetched = try articleRepo.fetch(query: query)
			articles      = fetched
			hasMore       = fetched.count >= pageSize
			currentOffset = fetched.count
		} catch {
			errorMessage = error.localizedDescription
		}
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
		activeTags = []
		showBookmarksOnly = false
		showHiddenOnly = false
		showDailySummary = false
		showSuggestedSources = false
		showQuizStats = false
		// Persist so the selection survives app restarts.
		if let id {
			UserDefaults.standard.set(id, forKey: Self.selectedSourceKey)
		} else {
			UserDefaults.standard.removeObject(forKey: Self.selectedSourceKey)
		}
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
			hiddenCount = (try? articleRepo.fetchHiddenCount()) ?? hiddenCount
			// Show undo toast for 4 seconds.
			pendingUndoHide = article
			undoHideTask?.cancel()
			undoHideTask = Task { @MainActor [weak self] in
				try? await Task.sleep(for: .seconds(10))
				guard !Task.isCancelled else { return }
				self?.pendingUndoHide = nil
			}
		} catch {
			errorMessage = error.localizedDescription
		}
	}

	func undoHide() {
		guard let article = pendingUndoHide else { return }
		undoHideTask?.cancel()
		pendingUndoHide = nil
		do {
			try articleRepo.unhideArticle(id: article.id)
			hiddenCount = (try? articleRepo.fetchHiddenCount()) ?? hiddenCount
			// Re-insert at the correct position in the sorted list.
			if !showHiddenOnly {
				var restored = article
				restored.isHidden = false
				let idx = articles.firstIndex(where: { $0.publishedAt < article.publishedAt }) ?? articles.endIndex
				articles.insert(restored, at: idx)
			}
		} catch {
			errorMessage = error.localizedDescription
		}
	}

	func unhideArticle(_ article: Article) {
		do {
			try articleRepo.unhideArticle(id: article.id)
			if showHiddenOnly {
				articles.removeAll { $0.id == article.id }
			}
			hiddenCount = (try? articleRepo.fetchHiddenCount()) ?? hiddenCount
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

	func cacheContent(id: String, readableContent: String) {
		do {
			try articleRepo.updateContent(id: id, readableContent: readableContent)
			if let idx = articles.firstIndex(where: { $0.id == id }) {
				articles[idx].readableContent = readableContent
				// Fire the daily-summary hook only for articles already marked read so
				// we have the best content available at the time of summarization.
				if articles[idx].isRead {
					onReadArticleContentCached?(id, articles[idx].title, readableContent)
				}
			}
		} catch {
			errorMessage = error.localizedDescription
		}
	}

	// MARK: - Private

	/// A human-readable sentence describing the currently active filters, or nil when
	/// no filters are applied. Used by the article grid to show a contextual banner.
	var activeFilterDescription: String? {
		var parts: [String] = []

		if showDailySummary { return nil }        // DailySummaryView has its own header
		if showSuggestedSources { return nil }    // SuggestedSourcesView has its own header
		if showQuizStats { return nil }           // QuizStatsView has its own header
		if showHiddenOnly {
			parts.append("Hidden")
		} else {
			if showBookmarksOnly { parts.append("Bookmarked") }
			if hideRead { parts.append("Unread") }
		}

		if let tag = activeTags.first {
			parts.append(tag.capitalized)
		}

		let noun = parts.isEmpty ? "Articles" : "articles"
		var sentence = (parts + [noun]).joined(separator: " ")
		sentence = sentence.prefix(1).uppercased() + sentence.dropFirst()

		var suffixes: [String] = []
		if dateRangeFilter != .all {
			switch dateRangeFilter {
			case .oneHour:     suffixes.append("from the past hour")
			case .fourHours:   suffixes.append("from the past 4 hours")
			case .sixHours:    suffixes.append("from the past 6 hours")
			case .twelveHours: suffixes.append("from the past 12 hours")
			case .today:       suffixes.append("from today")
			case .twoDays:     suffixes.append("from the past 2 days")
			case .week:        suffixes.append("from the past week")
			case .month:       suffixes.append("from the past month")
			case .all:         break
			}
		}
		if !searchText.isEmpty {
			suffixes.append("matching \"\(searchText)\"")
		}

		if !suffixes.isEmpty {
			sentence += " " + suffixes.joined(separator: ", ")
		}

		// Only return a description when at least one filter is active.
		let hasFilter = showHiddenOnly || showBookmarksOnly || hideRead
			|| !activeTags.isEmpty || dateRangeFilter != .all || !searchText.isEmpty
		return hasFilter ? sentence : nil
	}

	private func reset() {
		loadTask?.cancel()
		articles = []
		currentOffset = 0
		hasMore = true
		scrollResetToken += 1
	}

	func setDateRange(_ range: DateRangeFilter) {
		dateRangeFilter = range
		reset()
		loadTask = Task { await loadNextPage() }
	}

	func filterByBookmarks(_ on: Bool) {
		showBookmarksOnly = on
		if on { selectedSourceId = nil; showHiddenOnly = false; showDailySummary = false; showSuggestedSources = false; showQuizStats = false }
		reset()
		loadTask = Task { await loadNextPage() }
	}

	func filterByHidden(_ on: Bool) {
		showHiddenOnly = on
		if on { selectedSourceId = nil; showBookmarksOnly = false; showDailySummary = false; showSuggestedSources = false; showQuizStats = false }
		reset()
		loadTask = Task { await loadNextPage() }
	}

	func filterByDailySummary(_ on: Bool) {
		showDailySummary = on
		if on { selectedSourceId = nil; showBookmarksOnly = false; showHiddenOnly = false; showSuggestedSources = false; showQuizStats = false }
		reset()
		loadTask = Task { await loadNextPage() }
	}

	func filterBySuggestedSources(_ on: Bool) {
		showSuggestedSources = on
		if on { selectedSourceId = nil; showBookmarksOnly = false; showHiddenOnly = false; showDailySummary = false; showQuizStats = false }
		reset()
		loadTask = Task { await loadNextPage() }
	}

	func filterByQuizStats(_ on: Bool) {
		showQuizStats = on
		if on { selectedSourceId = nil; showBookmarksOnly = false; showHiddenOnly = false; showDailySummary = false; showSuggestedSources = false }
		reset()
		loadTask = Task { await loadNextPage() }
	}

	func toggleBookmark(_ article: Article) {
		do {
			let nowBookmarked = try articleRepo.toggleBookmark(id: article.id)
			if let idx = articles.firstIndex(where: { $0.id == article.id }) {
				articles[idx].isBookmarked = nowBookmarked
			}
			// If we are in bookmarks-only mode and the article was un-bookmarked, remove it.
			if showBookmarksOnly && !nowBookmarked {
				articles.removeAll { $0.id == article.id }
			}
			bookmarkCount = (try? articleRepo.fetchBookmarkCount()) ?? bookmarkCount
		} catch {
			errorMessage = error.localizedDescription
		}
	}

	private func buildQuery(offset: Int) -> ArticleQuery {
		ArticleQuery(
			tags: Array(activeTags),
			searchText: searchText,
			sourceId: selectedSourceId,
			hideRead: hideRead,
			hideHidden: !showHiddenOnly,
			hiddenOnly: showHiddenOnly,
			bookmarksOnly: showBookmarksOnly,
			dateRange: dateRangeFilter,
			limit: pageSize,
			offset: offset
		)
	}
}
