import Foundation
import WebKit

/// Extracts the main article content from a URL using Readability.js.
///
/// Strategy:
///   1. Fetch raw HTML via URLSession (fast, cancellation-safe).
///   2. Load the HTML string into a hidden WKWebView with the original URL
///      as base URL so relative links resolve correctly.
///   3. Inject Readability.js after the DOM is ready and return the result.
///
/// Using URLSession for the network request avoids NSURLErrorCancelled (-999)
/// errors that occur when calling WKWebView.stopLoading() on an in-flight
/// navigation.
@MainActor
final class ReadabilityService: NSObject {
	static let shared = ReadabilityService()

	private var webView: WKWebView?
	private var pendingContinuation: CheckedContinuation<ReadabilityResult, Error>?

	private override init() {
		super.init()
		let config = WKWebViewConfiguration()
		config.defaultWebpagePreferences.allowsContentJavaScript = false // static HTML only
		config.preferences.isElementFullscreenEnabled = false
		let wv = WKWebView(frame: .zero, configuration: config)
		wv.navigationDelegate = self
		webView = wv
	}

	func extract(from url: URL) async throws -> ReadabilityResult {
		// Step 1: fetch HTML with URLSession — no WKWebView navigation involved.
		let html = try await fetchHTML(from: url)

		// Step 2: inject a restrictive Content Security Policy before loading into
		// WKWebView. This prevents script execution and limits resource origins even
		// though allowsContentJavaScript is already false, providing defence-in-depth
		// against XSS from untrusted remote HTML (CWE-79).
		let sanitizedHTML = injectCSP(into: html)

		// Step 3: hand off to the WKWebView as a static string.
		return try await withCheckedThrowingContinuation { continuation in
			// Discard any leftover continuation from a previous (already-resolved) call.
			pendingContinuation = continuation
			webView?.loadHTMLString(sanitizedHTML, baseURL: url)
		}
	}

	/// Injects a restrictive CSP <meta> tag as the very first child of <head> (or
	/// prepends a <head> block if none is present). This blocks scripts, inline
	/// event handlers, and external resource loads beyond images — keeping the HTML
	/// safe for DOM-only parsing via Readability.js.
	private func injectCSP(into html: String) -> String {
		let cspMeta = """
		<meta http-equiv="Content-Security-Policy" \
		content="default-src 'none'; img-src * data: blob:; style-src 'unsafe-inline'; \
		script-src 'none'; object-src 'none'; base-uri 'none'; form-action 'none';">
		"""
		// Insert after opening <head> tag if present.
		if let headRange = html.range(of: "<head>", options: .caseInsensitive) {
			var result = html
			result.insert(contentsOf: "\n" + cspMeta, at: headRange.upperBound)
			return result
		}
		// Insert after <html> tag if present but no <head>.
		if let htmlRange = html.range(of: "<html", options: .caseInsensitive),
			let closeAngle = html[htmlRange.upperBound...].firstIndex(of: ">")
		{
			var result = html
			let insertAt = html.index(after: closeAngle)
			result.insert(contentsOf: "\n<head>\n" + cspMeta + "\n</head>", at: insertAt)
			return result
		}
		// Fallback: prepend a minimal head block.
		return "<head>\n\(cspMeta)\n</head>\n" + html
	}

	// MARK: - Private

	private func fetchHTML(from url: URL) async throws -> String {
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

	private func injectReadability() {
		guard
			let jsURL = Bundle.module.url(forResource: "Readability", withExtension: "js"),
			let js = try? String(contentsOf: jsURL, encoding: .utf8)
		else {
			pendingContinuation?.resume(throwing: NewsError.parseFailed("Readability.js not found in bundle"))
			pendingContinuation = nil
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
			defer { self.pendingContinuation = nil }

			if let error {
				self.pendingContinuation?.resume(
					throwing: NewsError.parseFailed(error.localizedDescription)
				)
				return
			}

			guard
				let jsonString = result as? String,
				let data = jsonString.data(using: .utf8),
				let parsed = try? JSONDecoder().decode(ReadabilityRaw.self, from: data)
			else {
				self.pendingContinuation?.resume(
					throwing: NewsError.parseFailed("Unexpected Readability output")
				)
				return
			}

			if let err = parsed.error {
				self.pendingContinuation?.resume(throwing: NewsError.parseFailed(err))
			} else {
				self.pendingContinuation?.resume(returning: ReadabilityResult(
					title: parsed.title ?? "",
					byline: parsed.byline,
					htmlContent: parsed.content ?? "",
					textContent: parsed.textContent ?? "",
					excerpt: parsed.excerpt
				))
			}
		}
	}
}

// MARK: - WKNavigationDelegate

extension ReadabilityService: WKNavigationDelegate {
	nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
		Task { @MainActor in self.injectReadability() }
	}

	nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
		Task { @MainActor in
			self.pendingContinuation?.resume(throwing: error)
			self.pendingContinuation = nil
		}
	}

	nonisolated func webView(
		_ webView: WKWebView,
		didFailProvisionalNavigation navigation: WKNavigation!,
		withError error: Error
	) {
		Task { @MainActor in
			self.pendingContinuation?.resume(throwing: error)
			self.pendingContinuation = nil
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
