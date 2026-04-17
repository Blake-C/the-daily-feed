import AppKit
import SwiftUI
import WebKit

struct ArticleDetailView: View {
	let article: Article
	@ObservedObject var vm: ArticlesViewModel
	var sourceName: String?
	@EnvironmentObject var appState: AppState
	@StateObject private var detailVM = ArticleDetailViewModel()
	@Environment(\.dismiss) private var dismiss

	@State private var readabilityResult: ReadabilityResult?
	@State private var displayTitle: String
	@State private var displaySummary: String
	@State private var isBookmarked: Bool

	// Quiz state
	@State private var showQuiz = false

	// Find-in-article state
	@State private var showFind = false
	@State private var findText = ""
	@State private var findTrigger = 0
	@State private var findBackward = false
	@FocusState private var findFieldFocused: Bool

	// Keep local bookmark state in sync after toggle so the button updates immediately.
	private func toggleBookmark() {
		vm.toggleBookmark(article)
		isBookmarked.toggle()
	}

	init(article: Article, vm: ArticlesViewModel, sourceName: String? = nil) {
		self.article = article
		self.vm = vm
		self.sourceName = sourceName
		_displayTitle = State(initialValue: article.rewrittenTitle ?? article.title)
		_displaySummary = State(initialValue: article.summary ?? "")
		_isBookmarked = State(initialValue: article.isBookmarked)
	}

