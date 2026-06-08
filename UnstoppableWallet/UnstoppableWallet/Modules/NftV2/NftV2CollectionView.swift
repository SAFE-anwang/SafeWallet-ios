import SwiftUI
import UIKit

private struct NftV2RemoteImage: View {
    let url: String?
    let placeholder: String
    var size: CGSize? = nil

    var body: some View {
        ThemeImage(
            ComponentImage.remote(url: url ?? "", placeholder: placeholder, size: size),
            size: size as CGSize?,
            colorStyle: nil
        )
    }
}

struct NftV2CollectionView: View {
    let collection: NftV2Collection
    let currentCollection: () -> NftV2Collection?
    let isFavorite: () -> Bool
    let sendCapability: (NftV2Asset) -> NftV2SendCapability
    let onRequestSendCapabilityRefresh: (NftV2Asset) -> Void
    let isSending: (NftV2Asset) -> Bool
    let onToggleFavorite: () -> Void
    let onSend: (NftV2Asset) async -> Void
    let onRefresh: () async -> Void

    @Environment(\.openURL) private var openURL
    @State private var visibleCount = 24
    @State private var displayedItems = [NftV2Asset]()
    @State private var favoriteState = false

    private static let pageSize = 24

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    private var visibleItems: [NftV2Asset] {
        Array(displayedItems.prefix(visibleCount))
    }

    private var effectiveCollection: NftV2Collection {
        currentCollection() ?? NftV2Collection(
            id: collection.id,
            chain: collection.chain,
            contractAddress: collection.contractAddress,
            name: collection.name,
            imageUrl: collection.imageUrl,
            market: collection.market,
            marketUrl: collection.marketUrl,
            items: []
        )
    }

