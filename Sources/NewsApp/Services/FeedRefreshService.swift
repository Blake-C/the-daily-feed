import Foundation

/// Coordinates refreshing all enabled sources and persisting new articles.
final class FeedRefreshService: @unchecked Sendable {
	static let shared = FeedRefreshService()

	private let sourceRepo = SourceRepository()
	private let articleRepo = ArticleRepository()
	private let rssService = RSSService.shared

	private init() {}

	@discardableResult
	func refreshAll() async -> RefreshResult {
		let sources: [NewsSource]
		do {
			sources = try sourceRepo.fetchEnabled()
		} catch {
			return RefreshResult(fetched: 0, sourceErrors: [:])
		}

		// Prune old read articles before fetching new ones so we don't immediately
		// re-insert something we just cleaned up. Reads retention setting directly
		// from UserDefaults (set via AppState's @AppStorage binding).
		pruneIfNeeded()

		var totalFetched = 0
		var sourceErrors: [Int64: String] = [:]

		// Cap concurrent network requests to avoid overwhelming sources or the
		// local network stack when many feeds are enabled (30+).
		let maxConcurrency = 6
		var pending = sources.makeIterator()

		await withTaskGroup(of: (Int64?, Result<Int, Error>).self) { group in
			// Seed the initial batch.
			for _ in 0..<min(maxConcurrency, sources.count) {
				if let source = pending.next() {
					let s = source
					group.addTask { await self.fetchOne(source: s) }
				}
			}

			// As each slot frees up, feed in the next source.
			while let (sourceId, result) = await group.next() {
				switch result {
				case .success(let count):
					totalFetched += count
				case .failure(let error):
					if let id = sourceId {
						sourceErrors[id] = friendlyError(error, sourceId: id, sources: sources)
					}
				}
				if let source = pending.next() {
					let s = source
					group.addTask { await self.fetchOne(source: s) }
				}
			}
		}

		return RefreshResult(fetched: totalFetched, sourceErrors: sourceErrors)
	}

	private func fetchOne(source: NewsSource) async -> (Int64?, Result<Int, Error>) {
		do {
			let articles = try await rssService.fetchArticles(from: source)
			try articleRepo.upsert(articles)
			if let id = source.id {
				try sourceRepo.updateLastFetched(id: id, date: Date())
			}
			return (source.id, .success(articles.count))
		} catch {
			if let id = source.id {
				try? sourceRepo.setError(id: id, message: error.localizedDescription)
			}
			return (source.id, .failure(error))
		}
	}

	func refresh(source: NewsSource) async throws -> Int {
		do {
			let articles = try await rssService.fetchArticles(from: source)
			try articleRepo.upsert(articles)
			if let id = source.id {
				try sourceRepo.updateLastFetched(id: id, date: Date())
			}
			return articles.count
		} catch {
			if let id = source.id {
				try? sourceRepo.setError(id: id, message: error.localizedDescription)
			}
			throw error
		}
	}

	// MARK: - Private

	private func pruneIfNeeded() {
		let retentionDays = UserDefaults.standard.integer(forKey: "articleRetentionDays")
		// 0 means "keep forever" — skip pruning entirely.
		guard retentionDays > 0 else { return }
		guard let cutoff = Calendar.current.date(byAdding: .day, value: -retentionDays, to: Date()) else { return }
		try? articleRepo.pruneArticles(olderThan: cutoff)
	}

	private func friendlyError(_ error: Error, sourceId: Int64, sources: [NewsSource]) -> String {
		let source = sources.first { $0.id == sourceId }
		if source?.type == .website {
			return "This URL is a website, not an RSS/Atom feed. Add the feed URL directly or use the RSS auto-discovery to find a feed for this site."
		}
		return error.localizedDescription
	}
}

struct RefreshResult {
	let fetched: Int
	let sourceErrors: [Int64: String]
}
