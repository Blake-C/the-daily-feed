# Changelog

All notable changes to The Daily Feed are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added
- Choice of AI provider in Settings: on-device Ollama (default), Anthropic (Claude), or OpenAI. The selected provider handles every AI feature (headline rewrite, daily summary, quiz, dispute, suggested sources).
- Per-provider model pickers with curated options (Claude: Haiku 4.5 / Sonnet 4.6 / Opus 4.8; OpenAI: gpt-4o-mini / gpt-4o / gpt-4.1-mini / gpt-4.1) plus a "Custom…" free-text option.
- Anthropic and OpenAI API keys, stored in the macOS Keychain.

### Changed
- Settings AI tab now shows only the active provider's connection fields, and warns when article content will be sent off-device (cloud providers, or a non-localhost Ollama endpoint).
- `OllamaService` renamed to `AIService`; AI calls now take an `AIProviderConfig` snapshot instead of a raw endpoint/model pair. Prompt-injection hardening and strict-JSON parsing are unchanged and shared across all providers.
