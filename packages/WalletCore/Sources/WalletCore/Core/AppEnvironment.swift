import Foundation

public enum AppEnvironment: String {
    case dev
    case prod

    public private(set) static var current: AppEnvironment = .prod

    public static func configure(_ env: AppEnvironment) {
        current = env
    }

    public static var config: Config {
        switch current {
        case .dev: return .dev
        case .prod: return .prod
        }
    }

    static func marketApiUrl(override: String?) -> String {
        guard let value = override?.trimmingCharacters(in: .whitespacesAndNewlines),
              let url = URL(string: value),
              let scheme = url.scheme?.lowercased(),
              ["https", "http"].contains(scheme),
              let host = url.host, !host.isEmpty,
              !value.contains("$("), !value.contains("${")
        else {
            return config.marketApiUrl
        }

        return value
    }
}

public extension AppEnvironment {
    struct Config {
        public let marketApiUrl: String
        public let swapApiUrl: String
        public let referralAppServerUrl: String
        public let showBuildNumber: Bool
        public let showDevTools: Bool

        static let dev = Config(
            marketApiUrl: "https://api-dev.blocksdecoded.com",
            swapApiUrl: "https://swap-dev.unstoppable.money/api",
            referralAppServerUrl: "https://dev-be.unstoppable.money/api",
            showBuildNumber: true,
            showDevTools: true
        )

        static let prod = Config(
            marketApiUrl: "https://api.blocksdecoded.com",
            swapApiUrl: "https://swap-api.unstoppable.money",
            referralAppServerUrl: "https://be.unstoppable.money/api",
            showBuildNumber: false,
            showDevTools: false
        )
    }
}
