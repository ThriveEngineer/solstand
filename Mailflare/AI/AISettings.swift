import Foundation
import Observation
import Security

/// Preferences shared by the on-device assistant, summaries and reply writer.
@MainActor
@Observable
final class AISettings {
	private enum Keys {
		static let instructions = "ai.instructions"
		static let writerInstructions = "ai.writerInstructions"
	}

	var instructions: String {
		didSet { UserDefaults.standard.set(instructions, forKey: Keys.instructions) }
	}
	var writerInstructions: String {
		didSet { UserDefaults.standard.set(writerInstructions, forKey: Keys.writerInstructions) }
	}

	init() {
		instructions = UserDefaults.standard.string(forKey: Keys.instructions) ?? ""
		writerInstructions = UserDefaults.standard.string(forKey: Keys.writerInstructions) ?? ""
	}

	var isConfigured: Bool { AIClient.isAvailable }
	var availabilityDescription: String { AIClient.availabilityDescription }
	var client: AIClient? { isConfigured ? AIClient() : nil }
	var writerClient: AIClient? { client }
}

/// Credentials for user-configured MCP services, stored separately from mail account secrets.
enum AIKeychain {
	private static let service = "com.solstand.mail.ai"

	private static func query(_ account: String) -> [String: Any] {
		[kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
	}

	static func load(_ account: String) -> String? {
		var request = query(account)
		request[kSecReturnData as String] = true
		request[kSecMatchLimit as String] = kSecMatchLimitOne
		var item: CFTypeRef?
		guard SecItemCopyMatching(request as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
		return String(data: data, encoding: .utf8)
	}

	static func save(_ account: String, _ secret: String) -> Bool {
		let data = Data(secret.utf8)
		let status = SecItemUpdate(query(account) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
		if status == errSecSuccess { return true }
		guard status == errSecItemNotFound else { return false }
		var insert = query(account)
		insert[kSecValueData as String] = data
		insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
		return SecItemAdd(insert as CFDictionary, nil) == errSecSuccess
	}

	static func delete(_ account: String) { SecItemDelete(query(account) as CFDictionary) }
}
