import SwiftUI
import MailflareCore

struct SignInView: View {
	/// True when shown as a popup over the mail window (adding another account).
	var isPopup = false

	@Environment(MailStore.self) private var store
	@AppStorage("lastEmail") private var email = ""
	@State private var provider = MailProviders.custom
	@State private var providerPicked = false
	@State private var providerOpen = false
	@State private var password = ""
	@State private var incoming = ServerEndpoint(host: "", port: 993, security: .tls)
	@State private var outgoing = ServerEndpoint(host: "", port: 465, security: .tls)
	@State private var username = ""
	@State private var busy = false
	@State private var error: String?

	var body: some View {
		// The window fits the form: the plain layout when it fits, a scrolling one when it is taller
		// than the room (for example with the server cards open).
		ViewThatFits(in: .vertical) {
			VStack(spacing: 0) {
				form
				Spacer(minLength: 0)
				bottomBar
			}
			ScrollView { form }
				.safeAreaInset(edge: .bottom, spacing: 0) {
					bottomBar.background(alignment: .top) { ModalFade().frame(height: 24).offset(y: -24) }
				}
		}
		.frame(width: 420)
		// Tall enough that the provider dropdown opens in full.
		.frame(minHeight: min(500, min(680, ModalMetrics.maxHeight)), maxHeight: min(680, ModalMetrics.maxHeight))
		.background(AppTheme.background)
		.overlay(alignment: .topTrailing) {
			if isPopup {
				TitlebarIconButton(icon: .close, help: "Close") { store.showAddAccount = false }
					.keyboardShortcut(.cancelAction)
					.padding(14)
			}
		}
		.onAppear {
			if !email.isEmpty, let match = MailProviders.match(email: email) { select(match, picked: false) }
		}
		.onChange(of: email) { _, value in
			guard !providerPicked, value.contains("@") else { return }
			let match = MailProviders.match(email: value) ?? MailProviders.custom
			if match != provider { select(match, picked: false) }
		}
	}

	private var form: some View {
		VStack(alignment: .leading, spacing: 16) {
			heading
			providerMenu
			accountFields
			hint
			if case .custom = provider.kind { customFields }
			if let message = error ?? store.banner {
				Text(message).font(Typography.notice).foregroundStyle(.red)
					.fixedSize(horizontal: false, vertical: true)
			}
		}
		.frame(maxWidth: .infinity, alignment: .leading)
		.padding(.horizontal, 28)
		.padding(.top, 28)
		.padding(.bottom, 16)
	}

	// MARK: Pieces

	private var heading: some View {
		VStack(alignment: .leading, spacing: 6) {
			Text(isPopup ? "Add an account" : "Sign in")
				.font(.system(size: 21, weight: .medium))
		}
		.padding(.top, isPopup ? 8 : 0)
	}

