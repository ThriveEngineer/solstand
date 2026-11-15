import SwiftUI
import MailflareCore
import UniformTypeIdentifiers

/// The Settings page in the main card, chosen from the sidebar's settings menu.
struct SettingsView: View {
	@Environment(MailStore.self) private var store
	var page: SettingsPage

	var body: some View {
		VStack(spacing: 0) {
			Text(page.title)
				.font(.system(size: 15, weight: .semibold))
				.frame(maxWidth: .infinity, alignment: .leading)
				.padding(.horizontal, 24)
				.frame(height: PaneHeader.height)
			Rectangle().fill(AppTheme.cardStroke).frame(height: 1)
			ScrollView {
				VStack(alignment: .leading, spacing: 22) {
					switch page {
					case .general: GeneralSettings()
					case .notifications: NotificationSettingsPage()
					case .accounts: AccountSettings()
					case .ai: AISettingsPage()
					case .mcp: MCPSettingsPage()
					case .about: AboutSettings()
					}
				}
				.frame(maxWidth: 560, alignment: .leading)
				.padding(24)
				.frame(maxWidth: .infinity, alignment: .top)
			}
		}
		.background(AppTheme.background)
	}
}

// MARK: Building blocks

/// A titled card of rows. Rows are separated with `SettingsDivider`, and each brings its own
/// vertical padding, so a single row and a long list both sit evenly.
/// Set by an open dropdown so its group is drawn above the groups after it.
private struct OpenDropdownKey: PreferenceKey {
	static let defaultValue = false
	static func reduce(value: inout Bool, nextValue: () -> Bool) { value = value || nextValue() }
}

struct SettingsGroup<Content: View>: View {
	var title: String
	var footer: String?
	@ViewBuilder var content: Content
	@State private var hasOpenDropdown = false

	var body: some View {
		VStack(alignment: .leading, spacing: 8) {
			Text(title).font(Typography.meta.weight(.medium)).foregroundStyle(.secondary)
			VStack(alignment: .leading, spacing: 0) { content }
				.frame(maxWidth: .infinity, alignment: .leading)
				.padding(.horizontal, 14)
				.background(AppTheme.composerContextFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
			if let footer {
				Text(footer).font(Typography.meta).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
			}
		}
		.onPreferenceChange(OpenDropdownKey.self) { hasOpenDropdown = $0 }
		.zIndex(hasOpenDropdown ? 10 : 0)
	}
}

struct SettingsDivider: View {
	var body: some View { Rectangle().fill(AppTheme.cardStroke).frame(height: 1) }
}

/// One line of a group: content with the group's row padding.
struct SettingsRow<Content: View>: View {
	@ViewBuilder var content: Content

	var body: some View {
		HStack(spacing: 10) { content }
			.frame(maxWidth: .infinity, alignment: .leading)
			.padding(.vertical, 12)
	}
}

/// The label on the left, the switch on the right.
private struct SettingsToggle: View {
	var title: String
	var detail: String?
	@Binding var isOn: Bool

	var body: some View {
		SettingsRow {
			VStack(alignment: .leading, spacing: 2) {
				Text(title).font(Typography.body)
				if let detail {
					Text(detail).font(Typography.meta).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
				}
			}
			Spacer(minLength: 12)
			Toggle("", isOn: $isOn).labelsHidden().toggleStyle(.switch)
		}
	}
}

/// A choice drawn as its current value and a chevron; opening it drops a card like the account
/// dropdown's, with a check on the chosen row.
struct SettingsPicker<Value: Hashable>: View {
	var title: String
	var options: [(label: String, value: Value)]
	@Binding var selection: Value
	/// For lists fetched on demand: shown instead of the options, as skeleton rows, while they load.
	var isLoading = false
	/// Called each time the dropdown opens, so a list can start loading then.
	var onOpen: (() -> Void)?
	var maxHeight: CGFloat = 280
	/// The label when `selection` is not among the options (yet).
	var fallbackLabel: String?
	@State private var isOpen = false
	@State private var isHovering = false
	@State private var query = ""

