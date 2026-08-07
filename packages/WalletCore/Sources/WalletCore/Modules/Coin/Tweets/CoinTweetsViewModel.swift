import Foundation
import HsExtensions
import MarketKit

class CoinTweetsViewModel: ObservableObject {
    private let coinUid: String
    private let marketKit = Core.shared.marketKit
    private let currencyManager = Core.shared.currencyManager
    private let languageManager = LanguageManager.shared
    private let performanceDataManager = Core.shared.performanceDataManager

    private var tasks = Set<AnyTask>()
    private var user: TwitterUser?

    @Published private(set) var state: State = .loading
    @Published private(set) var isRefreshing = false

    init(coinUid: String) {
        self.coinUid = coinUid
    }
}

extension CoinTweetsViewModel {
    var twitterPageUrl: String? {
        user.map { "https://twitter.com/\($0.username)" }
    }

    func load() {
        sync(showLoading: true)
    }

    func refresh() {
        sync(showLoading: false)
    }

    func onRetry() {
        sync(showLoading: true)
    }

    private func sync(showLoading: Bool) {
        tasks = Set()

        if showLoading {
            state = .loading
        } else {
            isRefreshing = true
        }

        Task { [weak self, coinUid, marketKit, currencyManager, languageManager, performanceDataManager] in
            do {
                guard let bearerToken = Self.twitterBearerToken else {
                    throw TweetsProvider.ProviderError.unauthorized
                }

                let provider = TweetsProvider(bearerToken: bearerToken)
                let username = try await Self.twitterUsername(
                    coinUid: coinUid,
                    marketKit: marketKit,
                    currencyCode: currencyManager.baseCurrency.code,
                    languageCode: languageManager.currentLanguage,
                    roiUids: performanceDataManager.coins.map(\.uid),
                    roiPeriods: performanceDataManager.periods
                )
                let user = try await provider.user(username: username)
                let tweets = try await provider.tweets(user: user)
                let viewItems = tweets.map { TweetViewItem(tweet: $0) }

                await MainActor.run { [weak self] in
                    self?.user = user
                    self?.isRefreshing = false
                    self?.state = .loaded(viewItems: viewItems)
                }
            } catch TweetsProvider.ProviderError.userNotFound, TweetsProvider.ProviderError.unauthorized {
                await MainActor.run { [weak self] in
                    self?.isRefreshing = false
                    self?.state = .notAvailable
                }
            } catch {
                await MainActor.run { [weak self] in
                    self?.isRefreshing = false
                    self?.state = .failed
                }
            }
        }
        .store(in: &tasks)
    }
}

private extension CoinTweetsViewModel {
    static var twitterBearerToken: String? {
        if let token = ApiKeyManager.apiKeys(name: .twitterBearerToken)?.randomElement(), !token.isEmpty {
            return token
        }

        return AppConfig.twitterBearerToken
    }

    static func twitterUsername(
        coinUid: String,
        marketKit: MarketKit.Kit,
        currencyCode: String,
        languageCode: String,
        roiUids: [String],
        roiPeriods: [HsTimePeriod]
    ) async throws -> String {
        if coinUid.isSafeCoin || coinUid == "custom_safe-erc20-SAFE" {
            return AppConfig.appTwitterAccount
        }

        let overview = try await marketKit.marketInfoOverview(
            coinUid: coinUid,
            roiUids: roiUids,
            roiPeriods: roiPeriods,
            currencyCode: currencyCode,
            languageCode: languageCode
        )

        guard let rawUsername = overview.links[.twitter], let username = normalizeTwitterUsername(rawUsername) else {
            throw TweetsProvider.ProviderError.userNotFound
        }

        return username
    }

    static func normalizeTwitterUsername(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        if trimmed.hasPrefix("@") {
            return String(trimmed.dropFirst()).nonEmpty
        }

        if let url = URL(string: trimmed), let host = url.host?.lowercased(), host == "twitter.com" || host == "x.com" {
            return username(fromPathComponent: url.pathComponents.dropFirst().first)
        }

        let candidate = trimmed
            .stripping(prefix: "https://twitter.com/")
            .stripping(prefix: "https://x.com/")
            .stripping(prefix: "twitter.com/")
            .stripping(prefix: "x.com/")
            .components(separatedBy: "/")
            .first

        return username(fromPathComponent: candidate)
    }

    static func username(fromPathComponent component: String?) -> String? {
        guard var username = component?.nonEmpty else {
            return nil
        }

        username = username
            .components(separatedBy: "?")
            .first?
            .components(separatedBy: "#")
            .first ?? username

        let reservedPaths = ["hashtag", "home", "i", "intent", "messages", "search", "share"]
        guard !reservedPaths.contains(username.lowercased()) else {
            return nil
        }

        return username.nonEmpty
    }
}

extension CoinTweetsViewModel {
    enum State {
        case loading
        case loaded(viewItems: [TweetViewItem])
        case notAvailable
        case failed
    }

    struct TweetViewItem: Identifiable {
        let id: String
        let title: String
        let subtitle: String
        let titleImageUrl: String
        let text: String
        let date: String
        let url: String
        let attachments: [Tweet.Attachment]
        let referencedTweet: ReferencedTweetViewItem?
        let metrics: MetricsViewItem?

        init(tweet: Tweet) {
            id = tweet.id
            title = tweet.user.name
            subtitle = "@\(tweet.user.username)"
            titleImageUrl = tweet.user.profileImageUrl
            text = tweet.text
            date = DateHelper.instance.formatFullTime(from: tweet.date)
            url = "https://twitter.com/\(tweet.user.username)/status/\(tweet.id)"
            attachments = tweet.attachments
            referencedTweet = tweet.referencedTweet.map { ReferencedTweetViewItem(referencedTweet: $0) }
            metrics = tweet.publicMetrics.map { MetricsViewItem(metrics: $0) }
        }
    }

    struct ReferencedTweetViewItem {
        let title: String
        let text: String

        init(referencedTweet: Tweet.ReferencedTweet) {
            switch referencedTweet.type {
            case .quoted:
                title = "coin_tweets.reference_type.quoted".localized(referencedTweet.user.username)
            case .retweeted:
                title = "coin_tweets.reference_type.retweeted".localized(referencedTweet.user.username)
            case .replied:
                title = "coin_tweets.reference_type.replied".localized(referencedTweet.user.username)
            }

            text = referencedTweet.text
        }
    }

    struct MetricsViewItem {
        let replies: String
        let retweets: String
        let likes: String
        let quotes: String

        init(metrics: TweetsPageResponse.RawTweet.PublicMetrics) {
            replies = ValueFormatter.instance.formatShort(value: Decimal(metrics.replyCount)) ?? "\(metrics.replyCount)"
            retweets = ValueFormatter.instance.formatShort(value: Decimal(metrics.retweetCount)) ?? "\(metrics.retweetCount)"
            likes = ValueFormatter.instance.formatShort(value: Decimal(metrics.likeCount)) ?? "\(metrics.likeCount)"
            quotes = ValueFormatter.instance.formatShort(value: Decimal(metrics.quoteCount)) ?? "\(metrics.quoteCount)"
        }
    }
}

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}
