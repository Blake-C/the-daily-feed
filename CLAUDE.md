# CLAUDE.md — The Daily Feed

A macOS 26 newspaper-style news reader built entirely with Swift 6 and SwiftUI, using Swift Package Manager. AI features run through a user-selected provider — a local Ollama instance (default), or the Anthropic or OpenAI APIs. No server-side components of our own.

---

## Project Scope & Goals

- Ingest RSS/Atom/JSON feeds and website URLs (with feed autodiscovery)
- Display articles in a responsive newspaper-style grid (title, source, author, thumbnail, date, tags)
- Full article reading via Mozilla Readability.js, cached locally
- Local LLM integration (Ollama) for headline rewriting, daily summaries, feed suggestions, and comprehension quizzes
- Weather widget in newspaper header via OpenWeatherMap (optional; hidden if no API key)
- All data stored locally in SQLite; API keys in macOS Keychain
- No external telemetry, no server-side code, no cloud dependency

**Target platform:** macOS 26+  
**Language:** Swift 6, strict concurrency  
**UI framework:** SwiftUI with `@Observable` macro (not Combine, not `@ObservableObject`)  
**Build system:** Swift Package Manager (no Xcode project file, no CocoaPods)

---

## Architecture

**Pattern:** MVVM with a Service + Repository data layer.

```
Sources/NewsApp/
├── App/               # Entry point, AppState (@Observable settings), SourceColorStore
├── Models/            # Article, NewsSource, QuizQuestion, SuggestedSource, WeatherData
├── Database/          # DatabaseManager (GRDB), ArticleRepository, SourceRepository, QuizRepository
├── Services/          # All external integrations (RSS, Ollama, Readability, Weather, etc.)
├── ViewModels/        # @Observable state per feature area
├── Views/             # SwiftUI components
└── Resources/         # Readability.js, DefaultSources.json, Assets.xcassets
```

### Key patterns

| Pattern | Where used |
|---|---|
| Repository | `ArticleRepository`, `SourceRepository`, `QuizRepository` — abstract all SQL |
| Service singletons | `RSSService`, `AIService`, `ReadabilityService`, `WeatherService`, etc. |
| Swift actors | `DailySummaryService`, `SuggestedSourcesService` — background-only work |
| `@Observable` | All ViewModels and `AppState` — no Combine, no `@StateObject`/`@ObservedObject` |
| `async/await` | All network and DB calls — no GCD, no DispatchQueue manual management |
| `@MainActor` | All ViewModels annotated; UI mutations are main-thread only |

---

## Database

**Engine:** GRDB.swift 7.10.0 (SQLite)  
**Location:** `~/Library/Application Support/The Daily Feed/news.sqlite`  
**Permissions:** 0o600 (owner read/write only)  
**Backup:** excluded from iCloud and Time Machine (`.isExcludedFromBackup = true`)  
**Encryption:** none — public content + system FDE justification documented in `DatabaseManager.swift`

### Schema migrations (v1–v6)

| Version | Change |
|---|---|
| v1 | `news_sources`, `articles` tables |
| v2 | `isHidden`, `sortOrder`, `lastError` columns |
| v3 | FTS5 virtual table (title, author, summary, body) |
| v4 | `isBookmarked`, `badgeClearedAt` |
| v5 | `dailySummary` per article |
| v6 | `quiz_results` table |

**When adding a new column or table, always add a new numbered migration in `DatabaseManager.swift`. Never modify existing migrations.**

### Key query notes

- `ArticleRepository.fetch()` uses LIMIT/OFFSET pagination (40 items/page)
- `readableContent` is excluded from grid queries — fetched on demand in detail view only
- FTS5 table tokens: `unicode61 remove_diacritics 2`
- Bookmarked articles are exempt from all retention/pruning logic

---

## External Dependencies

| Package | Version | Purpose |
|---|---|---|
| GRDB.swift | 7.10.0 | SQLite access, migrations, FTS5 |
| FeedKit | 9.1.2 | RSS 2.0 / Atom 1.0 / JSON Feed parsing |
| Readability.js | Mozilla (bundled) | Article extraction via WKWebView |

No other package manager. No CocoaPods. No SPM plugins.

---

## Services Reference

### RSSService
- Parses feeds via FeedKit; maps items to `Article` models
- Extracts title, author, summary, image, categories

### FeedDiscoveryService
- Given a website URL, parses HTML for `<link rel="alternate">` feed links
- Falls back to direct FeedKit parse (handles URLs that look like HTML but are feeds)
- Validates discovered URLs via FeedKit before returning

### FeedRefreshService
- Coordinates parallel refresh of all enabled sources
- **Concurrency cap: 6 simultaneous feed fetches** (prevents network saturation)
- Prunes articles older than retention window before each refresh
- Persists `lastError` and last-fetch timestamp per source

### ReadabilityService
- **Per-call WKWebView** — each extraction gets an isolated instance (no shared state hazard)
- Fetches HTML via URLSession (off main actor), injects Readability.js + restrictive CSP
- CSP blocks all scripts, inline handlers, and external loads except images
- Caches result in `articles.readableContent` — second open returns cached content, no WKWebView