	/// The options whose label contains what was typed, all of them when nothing was.
	private var matches: [Int] {
		let q = query.trimmingCharacters(in: .whitespaces).lowercased()
		guard !q.isEmpty else { return Array(options.indices) }
		return options.indices.filter { options[$0].label.lowercased().contains(q) }
	}

	private var selectedIndex: Int? { options.firstIndex { $0.value == selection } }

	private var currentLabel: String { options.first { $0.value == selection }?.label ?? fallbackLabel ?? "" }

	var body: some View {
		SettingsRow {
			Text(title).font(Typography.body)
			Spacer(minLength: 12)
			Button {
				withAnimation(.snappy(duration: 0.2)) { isOpen.toggle() }
				if isOpen { onOpen?() }
			} label: {
				HStack(spacing: 6) {
					Text(currentLabel).font(Typography.body)
					HIcon(.chevronDown, size: 12).foregroundStyle(.secondary)
						.rotationEffect(.degrees(isOpen ? 180 : 0))
				}
				.padding(.horizontal, 8).padding(.vertical, 4)
				.background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(isHovering || isOpen ? AppTheme.rowHighlight : .clear))
				.contentShape(Rectangle())
			}
			.buttonStyle(.plain)
			.onHover { isHovering = $0 }
			.overlay(alignment: .topTrailing) {
				if isOpen { dropdown.offset(y: 32) }
			}
			// A click anywhere else closes it.
			.clickAway(isActive: isOpen) { withAnimation(.snappy(duration: 0.2)) { isOpen = false } }
		}
		.zIndex(isOpen ? 10 : 0)
		.preference(key: OpenDropdownKey.self, value: isOpen)
		.onChange(of: isOpen) { _, _ in query = "" }
	}

	private var dropdown: some View {
		DropdownCard(width: 190) {
			if isLoading {
				DropdownScroll(maxHeight: maxHeight) {
					ForEach(0..<5, id: \.self) { _ in
						SkeletonBar(height: 12).padding(.horizontal, 10).padding(.vertical, 9)
					}
				}
			} else {
				// Worked out once here: asking per row would scan the whole list for every row.
				let shown = matches
				if options.count > 8 {
					DropdownSearchField(text: $query) {
						if let first = shown.first { selection = options[first].value; withAnimation(.snappy(duration: 0.2)) { isOpen = false } }
					}
				}
				DropdownScroll(maxHeight: maxHeight, target: query.isEmpty ? selectedIndex.map(String.init) : nil) {
					if shown.isEmpty { DropdownNoResults() }
					ForEach(shown, id: \.self) { index in
						DropdownRow(label: options[index].label, isSelected: options[index].value == selection) {
							selection = options[index].value
							withAnimation(.snappy(duration: 0.2)) { isOpen = false }
						}
						.id(String(index))
					}
				}
			}
		}
	}
}

/// A button as wide as the page, outside any group.
struct WideButton: View {
	var title: String
	var icon: AppIcon?
	var prominent = false
	var action: () -> Void

	var body: some View {
		Button(action: action) {
			HStack(spacing: 6) {
				if let icon { HIcon(icon, size: 14) }
				Text(title)
			}
			.frame(maxWidth: .infinity)
			.padding(.vertical, 7)
		}
		.buttonStyle(PillButtonStyle(prominent: prominent))
	}
}

// MARK: Pages

private struct GeneralSettings: View {
	@AppStorage(AppAppearance.key) private var appearance = AppAppearance.system.rawValue
	@AppStorage(MessageAppearance.adaptKey) private var adaptColors = true
	@AppStorage(ReadingSettings.markReadDelayKey) private var markReadDelay = 0
	@AppStorage(ReadingSettings.loadRemoteContentKey) private var loadRemote = true
	@AppStorage(ReadingSettings.showAvatarsKey) private var showAvatars = true
	@AppStorage(ReadingSettings.offlineDepthKey) private var offlineDepth = 1000
	@Environment(MailStore.self) private var store
	@State private var launchAtLogin = LaunchAtLogin.isEnabled

