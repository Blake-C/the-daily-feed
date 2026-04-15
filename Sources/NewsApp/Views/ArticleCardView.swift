import AppKit
import SwiftUI

struct ArticleCardView: View {
	let article: Article
	@ObservedObject var vm: ArticlesViewModel
	var sourceName: String?

	@State private var isHovered = false

	private var displayTitle: String {
		article.rewrittenTitle ?? article.title
	}

	private var relativePublishTime: String {
		let interval = Date().timeIntervalSince(article.publishedAt)
		if interval < 60 { return "1 minute ago" }
		let formatter = RelativeDateTimeFormatter()
		formatter.unitsStyle = .full
		return formatter.localizedString(for: article.publishedAt, relativeTo: Date())
	}

	@Environment(SourceColorStore.self) private var colorStore

	private var sourceColor: Color {
		colorStore.color(for: article.sourceId)
	}

	var body: some View {
		VStack(alignment: .leading, spacing: 0) {
			// Thumbnail — fixed height, overflow hidden
			ThumbnailView(url: article.thumbnailURL)
				.frame(maxWidth: .infinity)
				.frame(height: 160)
				.clipped()
				.overlay {
					if vm.dimThumbnails {
						Color.black.opacity(0.5)
							.allowsHitTesting(false)
							.transition(.opacity)
					}
				}
				.animation(.easeInOut(duration: 0.25), value: vm.dimThumbnails)

			VStack(alignment: .leading, spacing: 8) {
				// Tags
				if !article.tagList.isEmpty {
					ScrollView(.horizontal, showsIndicators: false) {
						HStack(spacing: 4) {
							ForEach(article.tagList.prefix(3), id: \.self) { tag in
								Text(tag.uppercased())
									.font(.system(size: 9, weight: .bold))
									.padding(.horizontal, 6)
									.padding(.vertical, 2)
									.background(sourceColor.opacity(0.15), in: Capsule())
									.foregroundStyle(sourceColor)
							}
						}
					}
				}

				// Title — Spacer below pushes meta to the bottom so all cards
				// in a row share the same height with whitespace under the title.
				Text(displayTitle)
					.font(.system(size: 14, weight: .semibold, design: .serif))
					.lineLimit(3)
					.foregroundStyle(article.isRead ? .secondary : .primary)

				Spacer(minLength: 0)

				// Bottom row: read badge + author (left) + source · time (right)
				HStack(spacing: 4) {
					if article.isRead {
						Image(systemName: "checkmark.circle.fill")
							.foregroundStyle(.green)
							.font(.caption)
					}
					if let author = article.author, !author.trimmingCharacters(in: .whitespaces).isEmpty {
						Text(author)
							.font(.system(size: 11))
							.foregroundStyle(.secondary)
							.lineLimit(1)
					}
					Spacer(minLength: 0)
					if let name = sourceName {
						Text(name)
							.font(.system(size: 11))
							.foregroundStyle(sourceColor.opacity(0.8))
							.lineLimit(1)
						Text("·")
							.font(.system(size: 11))
							.foregroundStyle(.quaternary)
					}
					Text(relativePublishTime)
						.font(.system(size: 11))
						.foregroundStyle(.tertiary)
				}
			}
			.frame(maxHeight: .infinity, alignment: .top)
			.padding(12)
		}
		.background(.background.secondary)
		// clipShape before overlay so the thumbnail is clipped to the rounded corners
		.clipShape(RoundedRectangle(cornerRadius: 10))
		.overlay {
			RoundedRectangle(cornerRadius: 10)
				.strokeBorder(isHovered ? Color.accentColor.opacity(0.6) : Color.clear, lineWidth: 1.5)

			// Top-right action buttons
			VStack {
				HStack(spacing: 4) {
					Spacer()
					if isHovered {
						CardActionButton(
							icon: article.isBookmarked ? "bookmark.fill" : "bookmark",
							tint: article.isBookmarked ? Color.accentColor : .white,
							help: article.isBookmarked ? "Remove bookmark" : "Bookmark"
						) { vm.toggleBookmark(article) }
						.transition(.opacity.combined(with: .scale(scale: 0.8)))

						CardActionButton(
							icon: "xmark",
							tint: .white,
							help: "Hide article"
						) { vm.hideArticle(article) }
						.transition(.opacity.combined(with: .scale(scale: 0.8)))
					} else if article.isBookmarked {
						CardActionButton(
							icon: "bookmark.fill",
							tint: Color.accentColor,
							help: "Bookmarked"
						) { vm.toggleBookmark(article) }
					}
				}
				.padding(8)
				.animation(.easeOut(duration: 0.15), value: isHovered)
				Spacer()
			}
		}
		.shadow(color: .black.opacity(isHovered ? 0.15 : 0.06), radius: isHovered ? 8 : 3, y: 2)
		.scaleEffect(isHovered ? 1.01 : 1.0)
		.animation(.easeOut(duration: 0.15), value: isHovered)
		.onHover { isHovered = $0 }
		.opacity(article.isRead ? 0.75 : 1.0)
		.contextMenu {
			Button {
				vm.toggleBookmark(article)
			} label: {
				Label(
					article.isBookmarked ? "Remove Bookmark" : "Bookmark",
					systemImage: article.isBookmarked ? "bookmark.slash" : "bookmark"
				)
			}
			Divider()
			if let articleURL = URL(string: article.articleURL) {
				ShareLink(item: articleURL) {
					Label("Share…", systemImage: "square.and.arrow.up")
				}
				Button {
					NSPasteboard.general.clearContents()
					NSPasteboard.general.setString(article.articleURL, forType: .string)
				} label: {
					Label("Copy Link", systemImage: "link")
				}
				Divider()
				Button {
					NSWorkspace.shared.open(articleURL)
				} label: {
					Label("Open in Browser", systemImage: "arrow.up.right.square")
				}
			}
			Divider()
			if article.isRead {
				Button {
					vm.markUnread(article)
				} label: {
					Label("Mark as Unread", systemImage: "circle")
				}
			} else {
				Button {
					vm.markRead(article)
				} label: {
					Label("Mark as Read", systemImage: "checkmark.circle")
				}
			}
			Divider()
			Button {
				vm.hideArticle(article)
			} label: {
				Label("Hide Article", systemImage: "xmark.circle")
			}
		}
	}
}

