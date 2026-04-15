import Foundation
import Security

/// A minimal wrapper around the macOS Keychain for storing sensitive string values
/// (e.g. API keys) as generic password items scoped to this application.
final class KeychainService: @unchecked Sendable {
	static let shared = KeychainService()

	private let service: String = Bundle.main.bundleIdentifier ?? "com.newsapp.dailyfeed"

	private init() {}

	// MARK: - Public API

	func set(_ value: String, for key: String) {
		let data = Data(value.utf8)
		let query = baseQuery(for: key)

		// Attempt an update first; if the item doesn't exist yet, add it.
		let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
		if status == errSecItemNotFound {
			var addQuery = query
			addQuery[kSecValueData as String] = data
			SecItemAdd(addQuery as CFDictionary, nil)
		}
	}

	func get(_ key: String) -> String {
		var query = baseQuery(for: key)
		query[kSecReturnData as String] = true
		query[kSecMatchLimit as String] = kSecMatchLimitOne

		var result: AnyObject?
		let status = SecItemCopyMatching(query as CFDictionary, &result)
		guard status == errSecSuccess, let data = result as? Data else { return "" }
		return String(data: data, encoding: .utf8) ?? ""
	}

	func delete(_ key: String) {
		SecItemDelete(baseQuery(for: key) as CFDictionary)
	}

	// MARK: - Private

	private func baseQuery(for key: String) -> [String: Any] {
		[
			kSecClass as String: kSecClassGenericPassword,
			kSecAttrService as String: service,
			kSecAttrAccount as String: key,
		]
	}
}
