import SwiftUI
import UniformTypeIdentifiers

// MARK: - Library item order

private enum LibraryItem: String, CaseIterable, Identifiable, Equatable {
	case bookmarks        = "bookmarks"
	case hidden           = "hidden"
	case dailySummary     = "daily_summary"
	case quizStats        = "quiz_stats"
	case suggestedSources = "suggested_sources"

	var id: String { rawValue }
}

// MARK: - Sidebar

struct SidebarView: View {
	@ObservedObject var sourcesVM: SourcesViewModel
	@ObservedObject var articlesVM: ArticlesViewModel
	@EnvironmentObject var appState: AppState

	@State private var searchText = ""
	@State private var draggingSource: NewsSource?
	@State private var draggingLibraryItem: LibraryItem?

	/// Comma-separated raw values persisted across launches.
	@AppStorage("libraryItemOrder") private var libraryOrderString = ""

	private var libraryOrder: [LibraryItem] {
		guard !libraryOrderString.isEmpty else { return LibraryItem.allCases }
		var result = libraryOrderString
			.components(separatedBy: ",")
			.compactMap { LibraryItem(rawValue: $0) }
		for item in LibraryItem.allCases where !result.contains(item) {
			result.append(item)
		}
		return result
	}

	private func saveLibraryOrder(_ order: [LibraryItem]) {
		libraryOrderString = order.map(\.rawValue).joined(separator: ",")
	}

	private var visibleLibraryItems: [LibraryItem] {
		libraryOrder.filter { item in
			switch item {
			case .bookmarks, .hidden:    return true
			case .dailySummary:          return appState.dailySummaryEnabled
			case .quizStats:             return appState.quizEnabled
			case .suggestedSources:      return appState.suggestedSourcesEnabled
			}
		}
	}

	@ViewBuilder
	private func libraryRow(for item: LibraryItem) -> some View {
		switch item {
		case .bookmarks:
			SidebarRow(
				title: "Bookmarks",
				icon: "bookmark",
				selectedIcon: "bookmark.fill",
				isSelected: articlesVM.showBookmarksOnly,
				unreadCount: articlesVM.bookmarkCount,
				badge: nil, error: nil
			) { articlesVM.filterByBookmarks(!articlesVM.showBookmarksOnly) }
		case .hidden:
			SidebarRow(
				title: "Hidden",
				icon: "eye.slash",
				selectedIcon: "eye.slash.fill",
				isSelected: articlesVM.showHiddenOnly,
				unreadCount: articlesVM.hiddenCount,
				badge: nil, error: nil
			) { articlesVM.filterByHidden(!articlesVM.showHiddenOnly) }
		case .dailySummary:
			SidebarRow(
				title: "Daily Summary",
				icon: "doc.text.magnifyingglass",
				selectedIcon: "doc.text.magnifyingglass",
				isSelected: articlesVM.showDailySummary,
				unreadCount: 0, badge: nil, error: nil
			) { articlesVM.filterByDailySummary(!articlesVM.showDailySummary) }
		case .quizStats:
			SidebarRow(
				title: "Quiz Stats",
				icon: "brain.head.profile",
				selectedIcon: "brain.head.profile",
				isSelected: articlesVM.showQuizStats,
				unreadCount: 0, badge: nil, error: nil
			) { articlesVM.filterByQuizStats(!articlesVM.showQuizStats) }
		case .suggestedSources:
			SidebarRow(
				title: "Suggested Sources",
				icon: "antenna.radiowaves.left.and.right",
				selectedIcon: "antenna.radiowaves.left.and.right",
				isSelected: articlesVM.showSuggestedSources,
				unreadCount: 0, badge: nil, error: nil
			) { articlesVM.filterBySuggestedSources(!articlesVM.showSuggestedSources) }
		}
	}

	private var filteredSources: [NewsSource] {
		if searchText.isEmpty { return sourcesVM.sources }
		return sourcesVM.sources.filter {
			$0.name.localizedCaseInsensitiveContains(searchText)
		}
	}

