import SwiftUI

/// Shared attribution and support details, using the installed host app's version.
public struct AboutFooter: View {
    public init() {}

    private var appName: String {
        #if os(iOS)
        return "ES100 Control"
        #else
        return "EarStudio Companion"
        #endif
    }

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
    }

    private var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
    }

    private var revision: String {
        let hash = Bundle.main.object(forInfoDictionaryKey: "EarStudioRevision") as? String ?? ""
        guard !hash.isEmpty else { return "Revision unavailable" }
        let modified = Bundle.main.object(forInfoDictionaryKey: "EarStudioSourceState") as? String == "modified"
        return "Revision \(hash)" + (modified ? " · modified" : "")
    }

    private var supportURL: URL {
        #if os(iOS)
        let platform = "iOS"
        #else
        let platform = "macOS"
        #endif
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = "ig@rbuz.me"
        components.queryItems = [
            URLQueryItem(name: "subject", value: "\(appName) — \(platform) support"),
            URLQueryItem(name: "body", value: "\(appName) for \(platform)\nVersion \(version) (beta) · Build \(build)\n\(revision)\n\n")
        ]
        return components.url!
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(appName).font(.subheadline.weight(.semibold))
            Text("Version \(version) (beta) · Build \(build)")
                .font(.caption).foregroundStyle(.secondary)
            Text(revision).font(.caption).foregroundStyle(.secondary)
                .textSelection(.enabled)
            Text("Made by Igor").font(.caption).foregroundStyle(.secondary)
            Link("Contact support", destination: supportURL)
                .font(.subheadline)
                .frame(minHeight: 44, alignment: .leading)
                .accessibilityIdentifier("about.contactSupport")
            Link("View on GitHub", destination: URL(string: "https://github.com/igorgarbuz/earstudio-mac")!)
                .font(.subheadline)
                .frame(minHeight: 44, alignment: .leading)
                .accessibilityIdentifier("about.github")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
