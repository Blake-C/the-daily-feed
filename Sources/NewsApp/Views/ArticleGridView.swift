import SwiftUI

struct ArticleGridView: View {
	@ObservedObject var vm: ArticlesViewModel
	var sourceName: String?
	/// Total number of configured sources — used to produce contextual empty states.
	var sourcesCount: Int

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

						// Source header
						if let sourceName {
							HStack {
								Text(sourceName)
									.font(.system(size: 22, weight: .bold, design: .serif))
								Spacer()
							}
							.padding(.horizontal, 16)
							.padding(.top, 16)
							.padding(.bottom, 8)
						}

						// Article grid
						LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 16) {
							ForEach(Array(vm.articles.enumerated()), id: \.element.id) { index, article in
								ArticleCardView(article: article, vm: vm)
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
		.sheet(item: $selectedArticle) { article in
			ArticleDetailView(article: article, vm: vm)
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
