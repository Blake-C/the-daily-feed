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
- **Non-disruptive refresh** — refreshing while scrolled down keeps your place; new articles appear as a tap-to-load "N new articles" pill instead of jumping the list

### Sources & Feeds
- **RSS & website sources** — add feeds by RSS URL or website URL (auto-discovers feed links)
- **OPML import / export** — migrate your subscriptions in and out
- **Source management** — edit, reorder (drag-to-reorder), and color-code sources
- **Per-source unread badges** — unread count displayed per source in the sidebar
- **Auto-refresh** — configurable background refresh interval
- **Refresh indicators** — an "Updating feeds…" indicator in the header and a per-source spinner in the sidebar show exactly what is being fetched
- **System notifications** — optional notification when new articles arrive

### Filtering & Search
- **Tag filtering** — auto-tagged from article content (Science, Technology, Politics, and 30+ more)
- **Full-text search** — searches title, author, summary, and cached article body
- **Unread & date range filters** — narrow the feed to what matters now
- **Active filter label** — dynamic description of current filters shown above the grid

### AI
- **Choice of provider** — run AI features on a local [Ollama](https://ollama.com) instance (default), or on Anthropic (Claude) or OpenAI models with your own API key. Selectable in Settings; the chosen provider handles every AI task
- **Headline rewriting** — rewrite article titles into clear, factual headlines
- **Article Quiz** — comprehension questions (multiple choice, true/false, yes/no) generated per article, with scoring, dispute resolution, and a stats history view
- **Daily Summary** — silently summarises articles as you read them, collected in a Library view
- **Suggested Sources** — recommends reputable feeds based on what you already follow

### Privacy & Storage
- **Local SQLite storage** — all articles, sources, tags, and quiz scores stored on-device via GRDB
- **Article retention** — configurable retention window (7 / 30 / 60 / 90 days); bookmarked articles exempt
- **Keychain storage** — all API keys (weather, Anthropic, OpenAI) stored in the macOS Keychain, never in UserDefaults
- **On-device by default** — Ollama keeps article content local; choosing Anthropic or OpenAI sends article content to that provider (clearly noted in Settings)
- **iCloud settings sync** — app settings sync across Macs via iCloud key-value store
- **No telemetry** — no analytics, crash reporting, or remote logging of any kind

### Other
- **Dark mode** — full support via semantic SwiftUI colors
- **Weather widget** — current conditions in the header (requires a free OpenWeatherMap API key)
- **Right-click context menus** — mark read/unread, hide, bookmark, and share per article

---

## Requirements

- macOS 26+
- For on-device AI: [Ollama](https://ollama.com) running locally (default: `http://localhost:11434`, model: `gemma4:e4b`). Alternatively, an Anthropic or OpenAI API key for cloud AI
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