	var body: some View {
		SettingsGroup(title: "Startup") {
			SettingsToggle(title: "Open Solstand Mail at login", isOn: Binding(
				get: { launchAtLogin },
				set: { launchAtLogin = $0; if !LaunchAtLogin.set($0) { launchAtLogin = LaunchAtLogin.isEnabled } }
			))
		}
		SettingsGroup(title: "Appearance") {
			SettingsPicker(
				title: "Theme",
				options: AppAppearance.allCases.map { ($0.title, $0.rawValue) },
				selection: $appearance)
			SettingsDivider()
			SettingsToggle(
				title: "Adapt message colors in dark mode",
				detail: "Re-colors mail that has no dark styles of its own. The reader's color button overrides it per sender.",
				isOn: $adaptColors)
		}
		SettingsGroup(title: "Emails") {
			SettingsToggle(
				title: "Show avatars in the email list",
				detail: "A sender's Gravatar, or their initial on a colored circle.",
				isOn: $showAvatars)
			SettingsDivider()
			SettingsPicker(
				title: "Mark as read",
				options: [("Immediately", 0), ("After 3 seconds", 3), ("After 10 seconds", 10), ("Never", -1)],
				selection: $markReadDelay)
			SettingsDivider()
			SettingsToggle(
				title: "Load remote content",
				detail: "Images, styles and fonts a message loads from the internet. Always blocked in Spam.",
				isOn: $loadRemote)
		}
		SettingsGroup(title: "Storage") {
			SettingsPicker(
				title: "Keep on this Mac",
				options: [("Newest 50 per folder", 50), ("1,000 per folder", 1000), ("5,000 per folder", 5000), ("25,000 per folder", 25000), ("Everything", Int(UInt32.max))],
				selection: $offlineDepth)
			Text("Mail kept here opens, scrolls and searches without waiting for the server. Older mail is downloaded in the background after each sync.")
				.font(Typography.meta).foregroundStyle(.secondary)
				.padding(.horizontal, 14).padding(.bottom, 10)
		}
		.onChange(of: appearance) { _, value in (AppAppearance(rawValue: value) ?? .system).apply() }
		.onChange(of: offlineDepth) { _, value in store.setOfflineDepth(value) }
	}
}

private struct NotificationSettingsPage: View {
	@Environment(MailStore.self) private var store
	@AppStorage(NotificationSettings.enabledKey) private var enabled = true
	@AppStorage(NotificationSettings.previewsKey) private var previews = true
	@AppStorage(NotificationSettings.soundKey) private var sound = true
	@AppStorage(NotificationSettings.badgeKey) private var badge = true

	/// On means macOS allows Solstand Mail's notifications and the app has not muted them itself.
	private var allowSwitch: Binding<Bool> {
		Binding(
			get: { enabled && store.notifier.isAllowed },
			set: { on in
				enabled = on
				guard on else { return }
				switch store.notifier.authorization {
				case .notDetermined: Task { await store.notifier.requestAuthorization() }
				case .denied: MailNotifier.openSystemSettings()
				default: break
				}
			})
	}

	private var allowDetail: String {
		switch store.notifier.authorization {
		case .denied: "Turned off for Solstand Mail in System Settings. Turn it on there, then come back."
		case .notDetermined: "Solstand Mail will ask macOS for permission."
		default: "Alert on new mail in any account's inbox. Turning this off stops Solstand Mail's alerts; macOS's own setting stays as it is."
		}
	}

	var body: some View {
		SettingsGroup(title: "Notifications", footer: "Solstand Mail checks every account for new mail about once a minute while it is open. Each account can be muted on its page under Accounts.") {
			SettingsToggle(title: "Allow notifications", detail: allowDetail, isOn: allowSwitch)
			SettingsDivider()
			SettingsRow {
				Text("Banner style and sounds for Solstand Mail are also managed by macOS.")
					.font(Typography.meta).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
				Spacer(minLength: 8)
				Button("Open System Settings") { MailNotifier.openSystemSettings() }
					.buttonStyle(.pill)
			}
			SettingsDivider()
			SettingsToggle(title: "Show previews", detail: "Include the sender and subject. Off, a notification only says there is new mail.", isOn: $previews)
				.disabled(!allowSwitch.wrappedValue)
			SettingsDivider()
			SettingsToggle(title: "Play a sound", isOn: $sound)
				.disabled(!allowSwitch.wrappedValue)
			SettingsDivider()
			SettingsToggle(title: "Show unread count on the Dock icon", isOn: $badge)
		}
		.onChange(of: badge) { _, _ in store.updateBadge() }
		.task { await store.notifier.refreshAuthorization() }
		// The user may have changed it in System Settings while the app was in the background.
		.onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
			Task { await store.notifier.refreshAuthorization() }
		}
	}
}

