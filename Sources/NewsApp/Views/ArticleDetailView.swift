import SwiftUI
import WebKit

struct ArticleDetailView: View {
	let article: Article
	@ObservedObject var vm: ArticlesViewModel
	@EnvironmentObject var appState: AppState
	@StateObject private var detailVM = ArticleDetailViewModel()
	@Environment(\.dismiss) private var dismiss

	@State private var readabilityResult: ReadabilityResult?
	@State private var displayTitle: String
	@State private var displaySummary: String

	init(article: Article, vm: ArticlesViewModel) {
		self.article = article
		self.vm = vm
		_displayTitle = State(initialValue: article.rewrittenTitle ?? article.title)
		_displaySummary = State(initialValue: article.summary ?? "")
	}

	var body: some View {
		VStack(spacing: 0) {
			// Toolbar
			HStack {
				Button { dismiss() } label: {
					Image(systemName: "xmark.circle.fill")
						.font(.title3)
						.foregroundStyle(.secondary)
				}
				.buttonStyle(.plain)

				Spacer()

				if detailVM.isLoadingContent {
					ProgressView().scaleEffect(0.7)
				}

				Button {
					Task { await rewriteWithAI() }
				} label: {
					Label(
						detailVM.isProcessingAI ? "Processing…" : "AI Rewrite",
						systemImage: "sparkles"
					)
					.font(.system(size: 12))
				}
				.buttonStyle(.borderedProminent)
				.controlSize(.small)
				.disabled(detailVM.isProcessingAI)

				if let articleURL = URL(string: article.articleURL) {
					Link(destination: articleURL) {
						Label("Open in Browser", systemImage: "arrow.up.right.square")
							.font(.system(size: 12))
					}
					.buttonStyle(.bordered)
					.controlSize(.small)
				}
			}
			.padding(.horizontal, 20)
			.padding(.vertical, 12)

			Divider()

			ScrollView {
				VStack(alignment: .leading, spacing: 16) {
					// Header meta
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

						// Byline / summary row
						if let byline = readabilityResult?.byline ?? article.author {
							Text("By \(byline)")
								.font(.system(size: 13, weight: .medium))
								.foregroundStyle(.secondary)
						}

						HStack {
							Text(article.publishedAt, style: .date)
							if let sourceName = readabilityResult?.title, sourceName != displayTitle {
								Text("·")
								Text(sourceName)
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

					Divider()

					// Article content
					if let result = readabilityResult {
						ArticleWebContentView(
							htmlContent: result.htmlContent,
							accessibilityText: result.textContent
						)
						.frame(minHeight: 400)
					} else {
						Text("Loading article content…")
							.foregroundStyle(.secondary)
							.frame(maxWidth: .infinity, alignment: .center)
							.padding(.top, 40)
					}
				}
				.padding(.horizontal, 40)
				.padding(.vertical, 24)
				.frame(maxWidth: 760, alignment: .leading)
				.frame(maxWidth: .infinity)
			}
		}
		.task {
			vm.markRead(article)
			readabilityResult = await detailVM.loadContent(for: article)
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

	private func rewriteWithAI() async {
		let content = readabilityResult?.textContent ?? article.readableContent ?? article.summary ?? article.title
		if let result = await detailVM.rewriteWithAI(
			article: article,
			content: content,
			endpoint: appState.ollamaEndpoint,
			model: appState.ollamaModel
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

	var body: some View {
		_ArticleWebView(htmlContent: htmlContent)
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

	func makeNSView(context: Context) -> WKWebView {
		let config = WKWebViewConfiguration()
		config.defaultWebpagePreferences.allowsContentJavaScript = false // Static rendering only
		let wv = WKWebView(frame: .zero, configuration: config)
		wv.navigationDelegate = context.coordinator
		return wv
	}

	func updateNSView(_ wv: WKWebView, context: Context) {
		let styledHTML = """
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
		    font-size: 17px;
		    line-height: 1.75;
		    max-width: 700px;
		    margin: 0 auto;
		    padding: 0 16px 48px;
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
		wv.loadHTMLString(styledHTML, baseURL: nil)
	}

	func makeCoordinator() -> Coordinator { Coordinator() }

	final class Coordinator: NSObject, WKNavigationDelegate {
		@MainActor
		func webView(
			_ webView: WKWebView,
			decidePolicyFor navigationAction: WKNavigationAction,
			decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
		) {
			// Only allow the initial HTML load; open external links in browser
			if navigationAction.navigationType == .linkActivated,
				let url = navigationAction.request.url
			{
				NSWorkspace.shared.open(url)
				decisionHandler(.cancel)
			} else {
				decisionHandler(.allow)
			}
		}
	}
}
