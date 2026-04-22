# The Daily Feed

A macOS news reader with a newspaper-inspired layout. Built with Swift 6 and SwiftUI, targeting macOS 26.

> **Note:** This application was written entirely by [Claude](https://claude.ai) (Anthropic) and has not been reviewed by a human developer. Use at your own discretion.

---

## Features

### Reading
- **Newspaper-style grid** — articles displayed with title, source, author, thumbnail, date, and tags
- **Full article view** — readable content extracted via Mozilla Readability.js, rendered in-app
- **In-article search** — Cmd+F find bar with highlight and navigation within article content
- **Text-to-speech** — read articles aloud using your configured macOS system voice
- **Bookmarks** — save articles for later; bookmarked articles are never pruned
- **Hidden articles** — dismiss articles from the feed with a one-tap undo toast
- **Share / Copy Link** — share articles via the macOS share sheet or copy the URL directly
- **Lazy loading** — prefetches ahead of the scroll position for smooth performance

### Sources & Feeds
- **RSS & website sources** — add feeds by RSS URL or website URL (auto-discovers feed links)
- **OPML import / export** — migrate your subscriptions in and out
- **Source management** — edit, reorder (drag-to-reorder), and color-code sources
- **Per-source unread badges** — unread count displayed per source in the sidebar
- **Auto-refresh** — configurable background refresh interval
- **System notifications** — optional notification when new articles arrive

### Filtering & Search
- **Tag filtering** — auto-tagged from article content (Science, Technology, Politics, and 30+ more)
- **Full-text search** — searches title, author, summary, and cached article body
- **Unread & date range filters** — narrow the feed to what matters now
- **Active filter label** — dynamic description of current filters shown above the grid

### AI (Ollama)
- **Headline rewriting** — rewrite article titles using your local LLM
- **Article Quiz** — comprehension questions (multiple choice, true/false, yes/no) generated per article, with scoring, dispute resolution, and a stats history view
- **Daily Summary** — silently summarises articles as you read them, collected in a Library view
- **Suggested Sources** — Ollama recommends reputable feeds based on what you already follow

### Privacy & Storage
- **Local SQLite storage** — all articles, sources, tags, and quiz scores stored on-device via GRDB
- **Article retention** — configurable retention window (7 / 30 / 60 / 90 days); bookmarked articles exempt
- **Keychain storage** — API keys stored in the macOS Keychain, never in UserDefaults
- **iCloud settings sync** — app settings sync across Macs via iCloud key-value store
- **No telemetry** — no analytics, crash reporting, or remote logging of any kind

### Other
- **Dark mode** — full support via semantic SwiftUI colors
- **Weather widget** — current conditions in the header (requires a free OpenWeatherMap API key)
- **Right-click context menus** — mark read/unread, hide, bookmark, and share per article

---

## Requirements

- macOS 26+
- [Ollama](https://ollama.com) running locally for AI features (default: `http://localhost:11434`, model: `gemma4:e4b`)
- OpenWeatherMap API key for the weather widget (free tier at [openweathermap.org](https://openweathermap.org))

---

## Third-Party Libraries

| Library | Purpose |
|---|---|
| [GRDB.swift](https://github.com/groue/GRDB.swift) | SQLite database access and persistence |
| [FeedKit](https://github.com/nmdias/FeedKit) | RSS / Atom feed parsing |
| [Mozilla Readability.js](https://github.com/mozilla/readability) | Article content extraction, bundled and run via WKWebView |

---

## Building

```bash
swift build
```

Or run `build_app.sh` to produce a self-contained `.app` bundle.
