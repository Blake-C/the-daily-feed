import SwiftUI

struct DailySummaryView: View {
	var vm: DailySummaryViewModel
	var sourceNames: [Int64: String] = [:]
	var searchText: String = ""
	var onSelectArticle: (Article) -> Void

	private var filteredArticles: [Article] {
		guard !searchText.isEmpty else { return vm.articles }
		let q = searchText.lowercased()
		return vm.articles.filter { $0.title.lowercased().contains(q) }
	}

	private func columnCount(for width: CGFloat) -> Int {
		switch width {
		case ..<600: return 1
		case ..<960: return 2
		default:     return 3
		}
	}

	var body: some View {
		GeometryReader { geo in
			let cols = columnCount(for: geo.size.width)
			let gridColumns = Array(repeating: GridItem(.flexible(), spacing: 16), count: cols)

			ScrollView {
				LazyVStack(alignment: .leading, spacing: 0) {
					// Header
					VStack(alignment: .leading, spacing: 4) {
						Text("Daily Summary")
							.font(.system(size: 22, weight: .bold, design: .serif))
						Text(Date(), style: .date)
							.font(.system(size: 12))
							.foregroundStyle(.secondary)
					}
					.frame(maxWidth: .infinity, alignment: .leading)
					.padding(.horizontal, 24)
					.padding(.top, 20)
					.padding(.bottom, 16)

					if filteredArticles.isEmpty {
						ContentUnavailableView(
							"No Articles Yet",
							systemImage: "doc.text.magnifyingglass",
							description: Text("Articles you read today will appear here with AI-generated briefings.")
						)
						.padding(.top, 40)
					} else {
						LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 16) {
							ForEach(filteredArticles) { article in
								DailySummaryCard(
									article: article,
									sourceName: sourceNames[article.sourceId]
								) {
									onSelectArticle(article)
								}
								.frame(maxHeight: .infinity, alignment: .top)
							}
						}
						.padding(.horizontal, 24)
						.padding(.bottom, 32)
					}
				}
			}
		}
		.onAppear { vm.load() }
	}
}

// MARK: - Summary card

private struct DailySummaryCard: View {
	let article: Article
	let sourceName: String?
	let onTap: () -> Void

	var body: some View {
		VStack(alignment: .leading, spacing: 10) {
			// Ollama briefing or pending indicator
			if let briefing = article.dailySummary, !briefing.isEmpty {
				Text(briefing)
					.font(.system(size: 14, design: .serif))
					.lineSpacing(3)
					.fixedSize(horizontal: false, vertical: true)
					.textSelection(.enabled)
			} else {
				HStack(spacing: 8) {
					ProgressView()
						.scaleEffect(0.65)
					Text("Generating briefing\u{2026}")
						.font(.system(size: 13))
						.foregroundStyle(.secondary)
				}
			}

			Divider()

			// Mini article link
			Button(action: onTap) {
				HStack(alignment: .top, spacing: 10) {
					VStack(alignment: .leading, spacing: 4) {
						Text(article.rewrittenTitle ?? article.title)
							.font(.system(size: 13, weight: .semibold))
							.lineLimit(2)
							.foregroundStyle(.primary)
							.multilineTextAlignment(.leading)

						HStack(spacing: 5) {
							if let name = sourceName {
								Text(name)
									.font(.system(size: 11))
									.foregroundStyle(Color.accentColor)
									.lineLimit(1)
							}
							if let author = article.author,
							   !author.trimmingCharacters(in: .whitespaces).isEmpty
							{
								Text("\u{00B7}")
									.font(.system(size: 11))
									.foregroundStyle(.quaternary)
								Text(author)
									.font(.system(size: 11))
									.foregroundStyle(.secondary)
									.lineLimit(1)
							}
							Spacer(minLength: 0)
							Text(article.publishedAt, style: .time)
								.font(.system(size: 11))
								.foregroundStyle(.tertiary)
						}
					}

					Image(systemName: "arrow.up.right.square")
						.font(.system(size: 12))
						.foregroundStyle(.secondary)
						.padding(.top, 2)
				}
			}
			.buttonStyle(.plain)
		}
		.padding(14)
		.background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
	}
}