/// The Accounts page: a menu of three tabs, Organize, Accounts and Inbox Views.
private struct AccountSettings: View {
	private enum Tab: String, CaseIterable, Identifiable {
		case accounts = "Accounts", organize = "Organize", views = "Inbox Views", tabs = "Custom Tabs"
		var id: String { rawValue }
	}

	@State private var tab: Tab = .accounts

	var body: some View {
		VStack(alignment: .leading, spacing: 22) {
			HStack(spacing: 2) {
				ForEach(Tab.allCases) { item in
					Button { tab = item } label: {
						Text(item.rawValue).font(Typography.body)
							.foregroundStyle(tab == item ? Color.primary : Color.secondary)
							.padding(.horizontal, 12).padding(.vertical, 6)
							.background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(tab == item ? AppTheme.railSelection : .clear))
							.contentShape(Rectangle())
					}
					.buttonStyle(.plain)
				}
				Spacer(minLength: 0)
			}
			switch tab {
			case .organize: OrganizeTab()
			case .accounts: AccountsTab()
			case .views: InboxViewsTab()
			case .tabs: CustomTabsTab()
			}
		}
	}
}

/// Which views the sidebar lists, for the Unified section and for each account alike, and which
/// accounts Unified draws from.
private struct OrganizeTab: View {
	@Environment(MailStore.self) private var store

	var body: some View {
		VStack(alignment: .leading, spacing: 22) {
			SettingsGroup(title: "Views", footer: "On: listed below Today for everything in the account dropdown. Off: listed in the section of each inbox instead.") {
				ForEach(Array(UnifiedViewKind.allCases.enumerated()), id: \.element.id) { index, kind in
					if index > 0 { SettingsDivider() }
					SettingsRow {
						HIcon(kind.icon, size: 16).foregroundStyle(.secondary).frame(width: 22)
						Text(kind.title).font(Typography.body)
						Spacer(minLength: 12)
						Toggle("", isOn: Binding(get: { store.unifiedShows(kind) }, set: { store.setUnified(kind, shown: $0) }))
							.labelsHidden().toggleStyle(.switch)
					}
				}
			}
		}
	}
}

/// Tabs under Today in the sidebar: Today itself, which is fixed, and the ones made here.
private struct CustomTabsTab: View {
	@Environment(MailStore.self) private var store

	var body: some View {
		VStack(alignment: .leading, spacing: 22) {
			SettingsGroup(title: "Built in") {
				row(.today) { Text("Built in").font(Typography.meta).foregroundStyle(.tertiary) }
			}
			SettingsGroup(
				title: "Custom Tabs",
				footer: "Tabs are listed under Today and show the Inbox mail that matches their rules, with the unread count beside them. The newest 1,000 messages of each inbox are checked."
			) {
				if store.customTabs.isEmpty {
					SettingsRow { Text("No custom tabs yet").font(Typography.body).foregroundStyle(.secondary) }
				}
				ForEach(Array(store.customTabs.enumerated()), id: \.element.id) { index, tab in
					if index > 0 { SettingsDivider() }
					row(tab) {
						Button("Edit") { store.customTabEditor = tab }.buttonStyle(.pill)
						Button("Delete") { store.deleteCustomTab(tab.id) }.buttonStyle(.pill).foregroundStyle(.red)
					}
				}
			}
			WideButton(title: "New Custom Tab", icon: .add) { store.customTabEditor = CustomTab(rules: [CustomTab.Rule(kind: .from)]) }
		}
	}