	private func labeled<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
		VStack(alignment: .leading, spacing: 6) {
			Text(title).font(Typography.meta.weight(.medium)).foregroundStyle(.secondary)
			content()
		}
	}

	/// The provider picker at the top: common providers or another server. A dropdown
	/// card like the ones in the toolbar, opening below the button.
	private var providerMenu: some View {
		Button {
			withAnimation(.snappy(duration: 0.2)) { providerOpen.toggle() }
		} label: {
			HStack(spacing: 10) {
				ProviderBadge(provider: provider, size: 26)
				Text(provider.name).font(Typography.body)
				Spacer(minLength: 0)
				HIcon(.chevronDown, size: 13).foregroundStyle(.secondary).rotationEffect(.degrees(providerOpen ? 180 : 0))
			}
			.padding(.horizontal, 12)
			.frame(height: 44)
			.frame(maxWidth: .infinity)
			.background(AppTheme.composerContextFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
			.overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(AppTheme.composerStroke, lineWidth: 1))
			.contentShape(Rectangle())
		}
		.buttonStyle(.plain)
		.overlay(alignment: .topLeading) {
			if providerOpen {
				DropdownCard(width: nil, anchor: .topLeading) {
					DropdownScroll(maxHeight: 290) {
						ForEach(MailProviders.common + [MailProviders.custom]) { item in
							DropdownRow(label: item.name, isSelected: item == provider) {
								select(item, picked: true)
								withAnimation(.snappy(duration: 0.2)) { providerOpen = false }
							}
						}
					}
				}
				.offset(y: 50)
			}
		}
		.clickAway(isActive: providerOpen) { withAnimation(.snappy(duration: 0.2)) { providerOpen = false } }
		.zIndex(providerOpen ? 10 : 0)
	}

	private var accountFields: some View {
		VStack(alignment: .leading, spacing: 14) {
			labeled("Email") {
				TextField("you@example.com", text: $email).textFieldStyle(.card).textContentType(.username).autocorrectionDisabled()
			}
			if !usesOAuth {
				labeled("Password") {
					CardSecureField(title: usesIMAP ? "App password" : "Password or app password", text: $password)
				}
			}
		}
		.onSubmit(submit)
	}

	@ViewBuilder
	private var hint: some View {
		if usesOAuth {
			Text("You'll sign in securely on \(provider.name)'s own page.")
				.font(Typography.meta).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
		} else if provider.id == "outlook" {
			Text("Outlook requires OAuth. Configure your own Microsoft Entra client ID for this build.")
				.font(Typography.meta).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
		} else if usesIMAP {
			Text("Gmail, iCloud, Yahoo and most other providers need an app password here, not your account password.")
				.font(Typography.meta).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
		}
	}

	/// Other mail servers: enter the incoming and outgoing server details.
	private var customFields: some View {
		VStack(alignment: .leading, spacing: 14) {
			endpointCard("Incoming (IMAP)", endpoint: $incoming, showsUsername: true)
			endpointCard("Outgoing (SMTP)", endpoint: $outgoing, showsUsername: false)
		}
	}

	private func endpointCard(_ title: String, endpoint: Binding<ServerEndpoint>, showsUsername: Bool) -> some View {
		VStack(alignment: .leading, spacing: 6) {
			Text(title).font(Typography.meta.weight(.medium)).foregroundStyle(.secondary)
			VStack(spacing: 0) {
				settingRow("Server") {
					TextField("imap.example.com", text: endpoint.host).textFieldStyle(.plain).multilineTextAlignment(.trailing).autocorrectionDisabled()
				}
				rowDivider
				settingRow("Port") {
					TextField("993", text: portText(endpoint.port)).textFieldStyle(.plain).multilineTextAlignment(.trailing)
				}
				rowDivider
				settingRow("Security") {
					Picker("Security", selection: endpoint.security) {
						ForEach(ConnectionSecurity.allCases) { Text($0.rawValue).tag($0) }
					}
					.labelsHidden().pickerStyle(.menu).fixedSize()
				}
				if showsUsername {
					rowDivider
					settingRow("Username") {
						TextField(provider.username(for: email.isEmpty ? "you@example.com" : email), text: $username)
							.textFieldStyle(.plain).multilineTextAlignment(.trailing).autocorrectionDisabled()
					}
				}
			}
			.background(AppTheme.composerContextFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
			.overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(AppTheme.composerStroke, lineWidth: 1))
		}
	}

	private var rowDivider: some View {
		Rectangle().fill(AppTheme.composerStroke).frame(height: 1).padding(.leading, 12)
	}

	private func settingRow<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
		HStack(spacing: 12) {
			Text(label).font(Typography.body).foregroundStyle(.secondary)
			Spacer(minLength: 8)
			content().font(Typography.body)
		}
		.padding(.horizontal, 12)
		.frame(minHeight: 38)
	}

	private func portText(_ port: Binding<Int>) -> Binding<String> {
		Binding(
			get: { port.wrappedValue == 0 ? "" : String(port.wrappedValue) },
			set: { port.wrappedValue = Int($0.filter(\.isNumber).prefix(5)) ?? 0 })
	}


	private var bottomBar: some View {
		VStack(spacing: 10) {
			Button(action: submit) {
				Text(busy ? "Signing in…" : (usesOAuth ? "Continue with \(provider.name)" : "Sign In"))
					.font(.system(size: 14, weight: .semibold))
					.frame(maxWidth: .infinity)
					.padding(.vertical, 7)
			}
			.buttonStyle(.pillProminent)
			.keyboardShortcut(.defaultAction)
			.disabled(busy || !canSubmit)
		}
		.padding(.horizontal, 28)
		.padding(.top, 12)
		.padding(.bottom, 24)
		.background(AppTheme.background)
	}

	// MARK: State

	private var usesIMAP: Bool {
		switch provider.kind {
		case .imap: true
		case .custom: true
		}
	}

	/// This build has a client id for the provider, so the browser sign-in replaces the password.
	private var usesOAuth: Bool {
		guard let oauth = provider.oauth else { return false }
		return OAuthConfig.isAvailable(oauth)
	}

	private var canSubmit: Bool {
		let blank = { (s: String) in s.trimmingCharacters(in: .whitespaces).isEmpty }
		let needsHosts = usesIMAP && (blank(incoming.host) || blank(outgoing.host))
		return !needsHosts && !blank(email) && (usesOAuth || !password.isEmpty)
	}

	private var mailServerConfig: MailServerConfig {
		let login = username.trimmingCharacters(in: .whitespaces)
		return MailServerConfig(
			incoming: incoming.core, outgoing: outgoing.core,
			username: login.isEmpty ? provider.username(for: email.trimmingCharacters(in: .whitespaces)) : login)
	}

	/// Google and most providers show an app password in groups ("abcd efgh ijkl mnop") but the server
	/// wants it without the spaces, so whitespace is dropped for the known providers.
	private var passwordToSend: String {
		if case .imap = provider.kind { return password.filter { !$0.isWhitespace } }
		return password
	}

	private func select(_ new: MailProvider, picked: Bool) {
		provider = new
		providerPicked = providerPicked || picked
		error = nil
		username = ""
		switch new.kind {
		case let .imap(defaultIncoming, defaultOutgoing):
			incoming = defaultIncoming
			outgoing = defaultOutgoing
		case .custom:
			incoming = ServerEndpoint(host: "", port: 993, security: .tls)
			outgoing = ServerEndpoint(host: "", port: 465, security: .tls)
		}
	}

	private func submit() {
		guard canSubmit, !busy else { return }
		busy = true; error = nil; store.banner = nil
		Task {
			defer { busy = false }
			do {
				if usesOAuth, let oauth = provider.oauth, let client = OAuthConfig.client(for: oauth) {
					try await store.signInOAuth(email: email, client: client, config: mailServerConfig)
				} else if usesIMAP {
					try await store.signInIMAP(email: email, password: passwordToSend, config: mailServerConfig)
					password = ""
				}
			} catch {
				self.error = describe(error)
			}
		}
	}
}