### AIService
- Unified service for all AI features (rewrite, daily summary, quiz, dispute, suggested sources).
- **Multi-provider** — the active provider is chosen in Settings (`aiProvider`); the default is Ollama. Each public method takes an `AIProviderConfig` (a `Sendable` snapshot from `AppState.aiConfig`) instead of raw endpoint/model. Prompt-building and JSON parsing are provider-agnostic; only the private `generate(...)` dispatch differs per provider:
  - `generateOllama` — `POST {endpoint}/api/generate`, `format: "json"`. Keeps the localhost / HTTPS guard (remote endpoints must use HTTPS).
  - `generateAnthropic` — `POST https://api.anthropic.com/v1/messages`, headers `x-api-key` + `anthropic-version: 2023-06-01`, `max_tokens: 2048`. Throws `NewsError.missingAPIKey` if no key; checks `stop_reason != "refusal"`; reads `content[0].text`.
  - `generateOpenAI` — `POST https://api.openai.com/v1/chat/completions`, `Authorization: Bearer`, `response_format: {type: "json_object"}`. Reads `choices[0].message.content`.
- `AIProvider` / `AIProviderConfig` and the curated model lists live in `AIProvider.swift`.
- **Prompt injection hardening (unchanged across providers):**
  - Title truncated to 200 chars, content to 4000 chars before substitution
  - Content paragraphs numbered `[1] text\n[2] text…` to prevent injection via article body
  - All responses expected as strict JSON; no `.unsafe` decoding
- Quiz generation: 90s timeout, 2 automatic retries before user-facing error
- Previous quiz question paragraph indices passed as context to avoid duplicate questions

### WeatherService
- OpenWeatherMap free tier; key stored in Keychain (not UserDefaults)
- Uses `CLLocationManager` for coordinates
- Header hidden entirely if no API key is set

### KeychainService
- Wraps SecItem APIs for storing/reading/deleting sensitive values
- Used for the OpenWeatherMap, Anthropic, and OpenAI API keys (keys: `openWeatherApiKey`, `anthropicApiKey`, `openAIApiKey`)

### ArticleTaggingService
- Two-layer auto-tagging: feed-native categories + keyword matching
- Keyword map: 30+ tags with 1000+ keywords (AI, Automotive, Business, Climate, Culture, etc.)
- No manual per-source tags — all tags come from article content
- Tags stored comma-separated in `articles.tags`

### OPMLService
- Import: parses OPML XML, maps `<outline>` entries to `NewsSource`, skips duplicates
- Export: generates valid OPML 2.0 from all sources in `SourceRepository`

### DailySummaryService (actor)
- Silently summarizes articles as the user reads them (best-effort; fails silently)
- Disabled by default; toggled in Settings (`dailySummaryEnabled`)

### SuggestedSourcesService (actor)
- Asks the active AI provider for reputable feed suggestions based on existing sources
- Validates each suggestion via `FeedDiscoveryService` before surfacing
- Disabled by default; toggled in Settings (`suggestedSourcesEnabled`)

---

## Settings & Persistence

### AppState.swift
All app-wide settings are `@AppStorage` with iCloud KV store sync fallback:

| Key | Default | Description |
|---|---|---|
| `aiProvider` | `ollama` | Active AI provider: `ollama` \| `anthropic` \| `openAI` |
| `ollamaEndpoint` | `http://localhost:11434` | Ollama server URL |
| `ollamaModel` | `gemma4:e4b` | Ollama model name |
| `anthropicModel` | `""` | Claude model id (empty = `claude-haiku-4-5`) |
| `openAIModel` | `""` | OpenAI model id (empty = `gpt-4o-mini`) |
| `ollamaPrompt` | `""` | Custom AI Summary prompt template (empty = use built-in; applies to all providers) |
| `aiSummaryEnabled` | `true` | Headline rewrite + summary toggle |
| `dailySummaryEnabled` | `false` | Daily briefing toggle |
| `suggestedSourcesEnabled` | `false` | Feed recommendations toggle |
| `quizEnabled` | `false` | Comprehension quiz toggle |
| `autoRefreshInterval` | `0` | Minutes between refreshes (0 = off) |
| `articleRetentionDays` | `30` | Days to keep articles (bookmarked = forever) |
| `articleFontSize` | `17` | Detail view font size (points) |
| `useCelsius` | `false` | Temperature unit |

**Persistence hierarchy:**
1. iCloud KV store (`NSUbiquitousKeyValueStore`) — syncs across Macs
2. Fallback to UserDefaults — if iCloud disabled
3. Keychain (`KeychainService`) — API keys only
4. UserDefaults — quiz question cache (`quiz_q_{articleId}`), source colors (`source_color_{id}`)

---

## ViewModels