	var body: some View {
		VStack(spacing: 0) {
			// Toolbar
			HStack(alignment: .center, spacing: 8) {
				Button { dismiss() } label: {
					Image(systemName: "xmark.circle.fill")
						.font(.system(size: 17))
						.foregroundStyle(.secondary)
				}
				.buttonStyle(.plain)
				.frame(width: 28, height: 28)

				Spacer()

				if detailVM.isLoadingContent {
					ProgressView()
						.scaleEffect(0.7)
						.frame(width: 22, height: 22)
				}

				// AI Summary — shown only when the feature is enabled
				if appState.aiSummaryEnabled {
					Button {
						Task { await rewriteWithAI() }
					} label: {
						Label(
							detailVM.isProcessingAI ? "Processing…" : "AI Summary",
							systemImage: "sparkles"
						)
						.font(.system(size: 12))
					}
					.buttonStyle(.borderedProminent)
					.controlSize(.small)
					.disabled(detailVM.isProcessingAI)

					Divider()
						.frame(height: 16)
				}

				// Quiz — shown only when the feature is enabled
				if appState.quizEnabled {
					Button {
						if showQuiz {
							showQuiz = false
						} else {
							showQuiz = true
							if detailVM.quizQuestions.isEmpty && !detailVM.isGeneratingQuiz {
								Task { await generateQuiz() }
							}
						}
					} label: {
						Label(
							detailVM.isGeneratingQuiz ? "Generating…" : "Test Your Knowledge",
							systemImage: "brain.head.profile"
						)
						.font(.system(size: 12))
					}
					.buttonStyle(.bordered)
					.controlSize(.small)
					.disabled(detailVM.isGeneratingQuiz)

					Divider()
						.frame(height: 16)
				}

				// Secondary icon-only actions — uniform 28×28 tap targets
				Button { toggleBookmark() } label: {
					Image(systemName: isBookmarked ? "bookmark.fill" : "bookmark")
						.font(.system(size: 15))
				}
				.buttonStyle(.plain)
				.foregroundStyle(isBookmarked ? Color.accentColor : .secondary)
				.frame(width: 28, height: 28)
				.help(isBookmarked ? "Remove bookmark" : "Bookmark article")

				// Share and open-in-browser as direct toolbar buttons so
				// NSSharingServicePicker anchors correctly to the button frame.
				if let articleURL = URL(string: article.articleURL) {
					ShareLink(item: articleURL) {
						Image(systemName: "square.and.arrow.up")
							.font(.system(size: 13))
							.foregroundStyle(.secondary)
					}
					.buttonStyle(.plain)
					.frame(width: 28, height: 28)
					.help("Share article")

					Button {
						NSWorkspace.shared.open(articleURL)
					} label: {
						Image(systemName: "arrow.up.right.square")
							.font(.system(size: 15))
							.foregroundStyle(.secondary)
					}
					.buttonStyle(.plain)
					.frame(width: 28, height: 28)
					.help("Open in browser: \(articleURL.absoluteString)")
				}
			}
			.padding(.horizontal, 16)
			.padding(.vertical, 8)

			Divider()

			// Find bar — visible when ⌘F is pressed
			if showFind {
				HStack(spacing: 8) {
					Image(systemName: "magnifyingglass")
						.foregroundStyle(.secondary)
						.font(.system(size: 12))
					TextField("Find in article…", text: $findText)
						.textFieldStyle(.plain)
						.font(.system(size: 13))
						.focused($findFieldFocused)
						.onSubmit {
							findTrigger += 1
							findBackward = false
						}
					if !findText.isEmpty {
						Button {
							findTrigger += 1
							findBackward = false
						} label: {
							Image(systemName: "chevron.down")
								.font(.system(size: 11, weight: .medium))
						}
						.buttonStyle(.plain)
						.foregroundStyle(.secondary)
						.help("Next match (⌘G)")
						Button {
							findTrigger += 1
							findBackward = true
						} label: {
							Image(systemName: "chevron.up")
								.font(.system(size: 11, weight: .medium))
						}
						.buttonStyle(.plain)
						.foregroundStyle(.secondary)
						.help("Previous match (⇧⌘G)")
						Button { findText = "" } label: {
							Image(systemName: "xmark.circle.fill")
								.foregroundStyle(.secondary)
								.font(.system(size: 11))
						}
						.buttonStyle(.plain)
					}
					Spacer()
					Button {
						showFind = false
						findText = ""
					} label: {
						Text("Done")
							.font(.system(size: 12))
					}
					.buttonStyle(.plain)
					.foregroundStyle(.secondary)
				}
				.padding(.horizontal, 16)
				.padding(.vertical, 7)
				.background(Color(NSColor.controlBackgroundColor))
				Divider()
			}

			GeometryReader { geo in
				HStack(alignment: .top, spacing: 0) {
					// Article column — header pinned at top, WebView fills remaining height
					VStack(alignment: .leading, spacing: 0) {
						// Header meta (title, byline, date, AI summary)
						VStack(alignment: .leading, spacing: 6) {
							// Category tags
							if !article.tagList.isEmpty {
								HStack(spacing: 6) {
									ForEach(article.tagList.prefix(4), id: \.self) { tag in
										Text(tag.uppercased())
											.font(.system(size: 10, weight: .bold))
											.foregroundStyle(Color.accentColor)
									}
								}
							}

							// Title
							Text(displayTitle)
								.font(.system(size: 26, weight: .bold, design: .serif))
								.textSelection(.enabled)

							// Byline
							if let byline = readabilityResult?.byline ?? article.author, !byline.trimmingCharacters(in: .whitespaces).isEmpty {
								Text("By \(byline)")
									.font(.system(size: 13, weight: .medium))
									.foregroundStyle(.secondary)
									.textSelection(.enabled)
							}

							HStack {
								Text(article.publishedAt, style: .date)
								if let name = sourceName {
									Text("·")
									Text(name)
										.lineLimit(1)
								}
							}
							.font(.system(size: 12))
							.foregroundStyle(.tertiary)

							// AI Summary
							if !displaySummary.isEmpty {
								Text(displaySummary)
									.font(.system(size: 14, weight: .regular, design: .serif))
									.italic()
									.foregroundStyle(.secondary)
									.textSelection(.enabled)
									.padding(12)
									.background(Color.accentColor.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
							}
						}
						.padding(.horizontal, 24)
						.padding(.top, 16)
						.padding(.bottom, 12)
						.frame(maxWidth: 760, alignment: .leading)
						.frame(maxWidth: .infinity, alignment: .leading)

						Divider()

						// Article body — WKWebView fills remaining height with native scrolling
						if let result = readabilityResult {
							ArticleWebContentView(
								htmlContent: result.htmlContent,
								accessibilityText: result.textContent,
								findQuery: findText,
								findTrigger: findTrigger,
								findBackward: findBackward
							)
							.padding(.horizontal, 24)
							.frame(maxWidth: .infinity, maxHeight: .infinity)
						} else {
							Text("Loading article content…")
								.foregroundStyle(.secondary)
								.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
						}
					}
					.frame(height: geo.size.height)

					// Quiz side panel — capped to available height, scrolls internally
					if showQuiz {
						Divider()
						ArticleQuizView(
							questions: detailVM.quizQuestions,
							isLoading: detailVM.isGeneratingQuiz,
							statusMessage: detailVM.quizStatusMessage,
							onClose: { showQuiz = false }
						) { correct, total in
							detailVM.saveQuizResult(
								articleId: article.id,
								articleTitle: article.title,
								score: correct,
								total: total
							)
						}
						.frame(width: 340, height: geo.size.height)
						.transition(.move(edge: .trailing).combined(with: .opacity))
					}
				}
				.frame(width: geo.size.width)
			}
			.frame(maxWidth: .infinity, maxHeight: .infinity)
			.animation(.easeInOut(duration: 0.2), value: showQuiz)
		}
		// Keyboard shortcuts — hidden buttons stay in the responder chain
		.background {
			Group {
				Button("") {
					showFind = true
				}
				.keyboardShortcut("f", modifiers: .command)
				Button("") {
					guard showFind, !findText.isEmpty else { return }
					findTrigger += 1
					findBackward = false
				}
				.keyboardShortcut("g", modifiers: .command)
				Button("") {
					guard showFind, !findText.isEmpty else { return }
					findTrigger += 1
					findBackward = true
				}
				.keyboardShortcut("g", modifiers: [.command, .shift])
			}
			.hidden()
		}
		.onChange(of: showFind) { _, visible in
			if visible { findFieldFocused = true }
		}
		.task {
			vm.markRead(article)
			if let result = await detailVM.loadContent(for: article) {
				readabilityResult = result
				// Route through articlesVM so onReadArticleContentCached fires for daily summary.
				vm.cacheContent(id: article.id, rawContent: result.htmlContent, readableContent: result.htmlContent)
			}
		}
		.onChange(of: detailVM.errorMessage) { _, msg in
			if msg != nil { NSSound.beep() }
		}
		.alert("Error", isPresented: Binding(
			get: { detailVM.errorMessage != nil },
			set: { if !$0 { detailVM.errorMessage = nil } }
		)) {
			Button("OK") { detailVM.errorMessage = nil }
		} message: {
			Text(detailVM.errorMessage ?? "")
		}
	}

	private func generateQuiz() async {
		let content = readabilityResult?.textContent ?? article.readableContent ?? article.summary ?? article.title
		await detailVM.generateQuiz(
			article: article,
			content: content,
			endpoint: appState.ollamaEndpoint,
			model: appState.ollamaModel
		)
	}

	private func rewriteWithAI() async {
		let content = readabilityResult?.textContent ?? article.readableContent ?? article.summary ?? article.title
		if let result = await detailVM.rewriteWithAI(
			article: article,
			content: content,
			endpoint: appState.ollamaEndpoint,
			model: appState.ollamaModel,
			customPrompt: appState.ollamaPrompt
		) {
			displayTitle = result.headline
			displaySummary = result.summary
			vm.updateAfterRewrite(id: article.id, title: result.headline, summary: result.summary)
		}
	}
}

// MARK: - Web content renderer

struct ArticleWebContentView: View {
	let htmlContent: String
	let accessibilityText: String
	var findQuery: String = ""
	var findTrigger: Int = 0
	var findBackward: Bool = false