	var body: some View {
		VStack(spacing: 0) {
			// Search field
			HStack(spacing: 6) {
				Image(systemName: "magnifyingglass")
					.foregroundStyle(.secondary)
					.font(.system(size: 12))
				TextField("Search sources…", text: $searchText)
					.textFieldStyle(.plain)
					.font(.system(size: 12))
				if !searchText.isEmpty {
					Button { searchText = "" } label: {
						Image(systemName: "xmark.circle.fill")
							.foregroundStyle(.secondary)
							.font(.system(size: 11))
					}
					.buttonStyle(.plain)
				}
			}
			.padding(.horizontal, 10)
			.padding(.vertical, 6)
			.background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
			.padding(.horizontal, 10)
			.padding(.top, 8)
			.padding(.bottom, 4)

			List {
				Section("Library") {
					ForEach(visibleLibraryItems) { item in
						libraryRow(for: item)
							.onDrag {
								draggingLibraryItem = item
								return NSItemProvider(object: item.rawValue as NSString)
							}
							.onDrop(of: [UTType.plainText], isTargeted: nil) { _ in
								guard let dragged = draggingLibraryItem, dragged != item else { return false }
								var order = libraryOrder
								guard
									let fromIdx = order.firstIndex(of: dragged),
									let toIdx   = order.firstIndex(of: item)
								else { return false }
								let dest = toIdx >= fromIdx ? toIdx + 1 : toIdx
								order.move(fromOffsets: IndexSet([fromIdx]), toOffset: dest)
								saveLibraryOrder(order)
								draggingLibraryItem = nil
								return true
							}
					}
				}

				Section("Feeds") {
					// All Articles
					let totalUnread = sourcesVM.unreadCounts.values.reduce(0, +)
					SidebarRow(
						title: "All Articles",
						icon: "newspaper",
						selectedIcon: "newspaper.fill",
						isSelected: articlesVM.selectedSourceId == nil,
						unreadCount: totalUnread,
						badge: nil,
						error: nil
					) {
						articlesVM.filterBySource(nil)
					}
					.contextMenu {
						if totalUnread > 0 {
							Button {
								sourcesVM.dismissBadge(sourceId: nil, dateRange: articlesVM.dateRangeFilter)
							} label: {
								Label("Dismiss New", systemImage: "bell.slash")
							}
						}
					}

					ForEach(filteredSources) { source in
						let unread = sourcesVM.unreadCounts[source.id ?? -1] ?? 0
						SidebarRow(
							title: source.name,
							icon: source.type == .rss ? "dot.radiowaves.left.and.right" : "globe",
							selectedIcon: source.type == .rss ? "dot.radiowaves.up.forward" : "globe.americas.fill",
							isSelected: articlesVM.selectedSourceId == source.id,
							unreadCount: source.isEnabled ? unread : 0,
							badge: source.isEnabled ? nil : "pause.circle",
							error: source.lastError
						) {
							articlesVM.filterBySource(source.id)
						}
						.contextMenu {
							if let error = source.lastError {
							if let url = URL(string: source.url),
							   ["http", "https"].contains(url.scheme?.lowercased() ?? "")
							{
								Button {
									NSWorkspace.shared.open(url)
								} label: {
									Label("Open in Browser", systemImage: "arrow.up.right.square")
								}
							}
							Text(error)
								.font(.caption)
							Divider()
						}
							if unread > 0 {
								Button {
									sourcesVM.dismissBadge(sourceId: source.id, dateRange: articlesVM.dateRangeFilter)
								} label: {
									Label("Dismiss New", systemImage: "bell.slash")
								}
								Divider()
							}
							Button(source.isEnabled ? "Disable Source" : "Enable Source") {
								sourcesVM.toggleSource(source: source)
							}
							Divider()
							Button("Delete", role: .destructive) {
								if let id = source.id { sourcesVM.deleteSource(id: id) }
							}
						}
						// Drag-to-reorder: onDrag/onDrop because .onMove requires editMode
						// which doesn't exist on macOS, and the Button rows block the list's
						// built-in drag handles.
						.onDrag {
							guard searchText.isEmpty else { return NSItemProvider() }
							draggingSource = source
							return NSItemProvider(object: "\(source.id ?? -1)" as NSString)
						}
						.onDrop(of: [UTType.plainText], isTargeted: nil) { _ in
							guard searchText.isEmpty,
								  let dragged = draggingSource,
								  dragged.id != source.id
							else { return false }
							let all = sourcesVM.sources
							guard
								let fromIdx = all.firstIndex(where: { $0.id == dragged.id }),
								let toIdx   = all.firstIndex(where: { $0.id == source.id })
							else { return false }
							// When dropping below the drag origin, shift destination by 1
							// so the row lands after the target, matching expected behaviour.
							let dest = toIdx >= fromIdx ? toIdx + 1 : toIdx
							sourcesVM.moveSources(from: IndexSet([fromIdx]), to: dest)
							draggingSource = nil
							return true
						}
					}
				}

				Section {
					Button {
						appState.showSourceManager = true
					} label: {
						Label("Manage Sources", systemImage: "plus.circle")
							.foregroundStyle(Color.accentColor)
					}
					.buttonStyle(.plain)
				}
			}
			.listStyle(.sidebar)
		}
	}
}

// MARK: - Sidebar row

private struct SidebarRow: View {
	let title: String
	let icon: String
	let selectedIcon: String
	let isSelected: Bool
	let unreadCount: Int     // 0 = hide badge
	let badge: String?       // optional SF symbol for a secondary indicator
	let error: String?       // non-nil = show warning indicator
	let action: () -> Void

	var body: some View {
		Button(action: action) {
			HStack(spacing: 8) {
				Image(systemName: isSelected ? selectedIcon : icon)
					.font(.system(size: 13, weight: isSelected ? .semibold : .regular))
					.foregroundStyle(isSelected ? Color.accentColor : .secondary)
					.frame(width: 16)

				Text(title)
					.font(.system(size: 13, weight: isSelected ? .semibold : .regular))
					.foregroundStyle(isSelected ? Color.accentColor : .primary)
					.lineLimit(1)

				Spacer(minLength: 4)

				if let error, !error.isEmpty {
					Image(systemName: "exclamationmark.triangle.fill")
						.font(.system(size: 11))
						.foregroundStyle(.orange)
						.help(error)
				}

				if let badge {
					Image(systemName: badge)
						.font(.system(size: 11))
						.foregroundStyle(.secondary)
				}

				if unreadCount > 0 {
					Text(unreadCount > 999 ? "999+" : "\(unreadCount)")
						.font(.system(size: 11, weight: .semibold))
						.foregroundStyle(isSelected ? Color.accentColor : .secondary)
						.padding(.horizontal, 6)
						.padding(.vertical, 2)
						.background(
							(isSelected ? Color.accentColor : Color.secondary).opacity(0.15),
							in: Capsule()
						)
				}
			}
			.padding(.vertical, 3)
			.padding(.horizontal, 6)
			.background(
				isSelected
					? Color.accentColor.opacity(0.12)
					: Color.clear,
				in: RoundedRectangle(cornerRadius: 6)
			)
		}
		.buttonStyle(.plain)
	}
}
