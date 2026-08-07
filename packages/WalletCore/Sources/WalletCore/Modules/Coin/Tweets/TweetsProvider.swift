import Foundation

class TweetsProvider {
    private let baseUrl = URL(string: "https://api.x.com/2/")!
    private let bearerToken: String
    private let decoder: JSONDecoder

    init(bearerToken: String) {
        self.bearerToken = bearerToken

        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

            if let date = formatter.date(from: string) {
                return date
            }

            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid Twitter date: \(string)")
        }
    }
}

extension TweetsProvider {
    func user(username: String) async throws -> TwitterUser {
        let response: UserSingleResponse = try await request(
            path: "users/by/username/\(username)",
            parameters: [
                "user.fields": Self.userFields,
            ]
        )

        return response.data
    }

    func tweets(user: TwitterUser) async throws -> [Tweet] {
        let response: TweetsPageResponse = try await request(
            path: "users/\(user.id)/tweets",
            parameters: [
                "expansions": Self.expansions,
                "media.fields": Self.mediaFields,
                "tweet.fields": Self.tweetFields,
                "user.fields": Self.userFields,
                "max_results": "50",
            ]
        )

        return response.tweets(user: user)
    }
}

extension TweetsProvider {
    enum ProviderError: Error {
        case invalidUrl
        case userNotFound
        case unauthorized
        case requestFailed
    }

    private func request<T: Decodable>(path: String, parameters: [String: String]) async throws -> T {
        var components = URLComponents(url: baseUrl.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        components?.queryItems = parameters.map { URLQueryItem(name: $0.key, value: $0.value) }

        guard let url = components?.url else {
            throw ProviderError.invalidUrl
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ProviderError.requestFailed
        }

        switch httpResponse.statusCode {
        case 200 ..< 300:
            return try decoder.decode(T.self, from: data)
        case 401, 403:
            throw ProviderError.unauthorized
        case 404:
            throw ProviderError.userNotFound
        default:
            throw ProviderError.requestFailed
        }
    }
}

private extension TweetsProvider {
    static let userFields = "created_at,description,entities,id,location,name,pinned_tweet_id,profile_image_url,protected,public_metrics,url,username,verified,verified_type"
    static let tweetFields = "attachments,author_id,context_annotations,conversation_id,created_at,edit_history_tweet_ids,entities,geo,id,in_reply_to_user_id,lang,note_tweet,possibly_sensitive,public_metrics,referenced_tweets,reply_settings,source,text,withheld"
    static let mediaFields = "alt_text,duration_ms,height,media_key,preview_image_url,public_metrics,type,url,variants,width"
    static let expansions = "attachments.poll_ids,attachments.media_keys,author_id,edit_history_tweet_ids,entities.mentions.username,geo.place_id,in_reply_to_user_id,referenced_tweets.id,referenced_tweets.id.author_id"
}

extension TweetsProvider {
    struct UserSingleResponse: Decodable {
        let data: TwitterUser
    }
}

struct TwitterUser: Decodable {
    let id: String
    let name: String
    let username: String
    let profileImageUrl: String

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case username
        case profileImageUrl = "profile_image_url"
    }
}

struct Tweet {
    let id: String
    let user: TwitterUser
    let text: String
    let date: Date
    let attachments: [Attachment]
    let referencedTweet: ReferencedTweet?
    let publicMetrics: TweetsPageResponse.RawTweet.PublicMetrics?

    enum Attachment {
        case photo(String)
        case video(previewUrl: String, videoUrl: String?)
    }

    enum ReferenceType {
        case quoted
        case retweeted
        case replied
    }

    struct ReferencedTweet {
        let type: ReferenceType
        let user: TwitterUser
        let text: String
    }
}

struct TweetsPageResponse: Decodable {
    let data: [RawTweet]?
    let includes: Includes?

    func tweets(user: TwitterUser) -> [Tweet] {
        data?.map { buildTweet(rawTweet: $0, user: user) } ?? []
    }