// MARK: - Card action button

/// A small circular icon button with a semi-transparent dark background used for
/// on-card hover actions (bookmark, hide). All instances share identical size and
/// padding so they stay visually aligned regardless of which combination appears.
private struct CardActionButton: View {
	let icon: String
	let tint: Color
	let help: String
	let action: () -> Void

	var body: some View {
		Button(action: action) {
			Image(systemName: icon)
				.font(.system(size: 13, weight: .semibold))
				.foregroundStyle(tint)
				.frame(width: 28, height: 28)
				.background(.black.opacity(0.45), in: Circle())
		}
		.buttonStyle(.plain)
		.help(help)
	}
}

// MARK: - Thumbnail

private struct ThumbnailView: View {
	let url: String?

	var body: some View {
		// Use Color as the layout anchor — overlay content cannot expand it,
		// so large images cannot widen or grow the card's layout footprint.
		Color.secondary.opacity(0.08)
			.overlay {
				if let urlString = url, let imageURL = URL(string: urlString) {
					AsyncImage(url: imageURL) { phase in
						switch phase {
						case .success(let image):
							image
								.resizable()
								.scaledToFill()
						case .failure:
							placeholderOverlay
						default:
							ProgressView()
						}
					}
				} else {
					placeholderOverlay
				}
			}
			.clipped()
			.contentShape(Rectangle())
	}

	private var placeholderOverlay: some View {
		Image(systemName: "newspaper")
			.font(.system(size: 32))
			.foregroundStyle(.tertiary)
	}
}

// MARK: - Star Rating

struct StarRatingView: View {
	let rating: Int
	let onRate: (Int) -> Void

	@State private var isHovered = false

	var body: some View {
		HStack(spacing: isHovered ? 4 : 2) {
			ForEach(1...5, id: \.self) { star in
				Button {
					onRate(star == rating ? 0 : star)
				} label: {
					Image(systemName: star <= rating ? "star.fill" : "star")
						.font(.system(size: isHovered ? 15 : 12))
						.foregroundStyle(star <= rating ? Color.yellow : Color.secondary.opacity(isHovered ? 0.6 : 0.4))
				}
				.buttonStyle(.plain)
			}
		}
		.onHover { isHovered = $0 }
		.animation(.easeOut(duration: 0.12), value: isHovered)
	}
}

// MARK: - Skeleton card

struct ArticleCardSkeletonView: View {
	@State private var phase: CGFloat = -1

	var body: some View {
		VStack(alignment: .leading, spacing: 0) {
			Rectangle()
				.fill(shimmerGradient)
				.frame(height: 160)

			VStack(alignment: .leading, spacing: 8) {
				ForEach(0..<3, id: \.self) { i in
					RoundedRectangle(cornerRadius: 3)
						.fill(shimmerGradient)
						.frame(height: 12)
						.frame(maxWidth: i == 2 ? 160 : .infinity)
				}
			}
			.padding(12)
		}
		.background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
		.onAppear { withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) { phase = 1 } }
	}

	private var shimmerGradient: LinearGradient {
		LinearGradient(
			colors: [Color.secondary.opacity(0.1), Color.secondary.opacity(0.2), Color.secondary.opacity(0.1)],
			startPoint: UnitPoint(x: phase - 0.5, y: 0),
			endPoint: UnitPoint(x: phase + 0.5, y: 0)
		)
	}
}
