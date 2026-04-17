import SwiftUI

struct SuggestedSourcesView: View {
	@ObservedObject var vm: SuggestedSourcesViewModel
	@ObservedObject var sourcesVM: SourcesViewModel
	@EnvironmentObject var appState: AppState
	var searchText: String = ""

	private var currentSourceNames: String {
		sourcesVM.sources.map { $0.name }.joined(separator: ", ")
	}

	private var filteredSuggestions: [SuggestedSource] {
		guard !searchText.isEmpty else { return vm.suggestions }
		let q = searchText.lowercased()
		return vm.suggestions.filter {
			$0.name.lowercased().contains(q) ||
			$0.summary.lowercased().contains(q) ||
			$0.category.lowercased().contains(q)
		}
	}

	var body: some View {
		GeometryReader { geo in
		ScrollView {
			LazyVStack(alignment: .leading, spacing: 0) {
				// Header
				HStack(alignment: .firstTextBaseline) {
					VStack(alignment: .leading, spacing: 4) {
						Text("Suggested Sources")
							.font(.system(size: 22, weight: .bold, design: .serif))
						Text("Reputable sources you might not follow yet")
							.font(.system(size: 12))
							.foregroundStyle(.secondary)
					}
					Spacer()
					Button {
						vm.refresh(
							currentSourceNames: currentSourceNames,
							endpoint: appState.ollamaEndpoint,
							model: appState.ollamaModel
						)
					} label: {
						if vm.isRefreshing {
							ProgressView()
								.scaleEffect(0.7)
								.frame(width: 22, height: 22)
						} else {
							Image(systemName: "arrow.clockwise")
								.font(.system(size: 13))
								.foregroundStyle(.secondary)
						}
					}
					.buttonStyle(.plain)
					.disabled(vm.isRefreshing)
					.help("Refresh suggestions")
				}
				.frame(maxWidth: .infinity, alignment: .leading)
				.padding(.horizontal, 24)
				.padding(.top, 20)
				.padding(.bottom, 16)

				if vm.isRefreshing && filteredSuggestions.isEmpty {
					VStack(spacing: 12) {
						ProgressView()
						Text("Finding sources…")
							.font(.system(size: 13))
							.foregroundStyle(.secondary)
					}
					.frame(width: geo.size.width, height: max(geo.size.height - 80, 200))
				} else if filteredSuggestions.isEmpty {
					ContentUnavailableView(
						"No Suggestions Yet",
						systemImage: "antenna.radiowaves.left.and.right",
						description: Text("Tap the refresh button to ask Ollama for source recommendations based on your current feeds.")
					)
					.frame(width: geo.size.width, height: max(geo.size.height - 80, 200))
				} else {
					VStack(spacing: 12) {
						ForEach(filteredSuggestions) { suggestion in
							SuggestedSourceCard(suggestion: suggestion) {
								sourcesVM.addSource(
									name: suggestion.name,
									url: suggestion.feedURL,
									type: .rss,
									sourceTags: []
								)
								vm.markAdded(id: suggestion.id)
							} onDismiss: {
								vm.dismiss(id: suggestion.id)
							}
						}
					}
					.padding(.horizontal, 24)
					.padding(.bottom, 32)
				}
			}
		}
		.onAppear {
			vm.syncAddedState(existingFeedURLs: Set(sourcesVM.sources.map { $0.url }))
			vm.refreshIfNeeded(
				currentSourceNames: currentSourceNames,
				endpoint: appState.ollamaEndpoint,
				model: appState.ollamaModel
			)
		}
		}
	}
}

// MARK: - Source suggestion card

private struct SuggestedSourceCard: View {
	let suggestion: SuggestedSource
	let onAdd: () -> Void
	let onDismiss: () -> Void

	var body: some View {
		VStack(alignment: .leading, spacing: 10) {
			HStack(alignment: .top) {
				VStack(alignment: .leading, spacing: 4) {
					HStack(spacing: 6) {
						Text(suggestion.name)
							.font(.system(size: 14, weight: .semibold))
							.lineLimit(1)

						if !suggestion.category.isEmpty {
							Text(suggestion.category.uppercased())
								.font(.system(size: 9, weight: .bold))
								.foregroundStyle(Color.accentColor)
								.padding(.horizontal, 5)
								.padding(.vertical, 2)
								.background(Color.accentColor.opacity(0.1), in: Capsule())
						}
					}

					if let websiteURL = URL(string: suggestion.websiteURL) {
						Link(suggestion.websiteURL, destination: websiteURL)
							.font(.system(size: 11))
							.foregroundStyle(.secondary)
							.lineLimit(1)
					}
				}

				Spacer(minLength: 8)

				if suggestion.isAlreadyAdded {
					Label("Added", systemImage: "checkmark.circle.fill")
						.font(.system(size: 12, weight: .medium))
						.foregroundStyle(.secondary)
						.labelStyle(.titleAndIcon)
				} else {
					Button(action: onAdd) {
						Label("Add", systemImage: "plus.circle.fill")
							.font(.system(size: 12, weight: .medium))
					}
					.buttonStyle(.borderedProminent)
					.controlSize(.small)
				}
			}

			if !suggestion.summary.isEmpty {
				Text(suggestion.summary)
					.font(.system(size: 13))
					.foregroundStyle(.secondary)
					.fixedSize(horizontal: false, vertical: true)
			}

			HStack {
				Text(suggestion.feedURL)
					.font(.system(size: 11))
					.foregroundStyle(.tertiary)
					.lineLimit(1)
				Spacer()
				Button {
					onDismiss()
				} label: {
					Image(systemName: "xmark")
						.font(.system(size: 10, weight: .medium))
						.foregroundStyle(.tertiary)
				}
				.buttonStyle(.plain)
				.help("Dismiss suggestion")
			}
		}
		.padding(14)
		.background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
	}
}
