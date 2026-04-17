import AppKit
import SwiftUI

struct ContentView: View {
	@Environment(AppState.self) var appState
	@State private var articlesVM = ArticlesViewModel()
	@State private var sourcesVM = SourcesViewModel()
	private var weatherService = WeatherService.shared
	@State private var dailySummaryVM = DailySummaryViewModel()
	@State private var suggestedSourcesVM = SuggestedSourcesViewModel()
	@State private var quizStatsVM = QuizStatsViewModel()
	@State private var selectedDailySummaryArticle: Article?

	private var selectedSourceName: String? {
		guard let id = articlesVM.selectedSourceId else { return nil }
		return sourcesVM.sources.first { $0.id == id }?.name
	}

	private var sourceNames: [Int64: String] {
		sourcesVM.sources.reduce(into: [:]) { dict, source in
			if let id = source.id { dict[id] = source.name }
		}
	}

	var body: some View {
		NavigationSplitView {
			SidebarView(sourcesVM: sourcesVM, articlesVM: articlesVM)
				.frame(minWidth: 200, idealWidth: 220)
		} detail: {
			VStack(spacing: 0) {
				NewspaperHeaderView()
				if articlesVM.showDailySummary {
					DailySummaryView(
						vm: dailySummaryVM,
						sourceNames: sourceNames,
						searchText: articlesVM.searchText
					) { article in
						selectedDailySummaryArticle = article
					}
				} else if articlesVM.showSuggestedSources {
					SuggestedSourcesView(vm: suggestedSourcesVM, sourcesVM: sourcesVM, searchText: articlesVM.searchText)
				} else if articlesVM.showQuizStats {
					QuizStatsView(vm: quizStatsVM, articlesVM: articlesVM, sourceNames: sourceNames, searchText: articlesVM.searchText)
				} else {
					TagFilterBarView(sourcesVM: sourcesVM, articlesVM: articlesVM)
					ArticleGridView(vm: articlesVM, sourceName: selectedSourceName, sourcesCount: sourcesVM.sources.count, sourceNames: sourceNames)
				}
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

			ToolbarItem(placement: .primaryAction) {
				Toggle(isOn: $articlesVM.dimThumbnails) {
					Label("Dim Thumbnails", systemImage: articlesVM.dimThumbnails ? "moon.fill" : "moon")
				}
				.toggleStyle(.button)
				.tint(articlesVM.dimThumbnails ? .accentColor : nil)
				.help(articlesVM.dimThumbnails ? "Thumbnails dimmed — click to restore" : "Dim thumbnails")
			}

			ToolbarItem(placement: .primaryAction) {
				Menu {
					ForEach(DateRangeFilter.allCases, id: \.rawValue) { range in
						Button {
							articlesVM.setDateRange(range)
						} label: {
							HStack {
								Text(range.label)
								if articlesVM.dateRangeFilter == range {
									Image(systemName: "checkmark")
								}
							}
						}
					}
				} label: {
					Label(
						articlesVM.dateRangeFilter == .all ? "All Time" : articlesVM.dateRangeFilter.label,
						systemImage: "calendar"
					)
				}
				.help("Filter articles by date range")
			}

			ToolbarItem(placement: .principal) {
				SearchField(text: Binding(
					get: { articlesVM.searchText },
					set: { articlesVM.applySearch($0) }
				))
				.frame(width: 280)
			}
		}
		.sheet(item: $selectedDailySummaryArticle) { article in
			ArticleDetailView(article: article, vm: articlesVM, sourceName: sourceNames[article.sourceId])
				.frame(minWidth: 860, minHeight: 700)
		}
		.sheet(isPresented: Bindable(appState).showSourceManager) {
			SourceManagerView(vm: sourcesVM)
				.frame(minWidth: 600, minHeight: 500)
		}
		.task {
			// Initialise the notification delegate early so the system can deliver
			// any pending notifications that arrived while the app was not running.
			_ = NotificationService.shared

			sourcesVM.onSourceAdded = { [weak articlesVM, weak sourcesVM] in
				Task {
					await articlesVM?.refresh()
					sourcesVM?.load(dateRange: articlesVM?.dateRangeFilter ?? .today)
				}
			}
			// Keep sidebar badges in sync whenever an article is marked read.
			articlesVM.onArticleRead = { [weak articlesVM, weak sourcesVM] in
				sourcesVM?.refreshUnreadCounts(dateRange: articlesVM?.dateRangeFilter ?? .today)
			}
			// Trigger background daily summarization when readable content is cached
			// for a read article. Runs only when the feature is enabled.
			articlesVM.onReadArticleContentCached = { [weak appState] id, title, content in
				guard let appState, appState.dailySummaryEnabled else { return }
				let endpoint = appState.resolvedEndpoint
				let model = appState.resolvedModel
				Task {
					await DailySummaryService.shared.summarize(
						articleId: id,
						title: title,
						content: content,
						endpoint: endpoint,
						model: model
					)
				}
			}
			sourcesVM.load()
			await seedIfNeeded()
			// Load cached articles immediately, then fetch fresh content from the network.
			await articlesVM.initialLoad()
			await articlesVM.refresh()
			sourcesVM.load(dateRange: articlesVM.dateRangeFilter)  // Sync unread counts after the initial fetch

			// Catch up on any today's read articles that need daily summaries.
			if appState.dailySummaryEnabled {
				let endpoint = appState.resolvedEndpoint
				let model = appState.resolvedModel
				Task {
					await DailySummaryService.shared.processPending(endpoint: endpoint, model: model)
				}
			}
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
				await articlesVM.refresh(notifyIfNew: true)
				sourcesVM.load(dateRange: articlesVM.dateRangeFilter)  // Sync unread counts after background fetch
			}
		}
		.onChange(of: articlesVM.dateRangeFilter) { _, newRange in
			sourcesVM.refreshUnreadCounts(dateRange: newRange)
		}
		// When the feature is enabled mid-session, immediately catch up on any
		// today's read articles that have no summary yet (same sequential queue
		// as the startup path).
		.onChange(of: appState.dailySummaryEnabled) { _, enabled in
			guard enabled else { return }
			let endpoint = appState.resolvedEndpoint
			let model = appState.resolvedModel
			Task {
				await DailySummaryService.shared.processPending(endpoint: endpoint, model: model)
			}
		}
		.onChange(of: articlesVM.errorMessage) { _, msg in
			if msg != nil { NSSound.beep() }
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
