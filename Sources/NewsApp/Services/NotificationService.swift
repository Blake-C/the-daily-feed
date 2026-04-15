import Foundation
import UserNotifications
import AppKit

/// Manages user-visible notifications for background article fetches.
///
/// Notifications are opt-in: the first time a background refresh delivers
/// new articles, the system permission dialog is shown. Subsequent calls
/// post notifications only when permission has been granted.
///
/// Notifications are suppressed when the app is in the foreground so the
/// user is not interrupted while actively reading.
@MainActor
final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
	static let shared = NotificationService()

	private override init() {
		super.init()
		UNUserNotificationCenter.current().delegate = self
	}

	// MARK: - Public API

	/// Posts a "N new articles" notification if permission allows.
	/// Requests permission first if the user has not yet been asked.
	/// Silently does nothing when the app is in the foreground.
	func notifyNewArticles(count: Int) async {
		guard count > 0 else { return }
		// Don't interrupt the user while they're actively using the app.
		guard !NSApp.isActive else { return }

		let center = UNUserNotificationCenter.current()
		let settings = await center.notificationSettings()

		switch settings.authorizationStatus {
		case .notDetermined:
			// Ask permission; if granted, post immediately.
			guard (try? await center.requestAuthorization(options: [.alert, .badge])) == true else { return }
		case .authorized, .provisional:
			break
		default:
			return
		}

		let content = UNMutableNotificationContent()
		content.title = "The Daily Feed"
		content.body = count == 1
			? "1 new article is available."
			: "\(count) new articles are available."
		content.sound = .none

		// Use a stable identifier so rapid back-to-back refreshes coalesce into
		// one notification rather than stacking.
		let request = UNNotificationRequest(
			identifier: "com.newsapp.dailyfeed.new-articles",
			content: content,
			trigger: nil
		)
		try? await center.add(request)
	}

	// MARK: - UNUserNotificationCenterDelegate

	/// Suppress notifications when the app comes to the foreground while one is
	/// pending delivery — avoids a banner appearing over the article the user
	/// just opened in response to the notification.
	nonisolated func userNotificationCenter(
		_ center: UNUserNotificationCenter,
		willPresent notification: UNNotification,
		withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
	) {
		completionHandler([])
	}
}
