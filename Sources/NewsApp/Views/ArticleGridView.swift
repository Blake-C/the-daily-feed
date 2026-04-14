import SwiftUI

struct ArticleGridView: View {
	@ObservedObject var vm: ArticlesViewModel
	var sourceName: String?   // non-nil when filtered to a single source

	@State private var selectedArticle: Article?

	private let columns = [
		GridItem(.adaptive(minimum: 280, maximum: 400), spacing: 16),
	]

	var body: some View {
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
					LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
						ForEach(Array(vm.articles.enumerated()), id: \.element.id) { index, article in
							ArticleCardView(article: article, vm: vm)
								.frame(maxHeight: .infinity, alignment: .top)
								.onTapGesture { selectedArticle = article }
								.onAppear { vm.prefetchIfNeeded(currentIndex: index) }
						}

						if vm.isLoading {
							ForEach(0..<4, id: \.self) { _ in
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
				ContentUnavailableView(
					vm.hideRead ? "No Unread Articles" : "No Articles",
					systemImage: vm.hideRead ? "checkmark.circle" : "newspaper",
					description: Text(
						vm.hideRead
							? "All articles have been read. Turn off the unread filter to see them."
							: "Add news sources or adjust your tag filters."
					)
				)
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
}
