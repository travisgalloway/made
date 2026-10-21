import Foundation

/// Application version metadata resolved from bundle Info.plist properties.
public struct AppVersion: Sendable, Equatable {
    public let marketingVersion: String
    public let buildNumber: String

    public init(marketingVersion: String, buildNumber: String) {
        self.marketingVersion = marketingVersion
        self.buildNumber = buildNumber
    }

    public init(bundle: Bundle = .main) {
        let marketing = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        self.init(marketingVersion: marketing, buildNumber: build)
    }

    public static var current: AppVersion {
        AppVersion(bundle: .main)
    }

    public var displayString: String {
        "Version \(marketingVersion) (\(buildNumber))"
    }
}
