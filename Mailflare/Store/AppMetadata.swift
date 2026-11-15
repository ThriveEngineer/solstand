import Foundation

/// Version metadata used by About and the sidebar.
enum AppMetadata {
	static var currentVersion: String {
		Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
	}
}
