import SwiftUI

struct ArticleGridView: View {
	var vm: ArticlesViewModel
	var sourceName: String?
	/// Total number of configured sources — used to produce contextual empty states.
	var sourcesCount: Int
	/// Source name keyed by source ID — passed down to each card and the detail view.
	var sourceNames: [Int64: String] = [:]

	@State private var selectedArticle: Article?

	var body: some View {
		GeometryReader { geo in
			let cols = columnCount(for: geo.size.width)
			let gridColumns = Array(repeating: GridItem(.flexible(), spacing: 16), count: cols)
			let skeletonCount = cols * 2

			ScrollViewReader { proxy in
				ScrollView {
					LazyVStack(alignment: .leading, spacing: 0, pinnedViews: []) {
						// Invisible anchor at the very top
						Color.clear.frame(height: 0).id("articleListTop")

						// Active filter description
						if let description = vm.activeFilterDescription {
							HStack {
								Image(systemName: "line.3.horizontal.decrease.circle")
									.font(.system(size: 12))
									.foregroundStyle(.secondary)
								Text(description)
									.font(.system(size: 13, weight: .medium))
									.foregroundStyle(.secondary)
								Spacer()
							}
							.padding(.horizontal, 16)
							.padding(.top, 14)
							.padding(.bottom, sourceName == nil ? 4 : 2)
							.transition(.opacity)
							.animation(.easeInOut(duration: 0.2), value: description)
						}

						// Source header
						if let sourceName {
							HStack {
								Text(sourceName)
									.font(.system(size: 22, weight: .bold, design: .serif))
								Spacer()
							}
							.padding(.horizontal, 16)
							.padding(.top, vm.activeFilterDescription == nil ? 16 : 4)
							.padding(.bottom, 8)
						}

						// Article grid
						LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 16) {
							ForEach(Array(vm.articles.enumerated()), id: \.element.id) { index, article in
								ArticleCardView(article: article, vm: vm, sourceName: sourceNames[article.sourceId])
									.frame(maxHeight: .infinity, alignment: .top)
									.onTapGesture { selectedArticle = article }
									.onAppear { vm.prefetchIfNeeded(currentIndex: index) }
							}

							if vm.isLoading {
								ForEach(0..<skeletonCount, id: \.self) { _ in
									ArticleCardSkeletonView()
								}
							}
						}
						.padding(.horizontal, 16)
						.padding(.bottom, 16)
						.padding(.top, sourceName == nil ? 16 : 0)
					}
				}
				.onChange(of: vm.scrollResetToken) {
					proxy.scrollTo("articleListTop", anchor: .top)
				}
			}
			.overlay {
				if vm.articles.isEmpty && !vm.isLoading {
					emptyState
				}
			}
		}
		.overlay(alignment: .bottom) {
			if vm.pendingUndoHide != nil {
				HideUndoToast { vm.undoHide() }
					.padding(.bottom, 20)
					.transition(.move(edge: .bottom).combined(with: .opacity))
			}
		}
		.animation(.spring(response: 0.3, dampingFraction: 0.8), value: vm.pendingUndoHide != nil)
		.sheet(item: $selectedArticle) { article in
			ArticleDetailView(article: article, vm: vm, sourceName: sourceNames[article.sourceId])
				.frame(minWidth: 860, minHeight: 700)
		}
		.refreshable {
			await vm.refresh()
		}
	}

	// MARK: - Contextual empty state

	@ViewBuilder
	private var emptyState: some View {
		if !vm.searchText.isEmpty {
			ContentUnavailableView.search(text: vm.searchText)
		} else if !vm.activeTags.isEmpty {
			ContentUnavailableView(
				"No Articles for Selected Tags",
				systemImage: "tag.slash",
				description: Text("Try removing some tag filters or refreshing your feeds.")
			)
		} else if vm.hideRead {
			ContentUnavailableView(
				"No Unread Articles",
				systemImage: "checkmark.circle",
				description: Text("All articles have been read. Turn off the unread filter to see them.")
			)
		} else if sourcesCount == 0 {
			ContentUnavailableView(
				"No Sources Added",
				systemImage: "dot.radiowaves.left.and.right.slash",
				description: Text("Open Manage Sources to add RSS feeds.")
			)
		} else {
			ContentUnavailableView(
				"No Articles",
				systemImage: "newspaper",
				description: Text("Pull to refresh or wait for the next auto-refresh.")
			)
		}
	}

	// MARK: - Layout helpers

	/// Returns the number of equal-width columns for the given available width.
	/// Targets roughly 340 pt per column with a minimum of 2.
	private func columnCount(for width: CGFloat) -> Int {
		max(2, Int(width / 340))
	}
}

// MARK: - Undo Toast

private struct HideUndoToast: View {
	let onUndo: () -> Void

	var body: some View {
		HStack(spacing: 14) {
			Image(systemName: "eye.slash.fill")
				.font(.system(size: 13))
				.foregroundStyle(.secondary)
			Text("Article hidden")
				.font(.system(size: 13, weight: .semibold))
			Divider()
				.frame(height: 16)
			Button("Undo") { onUndo() }
				.buttonStyle(.plain)
				.font(.system(size: 13, weight: .semibold))
				.foregroundColor(.accentColor)
		}
		.padding(.horizontal, 20)
		.padding(.vertical, 12)
		.background(Color(nsColor: .windowBackgroundColor).opacity(0.98))
		.clipShape(Capsule())
		.overlay(Capsule().strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
		.shadow(color: .black.opacity(0.25), radius: 16, y: 6)
	}
}
