import Kingfisher
import SwiftUI

struct CoinTweetsView: View {
    @ObservedObject var viewModel: CoinTweetsViewModel

    var body: some View {
        ThemeView(style: .list) {
            switch viewModel.state {
            case .loading:
                ProgressView()
            case let .loaded(viewItems):
                if viewItems.isEmpty {
                    PlaceholderViewNew(icon: "no_tweets_48", subtitle: "coin_tweets.no_tweets_yet".localized)
                } else {
                    list(viewItems: viewItems)
                }
            case .notAvailable:
                PlaceholderViewNew(icon: "no_tweets_48", subtitle: "coin_tweets.not_available".localized)
            case .failed:
                SyncErrorView {
                    viewModel.onRetry()
                }
            }
        }
        .refreshable {
            viewModel.refresh()
        }
    }

    @ViewBuilder private func list(viewItems: [CoinTweetsViewModel.TweetViewItem]) -> some View {
        ScrollView {
            LazyVStack(spacing: .margin12) {
                ForEach(viewItems) { viewItem in
                    tweetCell(viewItem: viewItem)
                }

                if let twitterPageUrl = viewModel.twitterPageUrl {
                    ThemeButton(text: "coin_tweets.see_on_twitter".localized, style: .secondary, size: .medium) {
                        Coordinator.shared.present(url: twitterPageUrl)
                    }
                    .padding(.top, .margin12)
                }
            }
            .padding(EdgeInsets(top: .margin12, leading: .margin16, bottom: .margin32, trailing: .margin16))
        }
    }

    @ViewBuilder private func tweetCell(viewItem: CoinTweetsViewModel.TweetViewItem) -> some View {
        ListSection {
            ClickableRow(padding: EdgeInsets(top: .margin16, leading: .margin16, bottom: .margin16, trailing: .margin16)) {
                Coordinator.shared.present(url: viewItem.url)
            } content: {
                VStack(alignment: .leading, spacing: .margin12) {
                    HStack(spacing: .margin12) {
                        KFImage.url(URL(string: viewItem.titleImageUrl))
                            .resizable()
                            .placeholder { Circle().fill(Color.themeBlade) }
                            .clipShape(Circle())
                            .frame(width: .iconSize32, height: .iconSize32)

                        MultiText(title: viewItem.title, subtitle: viewItem.subtitle)
                    }

                    Text(viewItem.text)
                        .themeSubhead2()
                        .fixedSize(horizontal: false, vertical: true)

                    if !viewItem.attachments.isEmpty {
                        attachments(viewItem.attachments)
                    }

                    if let referencedTweet = viewItem.referencedTweet {
                        referencedTweetView(viewItem: referencedTweet)
                    }

                    if let metrics = viewItem.metrics {
                        metricsView(viewItem: metrics)
                    }

                    Text(viewItem.date).themeMicro(color: .themeGray50)
                }
            }
        }
    }

    @ViewBuilder private func attachments(_ attachments: [Tweet.Attachment]) -> some View {
        VStack(spacing: .margin8) {
            ForEach(Array(attachments.enumerated()), id: \.offset) { _, attachment in
                switch attachment {
                case let .photo(url):
                    mediaImage(url: url)
                case let .video(previewUrl, _):
                    ZStack {
                        mediaImage(url: previewUrl)

                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 44))
                            .foregroundColor(.white)
                            .shadow(radius: 8)
                    }
                }
            }
        }
    }

    @ViewBuilder private func mediaImage(url: String) -> some View {
        KFImage.url(URL(string: url))
            .resizable()
            .placeholder { RoundedRectangle(cornerRadius: .cornerRadius12).fill(Color.themeBlade) }
            .scaledToFill()
            .frame(maxWidth: .infinity)
            .frame(height: 180)
            .clipShape(RoundedRectangle(cornerRadius: .cornerRadius12))
    }

    @ViewBuilder private func referencedTweetView(viewItem: CoinTweetsViewModel.ReferencedTweetViewItem) -> some View {
        VStack(alignment: .leading, spacing: .margin6) {
            Text(viewItem.title).themeCaptionSB(color: .themeGray)
            Text(viewItem.text)
                .themeSubhead2()
                .lineLimit(4)
        }
        .padding(.margin12)
        .background(Color.themeLawrence)
        .clipShape(RoundedRectangle(cornerRadius: .cornerRadius12))
    }

    @ViewBuilder private func metricsView(viewItem: CoinTweetsViewModel.MetricsViewItem) -> some View {
        HStack(spacing: .margin16) {
            metric(systemImage: "bubble.left", value: viewItem.replies)
            metric(systemImage: "arrow.2.squarepath", value: viewItem.retweets)
            metric(systemImage: "heart", value: viewItem.likes)
            metric(systemImage: "quote.bubble", value: viewItem.quotes)
        }
    }

    @ViewBuilder private func metric(systemImage: String, value: String) -> some View {
        HStack(spacing: .margin4) {
            Image(systemName: systemImage)
                .font(.caption)
            Text(value)
        }
        .foregroundColor(.themeGray)
        .font(.caption)
    }
}
