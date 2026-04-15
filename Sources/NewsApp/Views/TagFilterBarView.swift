import SwiftUI

struct TagFilterBarView: View {
	@ObservedObject var sourcesVM: SourcesViewModel
	@ObservedObject var articlesVM: ArticlesViewModel

	private var hasActiveFilters: Bool { !articlesVM.activeTags.isEmpty }

	var body: some View {
		HStack(spacing: 0) {
			ScrollView(.horizontal, showsIndicators: false) {
				HStack(spacing: 8) {
					ForEach(sourcesVM.tags) { tag in
						TagChip(
							name: tag.name,
							isActive: articlesVM.activeTags.contains(tag.name)
						) {
							articlesVM.toggleTag(tag.name)
						}
					}
				}
				.padding(.horizontal, 16)
				.padding(.vertical, 8)
			}

			if hasActiveFilters {
				Divider().frame(height: 20)

				Button {
					articlesVM.clearAllTagFilters()
				} label: {
					Label("Clear filters", systemImage: "xmark.circle.fill")
						.font(.system(size: 11, weight: .medium))
						.foregroundStyle(.secondary)
						.labelStyle(.titleAndIcon)
				}
				.buttonStyle(.plain)
				.padding(.horizontal, 12)
				.transition(.move(edge: .trailing).combined(with: .opacity))
			}
		}
		.animation(.easeInOut(duration: 0.2), value: hasActiveFilters)
		.background(.bar)
		Divider()
	}
}

private struct TagChip: View {
	let name: String
	let isActive: Bool
	let action: () -> Void

	var body: some View {
		Button(action: action) {
			Text(name)
				.font(.system(size: 12, weight: isActive ? .semibold : .regular))
				.lineLimit(1)
				.truncationMode(.tail)
				.frame(maxWidth: 120)
				.padding(.horizontal, 10)
				.padding(.vertical, 4)
				.background(
					isActive ? Color.accentColor : Color.secondary.opacity(0.12),
					in: Capsule()
				)
				.foregroundStyle(isActive ? .white : .primary)
		}
		.buttonStyle(.plain)
		.help(name)
	}
}