| ViewModel | Manages |
|---|---|
| `AppState` | App-wide settings, iCloud sync |
| `ArticlesViewModel` | Grid articles, filters (tag, date, source, read, bookmarks, hidden), pagination, search, pending new-article buffering |
| `ArticleDetailViewModel` | Content loading, quiz generation & dispute |
| `SourcesViewModel` | Source list, add/edit/delete/reorder, OPML, unread counts, fetch spinners |
| `DailySummaryViewModel` | Daily briefing articles + total summary |
| `SuggestedSourcesViewModel` | Ollama feed recommendations |
| `QuizStatsViewModel` | Quiz performance history (today/week/all-time) |
| `SourceColorStore` | Per-source accent colors (UserDefaults-backed, `@Observable`) |

---

## UI Layout

- **Main layout:** `NavigationSplitView` — sidebar (sources + filter sections) / content (article grid) / detail sheet
- **Article grid:** Responsive multi-column (`LazyVGrid` with adaptive columns, newspaper layout)
- **Article detail:** Modal sheet (full window width on macOS 26)
- **Newspaper header:** Date + weather widget (`NewspaperHeaderView`); shows an "Updating feeds…" spinner while a refresh is in flight
- **Refresh indicators:** Global header spinner + per-source sidebar spinners (`SourcesViewModel.fetchingSourceIds`, driven by a `FeedRefreshService.refreshAll` progress callback)
- **Tag filters:** Horizontal chip bar — single-select, auto-hidden if no articles for that tag
- **Skeleton loading:** Placeholder cards shown during pagination; count matches visible rows
- **Pagination:** 40 items/page; prefetch triggers at 20-item threshold from end
- **New-article pill:** Refreshing while scrolled down does not push the list — new articles are held aside and surfaced as a "N new articles" pill; tapping it loads them and scrolls to top. When the user is already at the top they merge silently

---

## Build & Deploy

```bash
# Debug build
swift build

# Release build
swift build --configuration release

# Produce self-contained .app bundle
./build_app.sh
./build_app.sh release

# Launch
open TheDailyFeed.app
```

**Bundle ID:** `com.newsapp.dailyfeed`  
**App name:** The Daily Feed  
**Minimum OS:** macOS 15.0 (runs on macOS 26)  
**ATS:** arbitrary loads disabled; localhost networking explicitly allowed for Ollama

---

## Security Requirements

These are non-negotiable and must be maintained in all new code:

1. **API keys in Keychain** — never store sensitive values in UserDefaults, plist, or code
2. **CSP on injected HTML** — `ReadabilityService` must keep restrictive CSP; do not relax it
3. **Prompt injection hardening (all providers)** — always truncate user-derived content before LLM substitution; always use numbered paragraphs; always parse LLM output as strict JSON. This logic is shared in `AIService` and must stay provider-agnostic.
4. **Link security** — all anchor links in rendered article HTML must carry `title` attributes with the href URL (for hover-preview before clicking)
5. **No XSS** — do not render unsanitized HTML outside of the Readability-extracted + CSP-wrapped WKWebView
6. **Off-device content warnings** — surface a warning when AI traffic leaves the device: a non-localhost Ollama endpoint, or the Anthropic / OpenAI providers (which always send article content off-device). Cloud API keys are HTTPS-only and stored in Keychain.
7. **No external telemetry** — do not add analytics, crash reporting, or remote logging without explicit user opt-in

After writing new Swift code, run `mcp__Snyk__snyk_code_scan` and fix any findings before marking work complete.

---

## Accessibility Requirements

- All interactive controls must have `.accessibilityLabel` descriptions
- Color is never the sole indicator of state (use shape, text, or icon alongside)
- Article text size is configurable (`articleFontSize` in Settings)
- Text-to-speech support is already implemented; do not break it

---

## Code Style

- **Language:** Swift 6 strict concurrency — all `@MainActor` and actor annotations must be present
- **UI:** SwiftUI only — no AppKit views unless strictly necessary (e.g., `NSApp` calls)
- **State:** `@Observable` only — do not use `@ObservableObject`, `@StateObject`, `@ObservedObject`, or Combine publishers in new code
- **Async:** `async/await` only — no `DispatchQueue` or `OperationQueue` in new code
- **Tabs:** tabs over spaces (per global CLAUDE.md)
- **Comments:** only when the WHY is non-obvious — no explanatory comments for self-evident code
- **No star ratings** — the star rating system was removed; do not reintroduce it

---

## Open Items (as of 2026-04-17)

The only known incomplete feature is **keyboard navigation**:

- J/K to move between articles
- Enter/Space to open article detail
- M to mark read
- O to open in browser

All other items in `TODO.todo` are marked done or cancelled.

---

## Notes

- This application was written entirely by Claude (Anthropic) and has not been reviewed by a human developer.
- `project.md` at root is the original product brief — reference it for original intent vs. evolved requirements.
- `TODO.todo` uses a custom todo format (✔ done, ✘ cancelled, ☐ open) — update it when completing features.
- `README.md` is user-facing; `CHANGELOG.md` does not yet exist — create one when shipping a public release.
