import Foundation

@MainActor
final class SourcesViewModel: ObservableObject {
	@Published var sources: [NewsSource] = []
	@Published var tags: [Tag] = []
	@Published var errorMessage: String?
	@Published var importSummary: String?

	/// Called after a new source is added and its initial fetch completes.
	var onSourceAdded: (() -> Void)?

	private let sourceRepo = SourceRepository()
	private let tagRepo = TagRepository()

	func load() {
		do {
			sources = try sourceRepo.fetchAll()
			tags = try tagRepo.fetchAll()
		} catch {
			errorMessage = error.localizedDescription
		}
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

	func addSource(name: String, url: String, type: SourceType, sourceTags: [String]) {
		var source = NewsSource(
			id: nil,
			name: name,
			url: url,
			type: type,
			faviconURL: nil,
			rating: 0,
			isEnabled: true,
			tags: sourceTags.joined(separator: ","),
			addedAt: Date(),
			lastFetchedAt: nil,
			sortOrder: 0,
			lastError: nil
		)
		do {
			try sourceRepo.insert(&source)
			load()
			// Fetch articles immediately so they appear without a manual refresh.
			let inserted = source
			Task {
				try? await FeedRefreshService.shared.refresh(source: inserted)
				onSourceAdded?()
			}
		} catch {
			errorMessage = error.localizedDescription
		}
	}

	func deleteSource(id: Int64) {
		do {
			try sourceRepo.delete(id: id)
			load()
		} catch {
			errorMessage = error.localizedDescription
		}
	}

	func rateSource(id: Int64, rating: Int) {
		do {
			try sourceRepo.updateRating(id: id, rating: rating)
			load()
		} catch {
			errorMessage = error.localizedDescription
		}
	}

	func toggleSource(source: NewsSource) {
		var updated = source
		updated.isEnabled = !source.isEnabled
		do {
			try sourceRepo.update(updated)
			load()
		} catch {
			errorMessage = error.localizedDescription
		}
	}

	func addTag(name: String) {
		var tag = Tag(id: nil, name: name, isBuiltIn: false, isActive: true)
		do {
			try tagRepo.insert(&tag)
			load()
		} catch {
			errorMessage = error.localizedDescription
		}
	}

	func toggleTag(_ tag: Tag) {
		guard let id = tag.id else { return }
		do {
			try tagRepo.toggle(id: id, isActive: !tag.isActive)
			load()
		} catch {
			errorMessage = error.localizedDescription
		}
	}

	func deleteTag(id: Int64) {
		do {
			try tagRepo.delete(id: id)
			load()
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
				guard !existingURLs.contains(outline.xmlUrl.lowercased()) else { continue }
				var source = NewsSource(
					id: nil,
					name: outline.title,
					url: outline.xmlUrl,
					type: .rss,
					faviconURL: nil,
					rating: 0,
					isEnabled: true,
					tags: "",
					addedAt: Date(),
					lastFetchedAt: nil,
					sortOrder: 0,
					lastError: nil
				)
				try sourceRepo.insert(&source)
				imported += 1
			}
			load()
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