	var body: some View {
		_ArticleWebView(
			htmlContent: htmlContent,
			findQuery: findQuery,
			findTrigger: findTrigger,
			findBackward: findBackward
		)
		// Provide the plain-text content as the accessibility representation so
		// VoiceOver, TTS, and other assistive technologies can read the article.
		.accessibilityRepresentation {
			ScrollView {
				Text(accessibilityText)
					.font(.body)
					.accessibilityLabel(accessibilityText)
			}
		}
	}
}

private struct _ArticleWebView: NSViewRepresentable {
	let htmlContent: String
	var findQuery: String = ""
	var findTrigger: Int = 0
	var findBackward: Bool = false
	@AppStorage("articleFontSize") private var fontSize: Int = 17

	func makeNSView(context: Context) -> WKWebView {
		let config = WKWebViewConfiguration()
		config.defaultWebpagePreferences.allowsContentJavaScript = false // Static rendering only

		// Inject a trusted script (not affected by allowsContentJavaScript) that:
		// 1. Adds title="<href>" to every anchor that has an href but no title, so
		//    hovering a link shows its destination URL (security transparency).
		// 2. Unwraps anchor tags with no href so they don't appear as dead links.
		let anchorScript = WKUserScript(
			source: """
			document.querySelectorAll('a').forEach(function(a) {
				var href = a.getAttribute('href');
				if (href) {
					if (!a.hasAttribute('title')) {
						a.setAttribute('title', href);
					}
				} else {
					var parent = a.parentNode;
					if (parent) {
						while (a.firstChild) { parent.insertBefore(a.firstChild, a); }
						parent.removeChild(a);
					}
				}
			});
			""",
			injectionTime: .atDocumentEnd,
			forMainFrameOnly: true
		)
		config.userContentController.addUserScript(anchorScript)

		let wv = WKWebView(frame: .zero, configuration: config)
		wv.navigationDelegate = context.coordinator
		return wv
	}