	private func row<Trailing: View>(_ tab: CustomTab, @ViewBuilder trailing: () -> Trailing) -> some View {
		SettingsRow {
			HIcon(tab.appIcon, size: 16).foregroundStyle(.secondary).frame(width: 22)
			VStack(alignment: .leading, spacing: 1) {
				Text(tab.name).font(Typography.bodySemibold).lineLimit(1)
				Text(tab.summary.prefix(1).uppercased() + tab.summary.dropFirst()).font(Typography.meta).foregroundStyle(.secondary).lineLimit(2)
			}
			Spacer(minLength: 8)
			trailing()
		}
	}
}

/// Custom inboxes that combine chosen accounts and inboxes.
private struct InboxViewsTab: View {
	@Environment(MailStore.self) private var store

	var body: some View {
		VStack(alignment: .leading, spacing: 22) {
			SettingsGroup(title: "Unified Inbox") {
				ForEach(Array(store.accountList.enumerated()), id: \.element.id) { index, account in
					let isOn = store.unifiedIncludes(account.id)
					if index > 0 { SettingsDivider() }
					SettingsRow {
						ProfileAvatar(key: AvatarCache.key(account: account.id), name: store.accountName(account), size: 28)
						VStack(alignment: .leading, spacing: 1) {
							Text(store.accountName(account)).font(Typography.body).lineLimit(1)
							Text(account.email).font(Typography.meta).foregroundStyle(.secondary).lineLimit(1)
						}
						Spacer(minLength: 12)
						Toggle("", isOn: Binding(get: { isOn }, set: { store.setUnified(account.id, included: $0) }))
							.labelsHidden().toggleStyle(.switch)
							.disabled(isOn && store.unifiedIncludedCount <= 1)
					}
				}
			}
			if store.inboxViews.isEmpty {
				SettingsGroup(title: "Custom Inboxes View", footer: "An inbox view combines the accounts and inboxes you choose into one list.") {
					SettingsRow {
						Text("No inbox views yet").font(Typography.body).foregroundStyle(.secondary)
					}
				}
			} else {
				SettingsGroup(title: "Inbox Views") {
					ForEach(Array(store.inboxViews.enumerated()), id: \.element.id) { index, view in
						if index > 0 { SettingsDivider() }
						SettingsRow {
							VStack(alignment: .leading, spacing: 1) {
								Text(view.name).font(Typography.bodySemibold).lineLimit(1)
								let inboxes = view.members.count, accounts = view.accountIDs.count
								Text("\(inboxes) inbox\(inboxes == 1 ? "" : "es") · \(accounts) account\(accounts == 1 ? "" : "s")")
									.font(Typography.meta).foregroundStyle(.secondary)
							}
							Spacer(minLength: 8)
							Button("Edit") { store.inboxViewEditor = view }.buttonStyle(.pill)
							Button("Delete") { store.deleteInboxView(view.id) }.buttonStyle(.pill).foregroundStyle(.red)
						}
					}
				}
			}
			WideButton(title: "New Inbox View", icon: .add) { store.inboxViewEditor = InboxView() }
		}
	}
}

private struct AccountsTab: View {
	@Environment(MailStore.self) private var store
	/// The account whose page is open; nil shows the list. The page slides in from the right.
	@State private var openID: String?
	/// The account waiting on the sign-out confirmation.
	@State private var signingOut: Account?

	var body: some View {
		ZStack(alignment: .top) {
			if let account = store.accountList.first(where: { $0.id == openID }) {
				AccountDetail(account: account) { withAnimation(.snappy(duration: 0.25)) { openID = nil } }
					.transition(.move(edge: .trailing).combined(with: .opacity))
			} else {
				list.transition(.move(edge: .leading).combined(with: .opacity))
			}
		}
		.frame(maxWidth: .infinity, alignment: .top)
		.clipped()
		.confirmationDialog(
			signingOut.map { "Sign out of \($0.email)?" } ?? "Sign out?",
			isPresented: Binding(get: { signingOut != nil }, set: { if !$0 { signingOut = nil } }),
			titleVisibility: .visible,
			presenting: signingOut
		) { account in
			Button("Sign Out", role: .destructive) { store.signOut(account) }
		} message: { _ in
			Text("Its saved mail and any unsent changes are removed from this Mac. Mail on the server is not affected.")
		}
	}

