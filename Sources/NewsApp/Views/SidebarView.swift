import SwiftUI

struct SidebarView: View {
	@ObservedObject var sourcesVM: SourcesViewModel
	@ObservedObject var articlesVM: ArticlesViewModel
	@EnvironmentObject var appState: AppState

	@State private var searchText = ""

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
				Section("Feeds") {
					// All Articles
					SidebarRow(
						title: "All Articles",
						icon: "newspaper",
						selectedIcon: "newspaper.fill",
						isSelected: articlesVM.selectedSourceId == nil,
						badge: nil,
						error: nil
					) {
						articlesVM.filterBySource(nil)
					}

					ForEach(filteredSources) { source in
						SidebarRow(
							title: source.name,
							icon: source.type == .rss ? "dot.radiowaves.left.and.right" : "globe",
							selectedIcon: source.type == .rss ? "dot.radiowaves.up.forward" : "globe.americas.fill",
							isSelected: articlesVM.selectedSourceId == source.id,
							badge: source.isEnabled ? nil : "pause.circle",
							error: source.lastError
						) {
							articlesVM.filterBySource(source.id)
						}
						.contextMenu {
							if let error = source.lastError, let url = URL(string: source.url) {
								Button {
									NSWorkspace.shared.open(url)
								} label: {
									Label("Open in Browser", systemImage: "arrow.up.right.square")
								}
								Text(error)
									.font(.caption)
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
					}
					.onMove { from, to in
						guard searchText.isEmpty else { return } // no reorder while searching
						sourcesVM.moveSources(from: from, to: to)
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
	let badge: String?       // optional SF symbol for a secondary badge
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