	func updateNSView(_ wv: WKWebView, context: Context) {
		let styledHTML = buildHTML()

		// Only reload the page when the HTML content actually changes; reloading
		// on every SwiftUI pass would reset scroll position and clear find highlights.
		if context.coordinator.loadedHTML != styledHTML {
			context.coordinator.loadedHTML = styledHTML
			// Reset find tracking so stale queries aren't re-fired after reload.
			context.coordinator.lastFindQuery = ""
			context.coordinator.lastFindTrigger = -1
			wv.loadHTMLString(styledHTML, baseURL: nil)
			return
		}

		// Drive WKWebView find when the query text or advance trigger changes.
		let queryChanged = context.coordinator.lastFindQuery != findQuery
		let triggerChanged = context.coordinator.lastFindTrigger != findTrigger

		guard queryChanged || triggerChanged else { return }
		context.coordinator.lastFindQuery = findQuery
		context.coordinator.lastFindTrigger = findTrigger

		guard !findQuery.isEmpty else { return }
		let findConfig = WKFindConfiguration()
		findConfig.wraps = true
		findConfig.backwards = findBackward
		wv.find(findQuery, configuration: findConfig) { _ in }
	}

	private func buildHTML() -> String {
		"""
		<!DOCTYPE html>
		<html>
		<head>
		<meta charset="UTF-8">
		<meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src * data: blob:; style-src 'unsafe-inline'; script-src 'none'; object-src 'none'; base-uri 'none'; form-action 'none';">
		<meta name="color-scheme" content="light dark">
		<style>
		  :root { color-scheme: light dark; }
		  body {
		    font-family: Georgia, "Times New Roman", serif;
		    font-size: \(fontSize)px;
		    line-height: 1.75;
		    max-width: 712px;
		    margin: 0 auto;
		    padding: 0 0 48px;
		    color: light-dark(#1a1a1a, #e8e8e8);
		    background: transparent;
		  }
		  h1, h2, h3 { font-weight: 700; line-height: 1.3; }
		  a { color: light-dark(#1a6fb5, #5aacf5); }
		  img { max-width: 100%; height: auto; border-radius: 6px; margin: 16px 0; }
		  blockquote {
		    border-left: 3px solid light-dark(#ccc, #555);
		    margin: 16px 0;
		    padding: 8px 16px;
		    color: light-dark(#555, #aaa);
		  }
		  figure { margin: 16px 0; }
		  figcaption { font-size: 13px; color: light-dark(#777, #888); margin-top: 6px; }
		  pre, code { font-family: "SF Mono", monospace; font-size: 14px; }
		</style>
		</head>
		<body>\(htmlContent)</body>
		</html>
		"""
	}

	func makeCoordinator() -> Coordinator { Coordinator() }

	final class Coordinator: NSObject, WKNavigationDelegate {
		/// The last fully-rendered HTML string loaded into the WKWebView.
		/// Used to skip redundant `loadHTMLString` calls on every SwiftUI pass.
		var loadedHTML: String = ""
		var lastFindQuery: String = ""
		var lastFindTrigger: Int = -1

		@MainActor
		func webView(
			_ webView: WKWebView,
			decidePolicyFor navigationAction: WKNavigationAction,
			decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
		) {
			// Only allow the initial HTML load; open external links in the system browser.
			// Restrict to http/https to prevent custom URL schemes, file://, or
			// applescript: links embedded in feed content from being dispatched.
			if navigationAction.navigationType == .linkActivated,
				let url = navigationAction.request.url
			{
				let scheme = url.scheme?.lowercased() ?? ""
				if scheme == "http" || scheme == "https" {
					NSWorkspace.shared.open(url)
				}
				decisionHandler(.cancel)
			} else {
				decisionHandler(.allow)
			}
		}
	}
}
