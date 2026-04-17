import SwiftUI
import UniformTypeIdentifiers

private struct OPMLFile: FileDocument {
	static let readableContentTypes: [UTType] = [
		UTType(tag: "opml", tagClass: .filenameExtension, conformingTo: .xml) ?? .xml
	]
	var data: Data
	init(_ data: Data) { self.data = data }
	init(configuration: ReadConfiguration) throws {
		data = configuration.file.regularFileContents ?? Data()
	}
	func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
		FileWrapper(regularFileWithContents: data)
	}
}

struct SourceManagerView: View {
	var vm: SourcesViewModel
	@Environment(\.dismiss) private var dismiss

	@State private var newSourceName = ""
	@State private var newSourceURL = ""
	@State private var newSourceTags = ""
	@State private var showAddSource = false
	@State private var showImporter = false
	@State private var showExporter = false

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
		.fileImporter(isPresented: $showImporter, allowedContentTypes: [opmlType]) { result in
			if case .success(let url) = result { vm.importOPML(from: url) }
		}
		.fileExporter(
			isPresented: $showExporter,
			document: OPMLFile(vm.exportOPML()),
			contentType: opmlType,
			defaultFilename: "TheDailyFeed"
		) { _ in }
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
					TextField("Source name (optional — auto-detected)", text: $newSourceName)
					TextField("URL (RSS feed or website)", text: $newSourceURL)
					TextField("Tags (comma-separated)", text: $newSourceTags)

					HStack(spacing: 8) {
						Button("Add Source") {
							guard !newSourceURL.isEmpty else { return }
							let tags = newSourceTags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
							vm.discoverAndAddSource(name: newSourceName, urlString: newSourceURL, sourceTags: tags)
							newSourceName = ""; newSourceURL = ""; newSourceTags = ""
						}
						.buttonStyle(.borderedProminent)
						.disabled(newSourceURL.isEmpty || vm.discoveryInProgress)

						if vm.discoveryInProgress {
							ProgressView()
								.scaleEffect(0.7)
							Text("Checking feed…")
								.font(.system(size: 12))
								.foregroundStyle(.secondary)
						}
					}
				}
				.textFieldStyle(.roundedBorder)
			}
			// Autodiscovery confirmation: shown when a website URL was entered and a
			// feed was found at a different address.
			.alert("Feed Found", isPresented: Binding(
				get: { vm.pendingDiscovery != nil },
				set: { if !$0 { vm.pendingDiscovery = nil } }
			)) {
				Button("Use This Feed") {
					let tags = newSourceTags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
					vm.confirmPendingDiscovery(name: newSourceName, sourceTags: tags)
					newSourceName = ""; newSourceTags = ""
				}
				Button("Cancel", role: .cancel) { vm.pendingDiscovery = nil }
			} message: {
				if let d = vm.pendingDiscovery {
					Text("A feed was discovered at:\n\(d.feedURL)\n\nWould you like to subscribe to it?")
				}
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
				Button("Import OPML…") { showImporter = true }
					.buttonStyle(.bordered)
				Button("Export OPML…") { showExporter = true }
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

	private var opmlType: UTType {
		UTType(tag: "opml", tagClass: .filenameExtension, conformingTo: .xml) ?? .xml
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
	var vm: SourcesViewModel
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
					.padding(.trailing, 6)
			}

			VStack(alignment: .leading, spacing: 2) {
				Text(source.name).font(.system(size: 13, weight: .medium))
				Text(source.url)
					.font(.system(size: 11))
					.foregroundStyle(.secondary)
					.lineLimit(1)
			}

			Spacer()

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
