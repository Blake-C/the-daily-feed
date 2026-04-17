import Foundation

/// Assigns topic tags to an article using two layered strategies:
/// 1. Feed-native categories — RSS `<category>`, Atom `<category term>`, JSON Feed `tags[]`
/// 2. Keyword matching — title + summary scanned against a curated keyword dictionary
///
/// Source-level tags (manually set on the source) are merged in as seeds so manual
/// overrides continue to work alongside auto-detected tags.
final class ArticleTaggingService: @unchecked Sendable {
	static let shared = ArticleTaggingService()
	private init() {}

	// MARK: - Public API

	/// Returns a comma-separated tag string for an article.
	/// - Parameters:
	///   - title: Article title
	///   - summary: Article description / summary from the feed
	///   - feedCategories: Raw category strings from the feed item
	func tags(
		title: String,
		summary: String?,
		feedCategories: [String]
	) -> String {
		var matched = Set<String>()

		// Layer 1 — normalise feed-native categories against the known vocabulary.
		for raw in feedCategories {
			if let tag = normalise(raw) {
				matched.insert(tag)
			}
		}

		// Layer 2 — keyword scan of title + summary.
		let corpus = "\(title) \(summary ?? "")".lowercased()
		for (tag, keywords) in Self.keywordMap {
			for kw in keywords where corpus.range(of: kw, options: .caseInsensitive) != nil {
				matched.insert(tag)
				break
			}
		}

		return matched.sorted().joined(separator: ",")
	}

	// MARK: - Feed category normalisation

	private func normalise(_ raw: String) -> String? {
		let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !cleaned.isEmpty else { return nil }
		let lower = cleaned.lowercased()

		// Direct match against known tag names.
		for tag in Self.knownTags where tag.lowercased() == lower {
			return tag
		}
		// Keyword match the category string itself.
		for (tag, keywords) in Self.keywordMap where keywords.contains(lower) {
			return tag
		}
		// Partial prefix match — handles things like "U.S. Politics" → "Politics".
		for tag in Self.knownTags where lower.contains(tag.lowercased()) {
			return tag
		}
		return nil
	}

	private static let knownTags: [String] = Array(keywordMap.keys).sorted()

	// MARK: - Keyword dictionary

