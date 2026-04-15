import Foundation
import WebKit

/// Extracts the main article content from a URL using Readability.js.
///
/// Strategy:
///   1. Fetch raw HTML via URLSession (fast, cancellation-safe).
///   2. Inject a restrictive CSP and hand the HTML to a per-call
///      ReadabilityExtractor that owns its own WKWebView.
///   3. Readability.js is injected after the DOM is ready; the result is
///      returned via a checked continuation.
///
/// Each call gets its own WKWebView so concurrent extractions are fully
/// isolated — there is no shared state or continuation that a second call
/// could clobber.
@MainActor
final class ReadabilityService: NSObject {
	static let shared = ReadabilityService()
	private override init() { super.init() }

	func extract(from url: URL) async throws -> ReadabilityResult {
		// Step 1: fetch HTML off the main actor — URLSession is thread-safe.
		let html = try await fetchHTML(from: url)

		// Step 2: inject a restrictive CSP before handing HTML to WebKit.
		let sanitizedHTML = injectCSP(into: html)

		// Step 3: delegate to a fresh per-call extractor.
		return try await ReadabilityExtractor(html: sanitizedHTML, baseURL: url).extract()
	}

	// MARK: - HTML fetch

	nonisolated func fetchHTML(from url: URL) async throws -> String {
		var request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 20)
		request.setValue(
			"Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.3 Safari/605.1.15",
			forHTTPHeaderField: "User-Agent"
		)
		request.setValue(
			"text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
			forHTTPHeaderField: "Accept"
		)
		request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
		request.setValue("gzip, deflate, br", forHTTPHeaderField: "Accept-Encoding")
		request.setValue("1", forHTTPHeaderField: "DNT")
		// Provide a plausible Referer so the server sees traffic arriving from a known entry point.
		if let host = url.host, let scheme = url.scheme {
			request.setValue("\(scheme)://\(host)/", forHTTPHeaderField: "Referer")
		}

		let (data, response) = try await URLSession.shared.data(for: request)

		// Determine encoding from Content-Type header; fall back to UTF-8 then Latin-1.
		var encoding = String.Encoding.utf8
		if let http = response as? HTTPURLResponse,
			let ct = http.value(forHTTPHeaderField: "Content-Type"),
			let charsetRange = ct.range(of: "charset=", options: .caseInsensitive)
		{
			let charsetString = String(ct[charsetRange.upperBound...])
				.components(separatedBy: ";").first?
				.trimmingCharacters(in: .whitespaces) ?? ""
			let cfEncoding = CFStringConvertIANACharSetNameToEncoding(charsetString as CFString)
			if cfEncoding != kCFStringEncodingInvalidId {
				encoding = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cfEncoding))
			}
		}

		if let html = String(data: data, encoding: encoding) { return html }
		if let html = String(data: data, encoding: .isoLatin1) { return html }
		throw NewsError.parseFailed("Could not decode response from \(url.host ?? url.absoluteString)")
	}

	// MARK: - CSP injection

	/// Injects a restrictive CSP <meta> tag as the very first child of <head> (or
	/// prepends a <head> block if none is present). This blocks scripts, inline
	/// event handlers, and external resource loads beyond images — keeping the HTML
	/// safe for DOM-only parsing via Readability.js.
	nonisolated func injectCSP(into html: String) -> String {
		let cspMeta = """
		<meta http-equiv="Content-Security-Policy" \
		content="default-src 'none'; img-src * data: blob:; style-src 'unsafe-inline'; \
		script-src 'none'; object-src 'none'; base-uri 'none'; form-action 'none';">
		"""
		if let headRange = html.range(of: "<head>", options: .caseInsensitive) {
			var result = html
			result.insert(contentsOf: "\n" + cspMeta, at: headRange.upperBound)
			return result
		}
		if let htmlRange = html.range(of: "<html", options: .caseInsensitive),
			let closeAngle = html[htmlRange.upperBound...].firstIndex(of: ">")
		{
			var result = html
			let insertAt = html.index(after: closeAngle)
			result.insert(contentsOf: "\n<head>\n" + cspMeta + "\n</head>", at: insertAt)
			return result
		}
		return "<head>\n\(cspMeta)\n</head>\n" + html
	}
}

