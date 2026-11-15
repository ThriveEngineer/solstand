import Foundation
import Observation

/// Names and notes assigned to senders, stored locally on this Mac. Local avatars are managed by
/// `AvatarCache`, and clearing a name restores the sender's original address-book display name.
@MainActor
@Observable
final class ContactProfiles {
	struct Entry: Codable, Equatable {
		var name: String?
		var note: String?
		var isEmpty: Bool { (name ?? "").isEmpty && (note ?? "").isEmpty }
	}

	private var entries: [String: Entry]
	private static let defaultsKey = "contactProfiles"

	init() {
		if let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
		   let saved = try? JSONDecoder().decode([String: Entry].self, from: data) { entries = saved } else { entries = [:] }
	}

	private static func key(_ email: String) -> String { email.trimmingCharacters(in: .whitespaces).lowercased() }

	/// The name set on this Mac for `email`, if any.
	func name(for email: String) -> String? {
		guard let name = entries[Self.key(email)]?.name?.trimmingCharacters(in: .whitespaces), !name.isEmpty else { return nil }
		return name
	}

	func note(for email: String) -> String { entries[Self.key(email)]?.note ?? "" }

	/// Saves both fields; empty ones are removed, and a contact with neither is forgotten.
	func save(email: String, name: String, note: String) {
		let key = Self.key(email)
		guard !key.isEmpty else { return }
		let entry = Entry(
			name: name.trimmingCharacters(in: .whitespacesAndNewlines),
			note: note.trimmingCharacters(in: .whitespacesAndNewlines))
		if entry.isEmpty { entries[key] = nil } else { entries[key] = entry }
		if let data = try? JSONEncoder().encode(entries) { UserDefaults.standard.set(data, forKey: Self.defaultsKey) }
	}
}
