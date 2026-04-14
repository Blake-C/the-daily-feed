import SwiftUI

struct SourceManagerView: View {
	@ObservedObject var vm: SourcesViewModel
	@Environment(\.dismiss) private var dismiss

	@State private var newSourceName = ""
	@State private var newSourceURL = ""
	@State private var newSourceType = SourceType.rss
	@State private var newSourceTags = ""
	@State private var showAddSource = false

	@State private var newTagName = ""

	var body: some View {
		VStack(spacing: 0) {
			// Header
			HStack {
				Text("Manage Sources & Tags")
					.font(.headline)
				Spacer()
				Button("Done") { dismiss() }
					.keyboardShortcut(.return)
			}
			.padding()

			Divider()

			TabView {
				sourcesTab
					.tabItem { Label("Sources", systemImage: "dot.radiowaves.left.and.right") }

				tagsTab
					.tabItem { Label("Tags", systemImage: "tag") }
			}
			.padding()
		}
		.onAppear { vm.load() }
	}

	// MARK: - Sources tab

	private var sourcesTab: some View {
		VStack(alignment: .leading, spacing: 12) {
			// Add source form
			GroupBox("Add New Source") {
				VStack(alignment: .leading, spacing: 8) {
					HStack {
						TextField("Source name", text: $newSourceName)
						Picker("Type", selection: $newSourceType) {
							Text("RSS").tag(SourceType.rss)
							Text("Website").tag(SourceType.website)
						}
						.pickerStyle(.segmented)
						.frame(width: 140)
					}
					TextField("URL (RSS feed or website)", text: $newSourceURL)
					TextField("Tags (comma-separated)", text: $newSourceTags)
					Button("Add Source") {
						guard !newSourceName.isEmpty, !newSourceURL.isEmpty else { return }
						let tags = newSourceTags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
						vm.addSource(name: newSourceName, url: newSourceURL, type: newSourceType, sourceTags: tags)
						newSourceName = ""; newSourceURL = ""; newSourceTags = ""
					}
					.buttonStyle(.borderedProminent)
					.disabled(newSourceName.isEmpty || newSourceURL.isEmpty)
				}
				.textFieldStyle(.roundedBorder)
			}

			// Source list
			List {
				ForEach(vm.sources) { source in
					SourceRow(source: source, vm: vm)
				}
			}
			.listStyle(.inset)
		}
	}

	// MARK: - Tags tab

	private var tagsTab: some View {
		VStack(alignment: .leading, spacing: 12) {
			GroupBox("Add Custom Tag") {
				HStack {
					TextField("Tag name", text: $newTagName)
						.textFieldStyle(.roundedBorder)
					Button("Add") {
						guard !newTagName.isEmpty else { return }
						vm.addTag(name: newTagName)
						newTagName = ""
					}
					.buttonStyle(.borderedProminent)
					.disabled(newTagName.isEmpty)
				}
			}

			List {
				ForEach(vm.tags) { tag in
					HStack {
						Toggle(isOn: Binding(
							get: { tag.isActive },
							set: { _ in vm.toggleTag(tag) }
						)) {
							HStack {
								Text(tag.name)
								if tag.isBuiltIn {
									Text("Built-in")
										.font(.caption)
										.foregroundStyle(.secondary)
										.padding(.horizontal, 6)
										.padding(.vertical, 2)
										.background(Color.secondary.opacity(0.1), in: Capsule())
								}
							}
						}
						Spacer()
						if !tag.isBuiltIn {
							Button(role: .destructive) {
								if let id = tag.id { vm.deleteTag(id: id) }
							} label: {
								Image(systemName: "trash")
									.foregroundStyle(.red)
									.font(.caption)
							}
							.buttonStyle(.plain)
						}
					}
				}
			}
			.listStyle(.inset)
		}
	}
}

private struct SourceRow: View {
	let source: NewsSource
	@ObservedObject var vm: SourcesViewModel

	var body: some View {
		HStack {
			VStack(alignment: .leading, spacing: 2) {
				Text(source.name).font(.system(size: 13, weight: .medium))
				Text(source.url)
					.font(.system(size: 11))
					.foregroundStyle(.secondary)
					.lineLimit(1)
			}

			Spacer()

			// Source rating
			StarRatingView(rating: source.rating) { stars in
				if let id = source.id { vm.rateSource(id: id, rating: stars) }
			}

			// Enable toggle
			Button {
				vm.toggleSource(source: source)
			} label: {
				Image(systemName: source.isEnabled ? "pause.circle" : "play.circle")
					.foregroundStyle(source.isEnabled ? Color.secondary : Color.accentColor)
			}
			.buttonStyle(.plain)

			// Delete
			Button(role: .destructive) {
				if let id = source.id { vm.deleteSource(id: id) }
			} label: {
				Image(systemName: "trash")
					.foregroundStyle(.red)
			}
			.buttonStyle(.plain)
		}
		.padding(.vertical, 4)
	}
}
