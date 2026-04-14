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

		var totalFetched = 0
		var sourceErrors: [Int64: String] = [:]

		await withTaskGroup(of: (Int64?, Result<Int, Error>).self) { group in
			for source in sources {
				group.addTask {
					do {
						let articles = try await self.rssService.fetchArticles(from: source)
						try self.articleRepo.upsert(articles)
						if let id = source.id {
							try self.sourceRepo.updateLastFetched(id: id, date: Date())
						}
						return (source.id, .success(articles.count))
					} catch {
						if let id = source.id {
							try? self.sourceRepo.setError(id: id, message: error.localizedDescription)
						}
						return (source.id, .failure(error))
					}
				}
			}

			for await (sourceId, result) in group {
				switch result {
				case .success(let count):
					totalFetched += count
				case .failure(let error):
					if let id = sourceId {
						sourceErrors[id] = friendlyError(error, sourceId: id, sources: sources)
					}
				}
			}
		}

		return RefreshResult(fetched: totalFetched, sourceErrors: sourceErrors)
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
