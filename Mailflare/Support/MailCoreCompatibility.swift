import MailflareCore

/// Adapts app conveniences to the public API in the checked-out mailflare-core package.
/// Keep the app usable with the package's current API while those conveniences remain absent upstream.
extension MailCore {
	/// This core version has no client controlled offline retention setting.
	func setOfflineDepth(depth: UInt32) {
		// The package caches mail as it syncs and pages older messages on demand.
	}

	/// Push registration requires an APNs token and topic, which this macOS app does not currently obtain.
	func startPush(accountId: String) -> Bool { false }

	/// Loads older pages until all server reported unread mail is available locally, or the folder ends.
	func fetchUnread(accountId: String, folder: Folder) async throws -> UInt32 {
		let unreadBefore = try cachedUnreadCount(accountId: accountId, folder: folder)
		let serverUnread = try unreadCount(accountId: accountId, folder: folder)
		var localUnread = unreadBefore
		while localUnread < serverUnread {
			let fetched = try await fetchOlder(accountId: accountId, folder: folder)
			guard fetched > 0 else { break }
			let updated = try cachedUnreadCount(accountId: accountId, folder: folder)
			guard updated > localUnread else { break }
			localUnread = updated
		}
		return localUnread - unreadBefore
	}

	/// Returns unread messages already held locally, paging the cache in bounded chunks.
	func unreadMessages(accountId: String, folder: Folder, limit: UInt32) throws -> [MessageSummary] {
		let pageSize: UInt32 = 500
		var offset: UInt32 = 0
		var unread: [MessageSummary] = []
		while unread.count < Int(limit) {
			let page = try messages(accountId: accountId, folder: folder, offset: offset, limit: pageSize)
			guard !page.isEmpty else { break }
			unread.append(contentsOf: page.filter { !$0.seen })
			offset += UInt32(page.count)
			if page.count < Int(pageSize) { break }
		}
		return Array(unread.prefix(Int(limit)))
	}

	/// Fetching a message body stores it in the core cache, so this provides the same warm-up behavior.
	func prefetchBodies(accountId: String, messageIds: [String]) async throws {
		for messageId in messageIds {
			_ = try await loadMessage(accountId: accountId, messageId: messageId)
		}
	}

	private func cachedUnreadCount(accountId: String, folder: Folder) throws -> UInt32 {
		let pageSize: UInt32 = 500
		var offset: UInt32 = 0
		var unread: UInt32 = 0
		while true {
			let page = try messages(accountId: accountId, folder: folder, offset: offset, limit: pageSize)
			unread += UInt32(page.filter { !$0.seen }.count)
			guard page.count == Int(pageSize) else { break }
			offset += pageSize
		}
		return unread
	}
}
