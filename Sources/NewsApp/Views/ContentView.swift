import SwiftUI

struct ContentView: View {
	@EnvironmentObject var appState: AppState
	@StateObject private var articlesVM = ArticlesViewModel()
	@StateObject private var sourcesVM = SourcesViewModel()
	@StateObject private var weatherService = WeatherService.shared

	private var selectedSourceName: String? {
		guard let id = articlesVM.selectedSourceId else { return nil }
		return sourcesVM.sources.first { $0.id == id }?.name
	}

	var body: some View {
		NavigationSplitView {
			SidebarView(sourcesVM: sourcesVM, articlesVM: articlesVM)
				.frame(minWidth: 200, idealWidth: 220)
		} detail: {
			VStack(spacing: 0) {
				NewspaperHeaderView()
				TagFilterBarView(sourcesVM: sourcesVM, articlesVM: articlesVM)
				ArticleGridView(vm: articlesVM, sourceName: selectedSourceName)
			}
		}
		.toolbar {
			ToolbarItem(placement: .primaryAction) {
				Button {
					Task { await articlesVM.refresh() }
				} label: {
					Label("Refresh", systemImage: "arrow.clockwise")
				}
				.disabled(articlesVM.isRefreshing)
			}

			ToolbarItem(placement: .primaryAction) {
				Toggle(isOn: Binding(
					get: { articlesVM.hideRead },
					set: { _ in articlesVM.toggleHideRead() }
				)) {
					Label(
						articlesVM.hideRead ? "Showing Unread" : "Show Unread Only",
						systemImage: articlesVM.hideRead ? "eye.slash.fill" : "eye"
					)
				}
				.toggleStyle(.button)
				.tint(articlesVM.hideRead ? .accentColor : nil)
				.help(articlesVM.hideRead ? "Showing unread articles only — click to show all" : "Filter to unread articles only")
			}

			ToolbarItem(placement: .principal) {
				SearchField(text: Binding(
					get: { articlesVM.searchText },
					set: { articlesVM.applySearch($0) }
				))
				.frame(width: 280)
			}
		}
		.sheet(isPresented: $appState.showSourceManager) {
			SourceManagerView(vm: sourcesVM)
				.frame(minWidth: 600, minHeight: 500)
		}
		.task {
			sourcesVM.onSourceAdded = { [weak articlesVM] in
				Task { await articlesVM?.refresh() }
			}
			sourcesVM.load()
			await seedIfNeeded()
			// Load cached articles immediately, then fetch fresh content from the network.
			await articlesVM.initialLoad()
			await articlesVM.refresh()
			if appState.hasWeather {
				await weatherService.fetchWeather(apiKey: appState.openWeatherApiKey)
			}
		}
		.task(id: appState.autoRefreshInterval) {
			guard appState.autoRefreshInterval > 0 else { return }
			let interval = TimeInterval(appState.autoRefreshInterval * 60)
			while !Task.isCancelled {
				try? await Task.sleep(for: .seconds(interval))
				guard !Task.isCancelled else { break }
				await articlesVM.refresh()
			}
		}
		.alert("Error", isPresented: Binding(
			get: { articlesVM.errorMessage != nil },
			set: { if !$0 { articlesVM.errorMessage = nil } }
		)) {
			Button("OK") { articlesVM.errorMessage = nil }
		} message: {
			Text(articlesVM.errorMessage ?? "")
		}
	}

	private func seedIfNeeded() async {
		do {
			try SourceRepository().seedDefaultSources()
			try TagRepository().seedDefaultTags()
		} catch {}
	}
}