	private var list: some View {
		VStack(alignment: .leading, spacing: 22) {
			SettingsGroup(title: "Accounts") {
				ForEach(Array(store.accountList.enumerated()), id: \.element.id) { index, account in
					if index > 0 { SettingsDivider() }
					SettingsRow {
						Button { withAnimation(.snappy(duration: 0.25)) { openID = account.id } } label: {
							HStack(spacing: 10) {
								ProfileAvatar(key: AvatarCache.key(account: account.id), name: store.accountName(account), size: 32)
								VStack(alignment: .leading, spacing: 1) {
									Text(store.accountName(account)).font(Typography.bodySemibold).lineLimit(1)
									Text(account.email).font(Typography.meta).foregroundStyle(.secondary).lineLimit(1)
								}
								Spacer(minLength: 8)
							}
							.contentShape(Rectangle())
						}
						.buttonStyle(.plain)
						Button("Sign Out") { signingOut = account }
							.buttonStyle(.pill).foregroundStyle(.red)
						Button { withAnimation(.snappy(duration: 0.25)) { openID = account.id } } label: {
							HIcon(.chevronRight, size: 12).foregroundStyle(.secondary).contentShape(Rectangle())
						}
						.buttonStyle(.plain)
					}
				}
			}
			WideButton(title: "Add Account", icon: .add) { store.showAddAccount = true }
		}
	}
}

/// One account: its picture, name and signature.
private struct AccountDetail: View {
	@Environment(MailStore.self) private var store
	var account: Account
	var back: () -> Void

	@State private var name = ""
	@State private var signature = ""
	@State private var loaded = false
	@State private var saving = false
	@State private var note: String?

	private var profiles: AccountProfiles { store.profiles }
	private var key: String { AvatarCache.key(account: account.id) }
	private var remote: AccountProfiles.Remote? { profiles.remote[account.id] }
	private var savedName: String { store.accountName(account) }
	private var savedSignature: String { profiles.signature(account.id) }

	private var isDirty: Bool {
		name.trimmingCharacters(in: .whitespacesAndNewlines) != savedName
			|| signature.trimmingCharacters(in: .whitespacesAndNewlines) != savedSignature
	}

	var body: some View {
		VStack(alignment: .leading, spacing: 22) {
			Button(action: back) {
				HStack(spacing: 6) {
					HIcon(.arrowLeft, size: 13)
					Text("Accounts").font(Typography.body)
				}
				.foregroundStyle(.secondary)
				.contentShape(Rectangle())
			}
			.buttonStyle(.plain)

			HStack(spacing: 16) {
				ProfileAvatar(key: key, name: name.isEmpty ? savedName : name, size: 72)
				VStack(alignment: .leading, spacing: 8) {
					Text(account.email).font(Typography.meta).foregroundStyle(.secondary).lineLimit(1)
					HStack(spacing: 8) {
						Button("Choose Picture…", action: choosePicture).buttonStyle(.pill)
						if store.avatars.hasLocal(key) {
							Button("Remove") { store.avatars.removeLocal(key: key); store.loadAvatars(for: account) }.buttonStyle(.pill)
						}
					}
				}
				Spacer(minLength: 0)
			}

			SettingsGroup(title: "Profile") {
				SettingsRow {
					Text("Name").font(Typography.body)
					Spacer(minLength: 12)
					TextField("Your name", text: $name)
						.textFieldStyle(.plain).multilineTextAlignment(.trailing).font(Typography.body)
				}
				SettingsDivider()
				SettingsRow {
					Text("Email").font(Typography.body)
					Spacer(minLength: 12)
					Text(account.email).font(Typography.body).foregroundStyle(.secondary).lineLimit(1).textSelection(.enabled)
				}
			}

			SettingsGroup(title: "Notifications", footer: "Off: no system notification for new mail in this account. Its mail still arrives and counts toward the Dock badge.") {
				SettingsToggle(title: "Notify about new mail", isOn: Binding(
					get: { store.notifier.notifies(account.id) },
					set: { store.notifier.setNotifies($0, accountID: account.id) }))
			}

			SettingsGroup(title: "Signature", footer: signatureFooter) {
				TextEditor(text: $signature)
					.font(Typography.body)
					.scrollContentBackground(.hidden)
					.frame(minHeight: 96)
					.padding(.vertical, 8)
			}

			HStack(spacing: 8) {
				if saving { ProgressView().controlSize(.small) }
				Spacer()
				Button("Revert") { fill() }.buttonStyle(.pill).disabled(!isDirty || saving)
				Button("Save", action: save).buttonStyle(.pillProminent).disabled(!isDirty || saving)
			}
			if let note {
				Text(note).font(Typography.meta).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
			}

			WideButton(title: "Sign Out") { store.signOut(account) }
		}
		.task {
			fill()
			await profiles.refresh(account)
			// Take the server's values unless the user has started typing.
			if !isDirty { fill() }
			loaded = true
		}
	}