    private var hasMore: Bool {
        visibleCount < displayedItems.count
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                headerCard
                assetsSection
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .refreshable {
            await onRefresh()
            syncDisplayedItems()
        }
        .onAppear {
            if displayedItems.isEmpty {
                syncDisplayedItems()
            }

            favoriteState = isFavorite()
        }
        .onChange(of: effectiveCollection) { _ in
            syncDisplayedItems()
        }
        .background(Color.themeLawrence.ignoresSafeArea())
        .navigationTitle("nft_v2.asset_detail.title".localized)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    onToggleFavorite()
                    favoriteState.toggle()
                } label: {
                    Image("filled_star_24").themeIcon(color: favoriteState ? .themeYellow : .themeLightGray)
                        
                }
            }
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                ThemeImage(
                    ComponentImage.remote(url: collection.imageUrl ?? "", placeholder: "placeholder_nft_32", size: nil),
                    size: CGSize(width: 72, height: 72)
                )
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                VStack(alignment: .leading, spacing: 8) {
                    ThemeText(collection.name, style: .headline1)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 8) {
                        BadgeViewNew(effectiveCollection.items.first?.standard ?? "nft_v2.asset.standard".localized, mode: .transparent, colorStyle: .secondary)

                        ThemeText(effectiveCollection.contractAddress.shortened, style: .subhead, colorStyle: .secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                Button {
                    CopyHelper.copyAndNotify(value: collection.contractAddress)
                } label: {
                    ThemeImage("copy_20", size: 20, colorStyle: .secondary)
                        .frame(width: 32, height: 32)
                        .background(Color.themeBlade)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            if let description = collectionDescription {
                Divider()

                ThemeText(description, style: .subhead, colorStyle: .secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            HStack(spacing: 12) {
                statItem(title: "nft_v2.collection.floor_price".localized, value: "0")
                statItem(title: "nft_v2.collection.average_price".localized, value: "0")
                statItem(title: "nft_v2.collection.volume".localized, value: "0")
            }
        }
        .padding(16)
        .background(Color.themeTyler)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    @ViewBuilder
    private var assetsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            ThemeText("nft_v2.section.assets".localized, style: .headline1)

            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(visibleItems) { asset in
                    NavigationLink(
                        destination: NftV2AssetDetailView(
                            asset: asset,
                            collection: collection,
                            currentSendCapability: { sendCapability(asset) },
                            isSending: { isSending(asset) },
                            onRefreshCapability: { onRequestSendCapabilityRefresh(asset) },
                            onSend: { await onSend(asset) }
                        )
                    ) {
                        assetCard(asset: asset)
                    }
                    .buttonStyle(.plain)
                    .onAppear {
                        if asset.id == visibleItems.last?.id {
                            loadMoreIfNeeded()
                        }
                    }
                }
            }

            if displayedItems.isEmpty {
                ThemeText("nft_v2.empty.title".localized, style: .captionSB, colorStyle: .secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(Color.themeTyler)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }

            if hasMore {
                Button {
                    loadMore()
                } label: {
                    ThemeText("nft_v2.collection.load_more".localized, style: .subhead, colorStyle: .secondary)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
            }
        }
    }

    private func loadMoreIfNeeded() {
        guard hasMore else {
            return
        }
        loadMore()
    }

    private func loadMore() {
        guard hasMore else {
            return
        }
        visibleCount = min(visibleCount + Self.pageSize, displayedItems.count)
    }

    private func syncDisplayedItems() {
        displayedItems = effectiveCollection.items
        visibleCount = min(max(visibleCount, Self.pageSize), displayedItems.count)
    }

    @ViewBuilder
    private func assetCard(asset: NftV2Asset) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle()
                .fill(Color.themeBlade)
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    NftV2RemoteImage(url: asset.imageUrl, placeholder: "placeholder_nft_32")
                        .aspectRatio(1, contentMode: .fill)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                }
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(alignment: .bottomTrailing) {
                    if asset.balance > 1 {
                        ThemeText("nft_v2.asset.balance".localized(asset.balance), style: .captionSB)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(Color.black.opacity(0.55))
                            .clipShape(Capsule(style: .continuous))
                            .padding(10)
                    }
                }

            VStack(alignment: .leading, spacing: 4) {
                ThemeText(asset.name, style: .headline2)
                    .lineLimit(1)
                ThemeText("#\(asset.tokenId)", style: .subhead, colorStyle: .secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
        }
        .background(Color.themeTyler)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    @ViewBuilder
    private func statItem(title: String, value: String) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                if collection.chain == .binanceSmartChain {
                    ThemeImage("binanceSmartChain_trx_32", size: 18)
                }

                ThemeText(value, style: .headline2)
            }

            ThemeText(title, style: .caption, colorStyle: .secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private var collectionDescription: String? {
        if let provided = NftV2CollectionContentProvider.collectionDescription(collectionName: collection.name) {
            return provided
        }

        let candidate = collection.items.first?.collectionName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let candidate, !candidate.isEmpty, candidate != collection.name else {
            return nil
        }

        return candidate
    }
}

private struct NftV2AssetDetailView: View {
    let asset: NftV2Asset
    let collection: NftV2Collection
    let currentSendCapability: () -> NftV2SendCapability
    let isSending: () -> Bool
    let onRefreshCapability: () -> Void
    let onSend: () async -> Void

    @Environment(\.openURL) private var openURL
    @State private var isSendingValidation = false
    @State private var liveSendCapability: NftV2SendCapability = .checking
    @State private var sendValidationTask: Task<Void, Never>?
    @State private var capabilityObserverTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    imageSection
                    marketSection
                    detailSection
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }

            if asset.canSend {
                sendButton
            }
        }
        .onAppear {
            isSendingValidation = false
            startCapabilityObservation(triggerRefresh: true)
        }
        .onDisappear {
            sendValidationTask?.cancel()
            capabilityObserverTask?.cancel()
            sendValidationTask = nil
            capabilityObserverTask = nil
            isSendingValidation = false
        }
        .background(Color.themeLawrence.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                ThemeText("nft_v2.asset_detail.title".localized, style: .headline1)
            }

            ToolbarItem(placement: .primaryAction) {
                Menu {
                    if let marketUrl = asset.marketUrl, let url = URL(string: marketUrl) {
                        Button("button.view".localized) {
                            openURL(url)
                        }
                    }

                    Button("button.copy".localized) {
                        CopyHelper.copyAndNotify(value: asset.contractAddress)
                    }
                } label: {
                    ThemeImage("more_20", size: 20, colorStyle: .primary)
                }
            }
        }
    }

    private var imageSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            NftV2RemoteImage(url: asset.imageUrl, placeholder: "placeholder_nft_32")
            .aspectRatio(1, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .background(Color.themeTyler)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))

            ThemeText(asset.name, style: .title2)
                .lineLimit(2)
        }
    }

    @ViewBuilder
    private var marketSection: some View {
        if let marketUrl = asset.marketUrl, let url = URL(string: marketUrl) {
            Button {
                openURL(url)
            } label: {
                HStack(spacing: 12) {
                    ThemeImage(
                        ComponentImage.remote(url: collection.imageUrl ?? "", placeholder: "placeholder_nft_32", size: nil),
                        size: CGSize(width: 48, height: 48)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                    VStack(alignment: .leading, spacing: 4) {
                        ThemeText(collection.name, style: .headline2)
                            .lineLimit(1)
                        ThemeText("nft_v2.asset.floor_price".localized("0 BNB", "$0"), style: .subhead, colorStyle: .secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    ThemeImage("arrow_right_20", size: 20, colorStyle: .secondary)
                }
                .padding(16)
                .background(Color.themeTyler)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    private var detailSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            ThemeText("nft_v2.section.details".localized, style: .headline1)

            VStack(spacing: 0) {
                detailRow(title: "nft_v2.asset.contract".localized, value: asset.contractAddress.shortened, copyValue: asset.contractAddress)
                detailRow(title: "nft_v2.asset.token_id".localized, value: asset.tokenId)
                detailRow(title: "nft_v2.asset.standard_label".localized, value: asset.standard)
                detailRow(title: "nft_v2.asset.network".localized, value: asset.chain.title, isLast: true)
            }
            .background(Color.themeTyler)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
    }

    private var sendButton: some View {
        VStack(spacing: 0) {
            Divider()
            Group {
                if !asset.canSend {
                    ThemeButton(text: "nft_v2.send.unavailable".localized, style: .secondary, mode: .transparent) {}
                        .disabled(true)
                } else if isSendingValidation || isSending() {
                    ThemeButton(text: "send.confirmation.sending".localized, style: .secondary, mode: .transparent) {}
                        .disabled(true)
                } else if liveSendCapability.isReady {
                    ThemeButton(text: "balance.send".localized) {
                        triggerSend()
                    }
                } else {
                    ThemeButton(text: "balance.send".localized) {
                        triggerSend()
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 20)
        }
        .background(Color.themeLawrence)
    }

    private func triggerSend() {
        guard !isSendingValidation, !isSending() else {
            return
        }

        isSendingValidation = true
        refreshCapability(triggerRefresh: true)

        sendValidationTask?.cancel()
        sendValidationTask = Task {
            await onSend()
            await MainActor.run {
                isSendingValidation = false
                sendValidationTask = nil
                startCapabilityObservation(triggerRefresh: false)
            }
        }
    }

    private func refreshCapability(triggerRefresh: Bool) {
        if triggerRefresh {
            onRefreshCapability()
        }

        let latest = currentSendCapability()
        if latest != liveSendCapability {
            liveSendCapability = latest
        }
    }

    private func startCapabilityObservation(triggerRefresh: Bool) {
        capabilityObserverTask?.cancel()
        refreshCapability(triggerRefresh: triggerRefresh)

        capabilityObserverTask = Task {
            for _ in 0 ..< 60 {
                guard !Task.isCancelled else {
                    return
                }

                try? await Task.sleep(nanoseconds: 250_000_000)

                let shouldStop = await MainActor.run {
                    refreshCapability(triggerRefresh: false)
                    return liveSendCapability != .checking && !isSendingValidation
                }

                if shouldStop {
                    break
                }
            }
        }
    }

    @ViewBuilder
    private func detailRow(title: String, value: String, copyValue: String? = nil, isLast: Bool = false) -> some View {
        HStack(spacing: 12) {
            ThemeText(title, style: .subhead, colorStyle: .secondary)
            Spacer()

            ThemeText(value, style: .subheadSB)
                .lineLimit(1)
                .truncationMode(.middle)

            if let copyValue {
                Button {
                    CopyHelper.copyAndNotify(value: copyValue)
                } label: {
                    ThemeImage("copy_20", size: 18, colorStyle: .secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) {
            if !isLast {
                Divider().padding(.leading, 16)
            }
        }
    }
}
