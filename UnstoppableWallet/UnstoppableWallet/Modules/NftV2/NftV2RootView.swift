import SwiftUI

private struct NftV2RootRemoteImage: View {
    let url: String?
    let placeholder: String
    let size: CGSize

    var body: some View {
        ThemeImage(
            ComponentImage.remote(url: url ?? "", placeholder: placeholder, size: size),
            size: size,
            colorStyle: nil
        )
    }
}

struct NftV2RootView: View {
    @Environment(\.openURL) private var openURL
    @StateObject var viewModel: NftV2ViewModel
    @State private var path = NavigationPath()
    @State private var presentedSendController: NftV2PresentedController?
    @State private var sendingAsset: NftV2Asset?
    @State private var collapsedChains = Set<NftV2Chain>()
    @Binding var isPresented: Bool
    
    var body: some View {
        ThemeNavigationStack(path: $path) {
            ThemeView(style: .list) {
                VStack(spacing: 0) {
                    header

                    switch viewModel.state {
                    case .idle, .loading:
                        loadingView
                    case let .failed(message):
                        failureView(message: message)
                    case .loaded:
                        contentView
                    }
                }
            }
            .navigationTitle("nft_collections.title".localized)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: close) {
                        Image("close")
                    }
                }

//                ToolbarItem(placement: .primaryAction) {
//                    Button {
//                        viewModel.reload()
//                    } label: {
//                        Image("reset")
//                    }
//                }
            }
            .navigationDestination(for: NftV2Collection.self) { collection in
                NftV2CollectionView(
                    collection: collection,
                    isFavorite: { viewModel.isFavorite(collection: collection) },
                    sendCapability: { asset in
                        viewModel.sendCapability(asset: asset)
                    },
                    onRequestSendCapabilityRefresh: { asset in
                        viewModel.refreshSendCapabilityIfNeeded(asset: asset)
                    },
                    isSending: { asset in
                        viewModel.isSending(asset: asset)
                    },
                    onToggleFavorite: { viewModel.toggleFavorite(collection: collection) },
                    onSend: { asset in
                        guard !viewModel.isSending(asset: asset) else {
                            return
                        }

                        viewModel.markSending(asset: asset, sending: true)
                        sendingAsset = asset

                        let controller = await viewModel.validatedSendController(
                            asset: asset,
                            collection: collection,
                            onSendSuccess: { asset, collection, transactionHash, amount in
                                viewModel.handleSendSuccess(asset: asset, collection: collection, transactionHash: transactionHash, amount: amount)
                            },
                            onSendFailed: { _ in }
                        )
                        await MainActor.run {
                            presentedSendController = controller.map(NftV2PresentedController.init)

                            if presentedSendController == nil {
                                viewModel.markSending(asset: asset, sending: false)
                                sendingAsset = nil
                                HudHelper.instance.show(banner: .error(string: viewModel.sendValidationMessage(asset: asset)))
                            }
                        }
                    }, onRefresh: {
                        await MainActor.run {
                            viewModel.reload()
                        }
                    }
                )
            }
            .sheet(item: $presentedSendController, onDismiss: {
                presentedSendController = nil

                guard let asset = sendingAsset else {
                    return
                }

                viewModel.completeSendPresentation(asset: asset)
                sendingAsset = nil
            }) { presented in
                NftV2LegacyWrapperView(controller: presented.controller)
                    .ignoresSafeArea()
            }
            .onAppear {
                viewModel.onAppear()
            }
            .onDisappear {
                viewModel.onDisappear()
            }
        }
    }

    private func close() {
        if let asset = sendingAsset {
            viewModel.markSending(asset: asset, sending: false)
            sendingAsset = nil
        }

        presentedSendController = nil
        path = NavigationPath()

        if isPresented {
            DispatchQueue.main.async {
                isPresented = false
            }
        }
    }

    private var header: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Picker("nft_v2.filter.title".localized, selection: $viewModel.filter) {
                    ForEach(NftV2ViewModel.Filter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
            ThemeText("nft_v2.loading".localized, style: .subheadSB, colorStyle: .secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func failureView(message: String) -> some View {
        PlaceholderViewNew(icon: "warning_filled", title: "nft_v2.error.title".localized, subtitle: message) {
            ThemeButton(text: "nft_v2.action.retry".localized) {
                viewModel.reload()
            }
        }
    }

    private var contentView: some View {
        ThemeList(bottomSpacing: 16) {
            ForEach(viewModel.chainSections) { section in
                Section {
                    if !isCollapsed(section.chainState.chain) {
                        ForEach(section.pendingTransfers) { pending in
                            pendingRow(pending)
                        }

                        ForEach(section.collections) { collection in
                            Button {
                                path.append(collection)
                            } label: {
                                collectionRow(collection: collection)
                            }
                            .buttonStyle(CellButtonStyle())
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button {
                                    viewModel.toggleFavorite(collection: collection)
                                } label: {
                                    Image(viewModel.isFavorite(collection: collection) ? "star_filled_20" : "star_20")
                                }
                                .tint(.themeRemus)
                            }
                        }

                        if section.collections.isEmpty && (viewModel.filter != .favorites || section.pendingTransfers.isEmpty) {
                            emptyCollectionsRow
                        }
                    }
                } header: {
                    sectionHeader(section.chainState.chain.title, chainState: section.chainState, chain: section.chainState.chain)
                }
            }

            if !viewModel.hasVisibleContent {
                Section {
                    emptyCollectionsRow
                }
            }
        }
    }

    @ViewBuilder
    private func collectionRow(collection: NftV2Collection) -> some View {
        HStack(spacing: 12) {
            NftV2RootRemoteImage(
                url: collection.imageUrl,
                placeholder: "placeholder_nft_32",
                size: CGSize(width: 44, height: 44)
            )
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                ThemeText(collection.name, style: .subheadSB)
                    .lineLimit(1)

                ThemeText("nft_v2.collection.items".localized(collection.chain.title, collection.count), style: .captionSB, colorStyle: .secondary)
                    .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                if let market = collection.market {
                    ThemeText(market.title, style: .captionSB, colorStyle: .secondary)
                }

                if viewModel.isFavorite(collection: collection) {
                    Image("star_filled_20")
                }
            }
        }
        .padding(16)
    }

    private var emptyCollectionsRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            ThemeText(
                viewModel.filter == .favorites ? "nft_v2.empty.favorites.title".localized : "nft_v2.empty.title".localized,
                style: .captionSB,
                colorStyle: .secondary
            )
        }
        .padding(16)
    }

    @ViewBuilder
    private func pendingRow(_ pending: NftV2PendingTransferItem) -> some View {
        Button {
            if let urlString = pending.explorerUrl, let url = URL(string: urlString) {
                openURL(url)
            }
        } label: {
            HStack(spacing: 12) {
                NftV2RootRemoteImage(
                    url: pending.asset.imageUrl,
                    placeholder: "placeholder_nft_32",
                    size: CGSize(width: 44, height: 44)
                )
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(alignment: .topTrailing) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: Color.white))
                        .padding(4)
                        .background(Color.black.opacity(0.55))
                        .clipShape(Circle())
                        .offset(x: 4, y: -4)
                }

                VStack(alignment: .leading, spacing: 4) {
                    ThemeText(pending.asset.name, style: .subheadSB)
                        .lineLimit(1)

                    ThemeText("nft_v2.pending.subtitle".localized(pending.amount), style: .captionSB, colorStyle: .secondary)
                        .lineLimit(1)
                }

                Spacer()

                ThemeText("nft_v2.pending.title".localized, style: .captionSB, colorStyle: .secondary)
            }
            .padding(16)
            .background(Color.themeTyler)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func sectionHeader(_ title: String, chainState: NftV2ChainState?, chain: NftV2Chain? = nil) -> some View {
        HStack(spacing: 0) {
            Button {
                if let chain {
                    toggleCollapse(chain)
                }
            } label: {
                HStack(spacing: 12) {
                    ThemeText(title, style: .subheadSB)
                    Spacer()
                    HStack(spacing: 8) {
                        if let chainState, chainState.isSyncing {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: Color.themeGray))
                                .scaleEffect(0.8)
                                .frame(width: 16, height: 16)
                        }

                        if let chainState {
                            let rightText = headerRightText(chainState: chainState)
                            if !rightText.isEmpty {
                                ThemeText(rightText, style: .captionSB, colorStyle: .secondary)
                            }
                        }

                        if let chain {
                            ThemeImage(
                                isCollapsed(chain) ? "arrow_small_down_20" : "arrow_small_forward_20",
                                size: 20,
                                colorStyle: .secondary
                            )
                        }
                    }
                    .frame(minWidth: 70, alignment: .trailing)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.themeTyler)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.themeJeremy, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(chain == nil)
        }
        .padding(.horizontal, 16)
        .padding(.top, 24)
        .padding(.bottom, {
            guard let chain else { return 10 }
            return isCollapsed(chain) ? 12 : 6
        }())
        .background(Color.themeLawrence)
        .listRowInsets(EdgeInsets())
    }

    private func isCollapsed(_ chain: NftV2Chain) -> Bool {
        collapsedChains.contains(chain)
    }

    private func headerRightText(chainState: NftV2ChainState) -> String {
        if viewModel.filter == .favorites {
            let favoriteCount = viewModel.favoriteCount(chain: chainState.chain)
            return favoriteCount == 0 ? "" : "nft_v2.state.items_count".localized(favoriteCount)
        }

        return chainState.badgeText
    }

    private func toggleCollapse(_ chain: NftV2Chain) {
        if collapsedChains.contains(chain) {
            collapsedChains.remove(chain)
        } else {
            collapsedChains.insert(chain)
        }
    }
}

private struct NftV2PresentedController: Identifiable {
    let controller: UIViewController
    let id = UUID()
}
