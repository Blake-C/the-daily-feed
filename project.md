A News feed application that will take in the RSS feed or website URL and scarp the news articles based on certain criteria. Show todays date and weather at the top of the application once. The layout should be based on what you would see on a newspaper.

This should be a desktop application using Swift.

The data should be stored local server with a DB.

Mozilla Readability to extract article content.

Ollama endpoint? Default http://localhost:11434, but should be configurable.

Ollama endpoint modal should use gemma4:e4b by default but should also be configurable.

Pick a good cross-topic list of news articles.

Mewspaper aesthetic — a more modern take with color, Dark mode support.

---

Target macOS 26

Swift Package Manager

OpenWeatherMap (requires free API key), if no API is added to application settings don't display weather.

SQLite via GRDB the standard approach.

For Mozilla Readability in Swift, the cleanest approach is to bundle Readability.js and run it via WKWebView or JavaScriptCore. Any objection to that approach? No objections.

---

- Pull in news articles in a grid
- Grid of articles shows title, source, author, thumbnail, date, tags.
- Articles can come from RSS
- Articles can come from Website URL
- Ability to add new news sources via RSS or website URL.
- Button to star an article out of 5 stars. Scores stores locally.
- Connection to local LLM OLLAM server for summarizing articles and rewriting titles.
- Button per article to read the article and give a more reasonable title based on the story.
- Tags to pull in articles based on a specific topic. Add a large list of typical filtering topics. (science, technology, politics, USA, Europe, etc.)
- Ability to add new tags for filtering news articles from the web.
- Ability to rate news sources. This wont be the article but the source from where the article came from.
- Clicking the article will pull the articles contents into the application as a rendered markdown format.
- Search field to find a specific articles.
- Lazy load more articles as the user scrolls down the view.
- As article are lazy loaded the application should stay ahead and render more than what is in view so that the application doesn't have to wait as much.
- Performance and speed should be a priority.
- Security is a must, the application must not load in anything that breaks system security.
- By default choose a list of the most common news sources for a variety of topics.
