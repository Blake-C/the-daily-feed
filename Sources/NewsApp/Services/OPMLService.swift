import Foundation

struct OPMLOutline {
	let title: String
	let xmlUrl: String
}

/// Parses OPML XML into feed outlines and generates OPML XML from a source list.
final class OPMLService: NSObject, XMLParserDelegate {
	private var outlines: [OPMLOutline] = []
	private var parseError: Error?

	/// Parse raw OPML data and return all feed outlines found (flattened from any folder hierarchy).
	func parse(data: Data) throws -> [OPMLOutline] {
		outlines = []
		parseError = nil
		let parser = XMLParser(data: data)
		parser.delegate = self
		parser.parse()
		if let error = parseError { throw error }
		return outlines
	}

	// MARK: - XMLParserDelegate

	func parser(
		_ parser: XMLParser,
		didStartElement elementName: String,
		namespaceURI _: String?,
		qualifiedName _: String?,
		attributes: [String: String]
	) {
		guard elementName == "outline" else { return }
		// Normalise keys — some generators emit "xmlUrl", others "xmlurl" or "XMLURL".
		let attrs = Dictionary(uniqueKeysWithValues: attributes.map { ($0.key.lowercased(), $0.value) })
		guard let xmlUrl = attrs["xmlurl"], !xmlUrl.isEmpty else { return }
		let title = attrs["title"] ?? attrs["text"] ?? xmlUrl
		outlines.append(OPMLOutline(title: title, xmlUrl: xmlUrl))
	}

	func parser(_: XMLParser, parseErrorOccurred error: Error) {
		parseError = error
	}

	// MARK: - Export

	/// Generate OPML 2.0 XML data from an array of sources. Only `.rss` sources are exported.
	static func generate(sources: [NewsSource]) -> Data {
		var xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
		xml += "<opml version=\"2.0\">\n"
		xml += "\t<head>\n"
		xml += "\t\t<title>The Daily Feed Subscriptions</title>\n"
		xml += "\t\t<dateCreated>\(ISO8601DateFormatter().string(from: Date()))</dateCreated>\n"
		xml += "\t</head>\n"
		xml += "\t<body>\n"
		for source in sources where source.type == .rss {
			let name = source.name.opmlEscaped
			let url = source.url.opmlEscaped
			xml += "\t\t<outline text=\"\(name)\" title=\"\(name)\" type=\"rss\" xmlUrl=\"\(url)\"/>\n"
		}
		xml += "\t</body>\n"
		xml += "</opml>\n"
		return Data(xml.utf8)
	}
}

private extension String {
	var opmlEscaped: String {
		self
			.replacingOccurrences(of: "&", with: "&amp;")
			.replacingOccurrences(of: "<", with: "&lt;")
			.replacingOccurrences(of: ">", with: "&gt;")
			.replacingOccurrences(of: "\"", with: "&quot;")
	}
}