	private var signatureFooter: String {
		var text = profiles.hasSignature(account.id)
			? "Added to new messages, replies and forwards from this account."
			: "No signature is set, so “\(AccountProfiles.defaultSignature)” is added to new messages. Write your own to replace it."
		if remote?.editable == false { text += " Your server doesn't allow edits, so changes stay on this Mac." }
		return text
	}

	private func fill() {
		name = savedName
		signature = savedSignature
		note = nil
	}

	private func save() {
		saving = true; note = nil
		let name = name, signature = signature
		Task {
			note = await profiles.save(account, name: name, signature: signature)
			saving = false
			fill()
			if let kept = note { note = kept }
		}
	}

	private func choosePicture() {
		let panel = NSOpenPanel()
		panel.allowedContentTypes = [.image]
		panel.allowsMultipleSelection = false
		panel.message = "Choose a picture for \(savedName)"
		guard panel.runModal() == .OK, let url = panel.url else { return }
		if !store.avatars.setLocal(key: key, from: url) { note = "That file couldn't be read as a picture." }
	}
}

private struct AISettingsPage: View {
	@Environment(MailStore.self) private var store
	private var ai: AISettings { store.ai }

	var body: some View {
		SettingsGroup(title: "On-device AI", footer: "Chat, summaries, reply writing and rewrites use Apple’s on-device language model. Prompts are not sent to a hosted AI model. Connected MCP services still receive the specific tool requests you run.") {
			SettingsRow {
				VStack(alignment: .leading, spacing: 4) {
					Text("Apple Foundation Models").font(Typography.bodySemibold)
					Text(ai.availabilityDescription).font(Typography.meta).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
				}
				Spacer(minLength: 8)
				Circle().fill(ai.isConfigured ? Color.green : Color.orange).frame(width: 7, height: 7)
			}
		}
		SettingsGroup(title: "AI Chat", footer: "Set the assistant’s tone and response preferences.") {
			promptField("For example: Be concise and sign off with Thanks, Sam", text: Binding(get: { ai.instructions }, set: { ai.instructions = $0 }))
		}
		SettingsGroup(title: "AI Writer", footer: "These preferences apply to drafted and rewritten replies.") {
			promptField("For example: Friendly, short paragraphs, no jargon", text: Binding(get: { ai.writerInstructions }, set: { ai.writerInstructions = $0 }))
		}
	}

	private func promptField(_ placeholder: String, text: Binding<String>) -> some View {
		TextField(placeholder, text: text, axis: .vertical)
			.textFieldStyle(.plain).font(Typography.body)
			.lineLimit(2...6)
			.padding(.vertical, 12)
			.frame(maxWidth: .infinity, alignment: .leading)
	}
}

private struct AboutSettings: View {
	var body: some View {
		SettingsGroup(title: "Solstand Mail") {
			SettingsRow {
				Text("Version").font(Typography.body)
				Spacer()
				Text(AppMetadata.currentVersion).font(Typography.body).foregroundStyle(.secondary)
			}
			SettingsDivider()
			SettingsRow {
				Text("Mail data").font(Typography.body)
				Spacer(minLength: 16)
				Text(MailStore.dataDirectoryDescription).font(Typography.meta).foregroundStyle(.secondary)
					.lineLimit(1).truncationMode(.middle).textSelection(.enabled)
			}
		}
	}
}