    private func buildTweet(rawTweet: RawTweet, user: TwitterUser) -> Tweet {
        var attachments = [Tweet.Attachment]()

        if let mediaKeys = rawTweet.attachments?.mediaKeys {
            for mediaKey in mediaKeys {
                guard let media = includes?.media?.first(where: { $0.key == mediaKey }) else {
                    continue
                }

                switch media.type {
                case "photo":
                    if let url = media.url {
                        attachments.append(.photo(url))
                    }
                case "video", "animated_gif":
                    if let previewImageUrl = media.previewImageUrl {
                        let videoUrl = media.variants?
                            .filter { $0.bitRate != nil }
                            .max { ($0.bitRate ?? 0) < ($1.bitRate ?? 0) }?
                            .url
                        attachments.append(.video(previewUrl: previewImageUrl, videoUrl: videoUrl))
                    }
                default:
                    break
                }
            }
        }

        let tweetText = rawTweet.noteTweet?.text.nonEmpty ?? rawTweet.text
        let referencedTweet = buildReferencedTweet(rawTweet: rawTweet)

        return Tweet(
            id: rawTweet.id,
            user: user,
            text: tweetText,
            date: rawTweet.date,
            attachments: attachments,
            referencedTweet: referencedTweet,
            publicMetrics: rawTweet.publicMetrics
        )
    }

    private func buildReferencedTweet(rawTweet: RawTweet) -> Tweet.ReferencedTweet? {
        guard
            let reference = rawTweet.referencedTweets?.first,
            let rawReferencedTweet = includes?.referencedTweets?.first(where: { $0.id == reference.id }),
            let authorId = rawReferencedTweet.authorId,
            let user = includes?.users?.first(where: { $0.id == authorId }),
            let referenceType = reference.referenceType
        else {
            return nil
        }

        return Tweet.ReferencedTweet(
            type: referenceType,
            user: user,
            text: rawReferencedTweet.noteTweet?.text.nonEmpty ?? rawReferencedTweet.text
        )
    }
}

extension TweetsPageResponse {
    struct Includes: Decodable {
        let media: [Media]?
        let users: [TwitterUser]?
        let referencedTweets: [RawTweet]?

        enum CodingKeys: String, CodingKey {
            case media
            case users
            case referencedTweets = "tweets"
        }
    }

    struct RawTweet: Decodable {
        let id: String
        let date: Date
        let authorId: String?
        let text: String
        let attachments: Attachments?
        let referencedTweets: [ReferencedTweet]?
        let publicMetrics: PublicMetrics?
        let noteTweet: NoteTweet?

        enum CodingKeys: String, CodingKey {
            case id
            case date = "created_at"
            case authorId = "author_id"
            case text
            case attachments
            case referencedTweets = "referenced_tweets"
            case publicMetrics = "public_metrics"
            case noteTweet = "note_tweet"
        }

        struct Attachments: Decodable {
            let mediaKeys: [String]?

            enum CodingKeys: String, CodingKey {
                case mediaKeys = "media_keys"
            }
        }

        struct PublicMetrics: Decodable {
            let retweetCount: Int
            let replyCount: Int
            let likeCount: Int
            let quoteCount: Int

            enum CodingKeys: String, CodingKey {
                case retweetCount = "retweet_count"
                case replyCount = "reply_count"
                case likeCount = "like_count"
                case quoteCount = "quote_count"
            }
        }

        struct NoteTweet: Decodable {
            let text: String
        }
    }

    struct Media: Decodable {
        let key: String
        let type: String
        let url: String?
        let previewImageUrl: String?
        let variants: [Variant]?

        enum CodingKeys: String, CodingKey {
            case key = "media_key"
            case type
            case url
            case previewImageUrl = "preview_image_url"
            case variants
        }

        struct Variant: Decodable {
            let bitRate: Int?
            let url: String?

            enum CodingKeys: String, CodingKey {
                case bitRate = "bit_rate"
                case url
            }
        }
    }

    struct ReferencedTweet: Decodable {
        let type: String
        let id: String

        var referenceType: Tweet.ReferenceType? {
            switch type {
            case "quoted": return .quoted
            case "retweeted": return .retweeted
            case "replied_to": return .replied
            default: return nil
            }
        }
    }
}

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}
