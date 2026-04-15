import AppKit
import SwiftUI
import UniformTypeIdentifiers

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
		.alert("Import Complete", isPresented: Binding(
			get: { vm.importSummary != nil },
			set: { if !$0 { vm.importSummary = nil } }
		)) {
			Button("OK") { vm.importSummary = nil }
		} message: {
			Text(vm.importSummary ?? "")
		}
		.alert("Error", isPresented: Binding(
			get: { vm.errorMessage != nil },
			set: { if !$0 { vm.errorMessage = nil } }
		)) {
			Button("OK") { vm.errorMessage = nil }
		} message: {
			Text(vm.errorMessage ?? "")
		}
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

			// OPML import / export
			HStack(spacing: 8) {
				Button("Import OPML…") { importOPML() }
					.buttonStyle(.bordered)
				Button("Export OPML…") { exportOPML() }
					.buttonStyle(.bordered)
					.disabled(vm.sources.isEmpty)
				Spacer()
				Text("\(vm.sources.count) source\(vm.sources.count == 1 ? "" : "s")")
					.font(.caption)
					.foregroundStyle(.secondary)
			}
			.padding(.top, 6)
		}
	}

	private func importOPML() {
		let panel = NSOpenPanel()
		panel.title = "Import OPML"
		panel.allowsMultipleSelection = false
		panel.canChooseDirectories = false
		panel.allowedContentTypes = opmlContentTypes
		guard panel.runModal() == .OK, let url = panel.url else { return }
		vm.importOPML(from: url)
	}

	private func exportOPML() {
		let panel = NSSavePanel()
		panel.title = "Export OPML"
		panel.nameFieldStringValue = "TheDailyFeed.opml"
		panel.allowedContentTypes = opmlContentTypes
		guard panel.runModal() == .OK, let url = panel.url else { return }
		try? vm.exportOPML().write(to: url)
	}

	private var opmlContentTypes: [UTType] {
		let opml = UTType(tag: "opml", tagClass: .filenameExtension, conformingTo: .xml) ?? .xml
		return [opml]
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
	@Environment(SourceColorStore.self) private var colorStore

	@State private var pickerColor: Color = .accentColor

	var body: some View {
		HStack(spacing: 8) {
			// Color swatch — lets the user assign a custom accent color to this source.
			if let id = source.id {
				ColorPicker("Source color", selection: $pickerColor, supportsOpacity: false)
					.labelsHidden()
					.frame(width: 22, height: 22)
					.help("Change accent color for \(source.name)")
					.onChange(of: pickerColor) {
						colorStore.set(pickerColor, for: id)
					}
			}

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
		.onAppear {
			if let id = source.id {
				pickerColor = colorStore.color(for: id)
			}
		}
	}
}
