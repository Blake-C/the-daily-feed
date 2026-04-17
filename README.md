# The Daily Feed

A macOS news reader with a newspaper-inspired layout. Built with Swift 6 and SwiftUI, targeting macOS 26.

> **Note:** This application was written entirely by [Claude](https://claude.ai) (Anthropic) and has not been reviewed by a human developer. Use at your own discretion.

---

## Features

- **Newspaper-style grid** — articles displayed with title, source, author, thumbnail, date, and tags
- **RSS & website sources** — add feeds by RSS URL or website URL (auto-discovers feed)
- **OPML import / export** — migrate your subscriptions in and out
- **Full article view** — readable content extracted via Mozilla Readability.js, rendered in-app
- **AI integration (Ollama)** — rewrite headlines, generate article summaries, and produce comprehension quizzes per article
- **Daily Summary** — silently summarises articles as you read them, collected in a dedicated Library view
- **Suggested Sources** — Ollama recommends reputable feeds based on what you already follow
- **Article Quiz** — comprehension questions generated per article, with scoring and dispute resolution
- **Tag filtering** — built-in and custom tags (Science, Technology, Politics, etc.) to filter the feed
- **Search** — full-text search across all cached articles
- **Unread filter & date range filter** — narrow the feed to what matters now
- **Source colour coding** — assign a custom accent colour per news source
- **Dark mode** — full support via semantic SwiftUI colours
- **Weather widget** — current conditions in the header (requires a free OpenWeatherMap API key)
- **Lazy loading** — prefetches ahead of the scroll position for smooth performance
- **Local SQLite storage** — all articles, sources, tags, and quiz scores stored on-device via GRDB
- **Keychain storage** — sensitive credentials (API keys) stored in the macOS Keychain

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