	// Each entry maps a canonical tag name to a list of lowercase keywords/phrases.
	// Longer and more specific phrases are listed first so they take priority when
	// scanning a corpus — the loop breaks on the first match per tag.
	private static let keywordMap: [String: [String]] = [
		"AI": [
			"artificial intelligence", "machine learning", "deep learning",
			"neural network", "large language model", "llm", "generative ai",
			"chatgpt", "openai", "gemini", "claude ai", "copilot ai",
			"natural language processing", "nlp", "computer vision",
		],
		"Automotive": [
			"electric vehicle", "self-driving", "autonomous vehicle",
			"automotive", "car recall", "electric car", "tesla", "ev charging",
			"carmaker", "auto industry",
		],
		"Business": [
			"merger", "acquisition", "startup", "entrepreneur", "venture capital",
			"private equity", "ipo", "ceo", "chief executive", "corporate",
			"company earnings", "layoffs", "workforce reduction",
		],
		"Climate": [
			"climate change", "global warming", "greenhouse gas", "carbon emissions",
			"net zero", "paris agreement", "ipcc", "fossil fuel", "renewable energy",
			"solar power", "wind energy", "carbon footprint", "deforestation",
		],
		"Culture": [
			"art exhibition", "museum", "literature", "theatre", "theater",
			"ballet", "opera", "fashion week", "cultural heritage",
			"architecture", "sculpture", "poetry",
		],
		"Cybersecurity": [
			"cybersecurity", "data breach", "ransomware", "malware", "phishing",
			"hacker", "zero-day", "vulnerability", "cyber attack", "ddos",
			"identity theft", "password leak",
		],
		"Economy": [
			"inflation", "gdp", "recession", "unemployment rate", "interest rate",
			"federal reserve", "central bank", "trade deficit", "fiscal policy",
			"monetary policy", "tariff", "supply chain",
		],
		"Education": [
			"education", "school district", "university", "college",
			"student loan", "curriculum", "academic", "teacher shortage",
			"tuition", "graduation",
		],
		"Energy": [
			"oil price", "natural gas", "petroleum", "nuclear power",
			"power grid", "electricity", "opec", "lng", "coal",
			"energy crisis", "power plant",
		],
		"Entertainment": [
			"box office", "film festival", "oscar", "grammy", "emmy", "bafta",
			"celebrity", "hollywood", "netflix", "streaming", "album release",
			"concert tour", "blockbuster",
		],
		"Environment": [
			"biodiversity", "wildlife", "conservation", "pollution",
			"endangered species", "ocean plastic", "coral reef",
			"national park", "habitat", "ecosystem",
		],
		"Europe": [
			"european union", "eu ", "nato", "germany", "france", "united kingdom",
			"britain", "italy", "spain", "poland", "ukraine", "brussels",
			"eurozone", "european parliament",
		],
		"Finance": [
			"stock market", "wall street", "nasdaq", "s&p 500", "dow jones",
			"bond yield", "hedge fund", "cryptocurrency", "bitcoin", "ethereum",
			"investment bank", "federal reserve", "earnings report",
		],
		"Food": [
			"restaurant", "chef", "recipe", "cuisine", "food safety",
			"nutrition", "fda food", "organic farming", "food bank",
			"culinary", "beverage", "michelin",
		],
		"Gaming": [
			"video game", "esports", "playstation", "xbox", "nintendo",
			"game developer", "steam games", "game release", "gaming industry",
		],
		"Health": [
			"public health", "covid", "pandemic", "vaccine", "fda approval",
			"clinical trial", "mental health", "cancer", "diabetes",
			"obesity", "hospital", "nhs", "cdc", "who health",
		],
		"History": [
			"archaeological", "ancient", "world war", "cold war",
			"historical discovery", "civil war", "empire", "dynasty",
			"artifact", "excavation",
		],
		"Law": [
			"supreme court", "federal court", "lawsuit", "verdict",
			"indictment", "plea deal", "criminal trial", "attorney general",
			"legislation", "bill signed", "congress passed",
		],
		"Media": [
			"social media", "journalism", "news outlet", "press freedom",
			"disinformation", "misinformation", "broadcasting", "podcast",
			"youtube", "tiktok", "instagram", "twitter",
		],
		"Military": [
			"military", "armed forces", "pentagon", "defense spending",
			"missile strike", "airstrike", "troops deployed", "warfare",
			"navy", "air force", "army", "war crimes",
		],
		"Politics": [
			"election", "congress", "senate", "parliament", "political party",
			"democrat", "republican", "prime minister", "president",
			"campaign", "ballot", "polling", "legislation", "white house",
		],
		"Religion": [
			"pope", "vatican", "church", "mosque", "synagogue", "temple",
			"faith", "clergy", "theology", "pilgrimage", "buddhism",
			"islam", "christianity", "judaism", "hinduism",
		],
		"Science": [
			"research study", "scientific", "physics", "biology", "chemistry",
			"genome", "dna", "quantum", "mathematician", "nature journal",
			"science journal", "discovery", "experiment",
		],
		"Social Justice": [
			"racial inequality", "civil rights", "discrimination", "protest",
			"police brutality", "lgbtq", "gender pay gap", "immigration reform",
			"human rights", "refugee", "asylum seeker",
		],
		"Space": [
			"nasa", "spacex", "rocket launch", "iss", "space station",
			"astronaut", "mars mission", "satellite", "telescope",
			"black hole", "exoplanet", "moon landing",
		],
		"Sports": [
			"nfl", "nba", "mlb", "nhl", "premier league", "champions league",
			"fifa", "olympic", "world cup", "grand slam", "tournament",
			"championship", "match result", "transfer fee",
		],
		"Technology": [
			"apple", "google", "microsoft", "amazon", "meta ", "semiconductor",
			"chip shortage", "smartphone", "iphone", "android", "software update",
			"cloud computing", "5g", "tech company",
		],
		"Travel": [
			"tourism", "airline", "airport", "hotel", "passport",
			"travel advisory", "destination", "visa", "cruise",
		],
		"USA": [
			"united states", " u.s. ", "american", "washington d.c.",
			"biden", "trump", "congress", "supreme court usa",
			"white house", "us economy", "us military",
		],
		"World": [
			"united nations", "global", "international", "geopolitical",
			"foreign policy", "diplomat", "g7", "g20", "imf", "world bank",
		],
	]
}