// MARK: - Per-call extractor

/// Owns a single WKWebView for the lifetime of one extraction call.
/// A temporary retain cycle (retainSelf) keeps the instance alive while
/// WebKit's weak navigationDelegate reference is the only reference to it.
/// The cycle is broken in finish(with:) when the continuation is resumed.
@MainActor
private final class ReadabilityExtractor: NSObject, WKNavigationDelegate {
	private let html: String
	private let baseURL: URL
	private var webView: WKWebView?
	private var continuation: CheckedContinuation<ReadabilityResult, Error>?
	private var retainSelf: ReadabilityExtractor?

	init(html: String, baseURL: URL) {
		self.html = html
		self.baseURL = baseURL
	}

	func extract() async throws -> ReadabilityResult {
		try await withCheckedThrowingContinuation { continuation in
			self.continuation = continuation
			retainSelf = self  // Keep alive while WKWebView holds a weak delegate ref

			let config = WKWebViewConfiguration()
			config.defaultWebpagePreferences.allowsContentJavaScript = false
			config.preferences.isElementFullscreenEnabled = false
			let wv = WKWebView(frame: .zero, configuration: config)
			wv.navigationDelegate = self
			webView = wv
			wv.loadHTMLString(html, baseURL: baseURL)
		}
	}

	// MARK: - WKNavigationDelegate

	nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
		Task { @MainActor in self.injectReadability() }
	}

	nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
		Task { @MainActor in self.finish(with: .failure(error)) }
	}

	nonisolated func webView(
		_ webView: WKWebView,
		didFailProvisionalNavigation navigation: WKNavigation!,
		withError error: Error
	) {
		Task { @MainActor in self.finish(with: .failure(error)) }
	}

	// MARK: - Readability injection

	private func injectReadability() {
		guard
			let jsURL = Bundle.module.url(forResource: "Readability", withExtension: "js"),
			let js = try? String(contentsOf: jsURL, encoding: .utf8)
		else {
			finish(with: .failure(NewsError.parseFailed("Readability.js not found in bundle")))
			return
		}

		let runner = """
		(function() {
		    \(js)
		    try {
		        var article = new Readability(document.cloneNode(true)).parse();
		        if (article) {
		            return JSON.stringify({
		                title: article.title || '',
		                byline: article.byline || '',
		                content: article.content || '',
		                textContent: article.textContent || '',
		                excerpt: article.excerpt || ''
		            });
		        }
		        return JSON.stringify({ error: 'Readability could not parse this page' });
		    } catch(e) {
		        return JSON.stringify({ error: e.message });
		    }
		})();
		"""

		webView?.evaluateJavaScript(runner) { [weak self] result, error in
			guard let self else { return }

			if let error {
				self.finish(with: .failure(NewsError.parseFailed(error.localizedDescription)))
				return
			}

			guard
				let jsonString = result as? String,
				let data = jsonString.data(using: .utf8),
				let parsed = try? JSONDecoder().decode(ReadabilityRaw.self, from: data)
			else {
				self.finish(with: .failure(NewsError.parseFailed("Unexpected Readability output")))
				return
			}

			if let err = parsed.error {
				self.finish(with: .failure(NewsError.parseFailed(err)))
			} else {
				self.finish(with: .success(ReadabilityResult(
					title: parsed.title ?? "",
					byline: parsed.byline,
					htmlContent: parsed.content ?? "",
					textContent: parsed.textContent ?? "",
					excerpt: parsed.excerpt
				)))
			}
		}
	}

	private func finish(with result: Result<ReadabilityResult, Error>) {
		webView?.navigationDelegate = nil
		webView = nil
		let c = continuation
		continuation = nil
		retainSelf = nil  // Break retain cycle — self may dealloc after this line
		switch result {
		case .success(let r): c?.resume(returning: r)
		case .failure(let e): c?.resume(throwing: e)
		}
	}
}

// MARK: - Types

struct ReadabilityResult {
	let title: String
	let byline: String?
	let htmlContent: String
	let textContent: String
	let excerpt: String?
}

private struct ReadabilityRaw: Codable {
	let title: String?
	let byline: String?
	let content: String?
	let textContent: String?
	let excerpt: String?
	let error: String?
}
