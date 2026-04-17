import Foundation

@Observable
@MainActor
final class SourcesViewModel {
	var sources: [NewsSource] = []
	var errorMessage: String?
	var importSummary: String?
	/// Unread article counts keyed by source ID. Refreshed on every load().
	var unreadCounts: [Int64: Int] = [:]
	/// Non-nil while feed autodiscovery is running.
	var discoveryInProgress = false
	/// Set when discovery finds a different URL than the one the user typed.
	/// The UI presents a confirmation before adding.
	var pendingDiscovery: FeedDiscoveryService.DiscoveryResult?

	/// Called after a new source is added and its initial fetch completes.
	var onSourceAdded: (() -> Void)?

	private let sourceRepo = SourceRepository()
	private let articleRepo = ArticleRepository()

	/// The last date range passed to load() or refreshUnreadCounts().
	/// All internal reload calls use this so badges never silently reset to .today.
	private var activeDateRange: DateRangeFilter = .today

	func load(dateRange: DateRangeFilter = .today) {
		activeDateRange = dateRange
		do {
			sources = try sourceRepo.fetchAll()
			unreadCounts = (try? articleRepo.fetchUnreadCountsBySource(dateRange: dateRange)) ?? [:]
		} catch {
			errorMessage = error.localizedDescription
		}
	}

	/// Lightweight re-query of unread counts without reloading sources.
	func refreshUnreadCounts(dateRange: DateRangeFilter = .today) {
		activeDateRange = dateRange
		unreadCounts = (try? articleRepo.fetchUnreadCountsBySource(dateRange: dateRange)) ?? [:]
	}

	/// Clears the new-article badge for one source (or all when sourceId is nil)
	/// without touching any article's read status.
	func dismissBadge(sourceId: Int64?, dateRange: DateRangeFilter = .today) {
		do {
			try sourceRepo.clearBadge(sourceId: sourceId)
			refreshUnreadCounts(dateRange: dateRange)
		} catch {
			errorMessage = error.localizedDescription
		}
	}

	private func reload() {
		load(dateRange: activeDateRange)
	}

	func moveSources(from offsets: IndexSet, to destination: Int) {
		sources.move(fromOffsets: offsets, toOffset: destination)
		let ids = sources.compactMap { $0.id }
		do {
			try sourceRepo.reorder(ids: ids)
		} catch {
			errorMessage = error.localizedDescription
		}
	}

	func addSource(name: String, url: String, type: SourceType) {
		guard let parsed = URL(string: url),
		      let scheme = parsed.scheme?.lowercased(),
		      scheme == "http" || scheme == "https"
		else {
			errorMessage = "Invalid feed URL — only http:// and https:// sources are supported."
			return
		}
		var source = NewsSource(
			id: nil,
			name: name,
			url: url,
			type: type,
			faviconURL: nil,
			isEnabled: true,
			addedAt: Date(),
			lastFetchedAt: nil,
			sortOrder: 0,
			lastError: nil
		)
		do {
			try sourceRepo.insert(&source)
			reload()
			let inserted = source
			Task {
				try? await FeedRefreshService.shared.refresh(source: inserted)
				onSourceAdded?()
			}
		} catch {
			errorMessage = error.localizedDescription
		}
	}

	/// Runs feed autodiscovery on `urlString`, then either adds the source
	/// immediately (if the URL is already a valid feed) or sets
	/// `pendingDiscovery` so the UI can confirm before using the discovered URL.
	func discoverAndAddSource(name: String, urlString: String) {
		discoveryInProgress = true
		Task {
			defer { discoveryInProgress = false }
			guard let result = await FeedDiscoveryService.shared.discover(urlString: urlString) else {
				errorMessage = "Could not find a feed at that URL. Try pasting the RSS/Atom feed URL directly."
				return
			}
			if result.wasDiscovered {
				pendingDiscovery = result
			} else {
				let resolvedName = name.isEmpty ? (result.suggestedName ?? urlString) : name
				addSource(name: resolvedName, url: result.feedURL, type: .rss)
			}
		}
	}

	func confirmPendingDiscovery(name: String) {
		guard let discovery = pendingDiscovery else { return }
		pendingDiscovery = nil
		let resolvedName = name.isEmpty ? (discovery.suggestedName ?? discovery.feedURL) : name
		addSource(name: resolvedName, url: discovery.feedURL, type: .rss)
	}

	func updateSource(id: Int64, name: String, url: String) {
		guard let parsed = URL(string: url),
		      let scheme = parsed.scheme?.lowercased(),
		      scheme == "http" || scheme == "https"
		else {
			errorMessage = "Invalid feed URL — only http:// and https:// sources are supported."
			return
		}
		guard var source = sources.first(where: { $0.id == id }) else { return }
		let trimmedName = name.trimmingCharacters(in: .whitespaces)
		source.name = trimmedName.isEmpty ? source.name : trimmedName
		source.url = url
		do {
			try sourceRepo.update(source)
			reload()
		} catch {
			errorMessage = error.localizedDescription
		}
	}

	func deleteSource(id: Int64) {
		do {
			try sourceRepo.delete(id: id)
			reload()
		} catch {
			errorMessage = error.localizedDescription
		}
	}

	func toggleSource(source: NewsSource) {
		var updated = source
		updated.isEnabled = !source.isEnabled
		do {
			try sourceRepo.update(updated)
			reload()
		} catch {
			errorMessage = error.localizedDescription
		}
	}

	// MARK: - OPML

	func importOPML(from url: URL) {
		do {
			let data = try Data(contentsOf: url)
			let outlines = try OPMLService().parse(data: data)
			let existingURLs = Set(sources.map { $0.url.lowercased() })
			var imported = 0
			for outline in outlines {
				guard !existingURLs.contains(outline.xmlUrl.lowercased()),
				      let parsedFeedURL = URL(string: outline.xmlUrl),
				      let feedScheme = parsedFeedURL.scheme?.lowercased(),
				      feedScheme == "http" || feedScheme == "https"
				else { continue }
				var source = NewsSource(
					id: nil,
					name: outline.title,
					url: outline.xmlUrl,
					type: .rss,
					faviconURL: nil,
					isEnabled: true,
					addedAt: Date(),
					lastFetchedAt: nil,
					sortOrder: 0,
					lastError: nil
				)
				try sourceRepo.insert(&source)
				imported += 1
			}
			reload()
			let skipped = outlines.count - imported
			var message = "\(imported) source\(imported == 1 ? "" : "s") imported"
			if skipped > 0 { message += ", \(skipped) already present" }
			importSummary = message + "."
			if imported > 0 { onSourceAdded?() }
		} catch {
			errorMessage = error.localizedDescription
		}
	}

	func exportOPML() -> Data {
		OPMLService.generate(sources: sources)
	}
}
