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

					HStack(spacing: 8) {
						Button("Add Source") {
							guard !newSourceURL.isEmpty else { return }
							vm.discoverAndAddSource(name: newSourceName, urlString: newSourceURL)
							newSourceName = ""; newSourceURL = ""
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
					vm.confirmPendingDiscovery(name: newSourceName)
					newSourceName = ""
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
				.onMove { vm.moveSources(from: $0, to: $1) }
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
	@State private var showEdit = false
	@State private var editName = ""
	@State private var editURL = ""

	var body: some View {
		HStack(spacing: 8) {
			// Color swatch
			if let id = source.id {
				ColorPicker("Source color", selection: $pickerColor, supportsOpacity: false)
					.labelsHidden()
					.frame(width: 22, height: 22)
					.help("Change accent color for \(source.name)")
					.onChange(of: pickerColor) {
						colorStore.set(pickerColor, for: id)
					}
					.padding(.trailing, 2)
			}

			VStack(alignment: .leading, spacing: 2) {
				HStack(spacing: 4) {
					Text(source.name).font(.system(size: 13, weight: .medium))
					if source.lastError != nil {
						Image(systemName: "exclamationmark.triangle.fill")
							.font(.system(size: 10))
							.foregroundStyle(.orange)
							.help("Last fetch failed: \(source.lastError ?? "")")
					}
				}
				Text(source.url)
					.font(.system(size: 11))
					.foregroundStyle(.secondary)
					.lineLimit(1)
			}

			Spacer()

			// Edit
			Button {
				editName = source.name
				editURL = source.url
				showEdit = true
			} label: {
				Image(systemName: "pencil")
					.font(.system(size: 12))
					.foregroundStyle(.secondary)
			}
			.buttonStyle(.plain)
			.help("Edit source")
			.popover(isPresented: $showEdit, arrowEdge: .trailing) {
				EditSourcePopover(
					name: $editName,
					url: $editURL,
					onSave: {
						guard let id = source.id else { return }
						vm.updateSource(id: id, name: editName, url: editURL)
						showEdit = false
					},
					onCancel: { showEdit = false }
				)
			}

			// Enable / disable
			Button {
				vm.toggleSource(source: source)
			} label: {
				Image(systemName: source.isEnabled ? "pause.circle" : "play.circle")
					.foregroundStyle(source.isEnabled ? Color.secondary : Color.accentColor)
			}
			.buttonStyle(.plain)
			.help(source.isEnabled ? "Pause this source" : "Resume this source")

			// Delete
			Button(role: .destructive) {
				if let id = source.id { vm.deleteSource(id: id) }
			} label: {
				Image(systemName: "trash")
					.foregroundStyle(.red)
			}
			.buttonStyle(.plain)
			.help("Remove source")
		}
		.padding(.vertical, 4)
		.onAppear {
			if let id = source.id {
				pickerColor = colorStore.color(for: id)
			}
		}
	}
}

private struct EditSourcePopover: View {
	@Binding var name: String
	@Binding var url: String
	let onSave: () -> Void
	let onCancel: () -> Void

	var body: some View {
		VStack(alignment: .leading, spacing: 12) {
			Text("Edit Source")
				.font(.headline)

			VStack(alignment: .leading, spacing: 6) {
				Label("Name", systemImage: "textformat")
					.font(.system(size: 11, weight: .medium))
					.foregroundStyle(.secondary)
				TextField("Source name", text: $name)
					.textFieldStyle(.roundedBorder)
			}

			VStack(alignment: .leading, spacing: 6) {
				Label("Feed URL", systemImage: "link")
					.font(.system(size: 11, weight: .medium))
					.foregroundStyle(.secondary)
				TextField("https://example.com/feed.rss", text: $url)
					.textFieldStyle(.roundedBorder)
			}

			HStack {
				Button("Cancel", role: .cancel, action: onCancel)
					.buttonStyle(.bordered)
				Spacer()
				Button("Save", action: onSave)
					.buttonStyle(.borderedProminent)
					.disabled(url.trimmingCharacters(in: .whitespaces).isEmpty)
					.keyboardShortcut(.return)
			}
		}
		.padding(16)
		.frame(width: 280)
	}
}
