import BigInt
import Foundation
import UIKit

class SafeDappManagerViewModel: ObservableObject {
    private let service: SafeDappService

    @Published private(set) var dataState: DataStatus<[SafeDappViewItem]> = .loading
    @Published private(set) var items: [SafeDappViewItem] = []
    @Published var searchText = "" {
        didSet { applyFilter() }
    }
    @Published var operationState: SafeDappAsyncState = .idle
    @Published var openAlert: SafeDappOpenAlert?
    private var allItems: [SafeDappViewItem] = []
    private var loadTask: Task<Void, Never>?
    private var activeLoadID = UUID()

    var hasLoadedItems: Bool { !allItems.isEmpty }
    var isSearchResultEmpty: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && items.isEmpty
    }

    init(service: SafeDappService) {
        self.service = service
        load()
    }

    func load() {
        loadTask?.cancel()
        let loadID = UUID()
        activeLoadID = loadID
        dataState = .loading
        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let total = try await service.getMineNum()
                var ids: [BigUInt] = []
                var start = BigUInt.zero
                let pageSize = BigUInt(100)
                while start < total {
                    let count = min(pageSize, total - start)
                    ids.append(contentsOf: try await service.getMineIDs(start: start, count: count))
                    start += count
                }

                var loaded: [SafeDappViewItem] = []
                for id in ids {
                    let info = try await service.getInfo(id: id)
                    loaded.append(SafeDappViewItem(info: info))
                }

                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard self.activeLoadID == loadID else { return }
                    self.allItems = loaded
                    self.applyFilter()
                }

                for item in loaded {
                    loadLogo(id: item.info.id, loadID: loadID)
                }
            } catch {
                await MainActor.run {
                    guard self.activeLoadID == loadID, !Task.isCancelled else { return }
                    self.dataState = .failed(error)
                }
            }
        }
    }

    func loadLogo(id: BigUInt, loadID: UUID? = nil) {
        Task {
            do {
                let data = try await service.getLogo(id: id)
                let image = UIImage(data: data)
                await MainActor.run {
                    updateLogo(id: id, logo: image, loadID: loadID)
                }
            } catch {
                await MainActor.run {
                    updateLogo(id: id, logo: nil, loadID: loadID)
                }
            }
        }
    }

    @MainActor
    private func updateLogo(id: BigUInt, logo: UIImage?, loadID: UUID? = nil) {
        if let loadID, activeLoadID != loadID { return }
        guard let index = allItems.firstIndex(where: { $0.info.id == id }) else { return }
        allItems[index].logo = logo
        allItems[index].logoLoaded = true
        applyFilter()
    }

    private func applyFilter() {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if query.isEmpty {
            items = allItems
        } else {
            items = allItems.filter { item in
                [
                    item.info.id.description,
                    item.info.name,
                    item.info.keyword,
                    item.info.runUrl,
                    item.contractAddress,
                ]
                .map { $0.lowercased() }
                .contains { $0.contains(query) }
            }
        }
        dataState = .completed(items)
    }

    func prepareOpen(item: SafeDappViewItem) {
        Task {
            do {
                if try await service.isFrozen(id: item.info.id) {
                    await MainActor.run {
                        openAlert = .blocked(title: "safe_dapp.frozen".localized, message: "safe_dapp.frozen_message".localized)
                    }
                    return
                }
                var checkedItem = item
                if !checkedItem.logoLoaded {
                    if let data = try? await service.getLogo(id: checkedItem.info.id) {
                        checkedItem.logo = UIImage(data: data)
                    }
                    checkedItem.logoLoaded = true
                    await MainActor.run {
                        updateLogo(id: checkedItem.info.id, logo: checkedItem.logo)
                    }
                }
                await MainActor.run {
                    if checkedItem.info.fraudNum > 0 {
                        openAlert = .confirm(
                            title: "safe_dapp.fraud_warning".localized,
                            message: "safe_dapp.fraud_warning_message".localized(checkedItem.info.fraudNum.description),
                            url: checkedItem.info.runUrl
                        )
                    } else if checkedItem.logoMissing {
                        openAlert = .confirm(
                            title: "safe_dapp.logo_missing".localized,
                            message: "safe_dapp.logo_missing_message".localized,
                            url: checkedItem.info.runUrl
                        )
                    } else {
                        open(url: checkedItem.info.runUrl)
                    }
                }
            } catch {
                await MainActor.run {
                    openAlert = .blocked(title: "alert.error".localized, message: error.localizedDescription)
                }
            }
        }
    }

    func open(url: String) {
        MarketDappModule.open(rawUrl: url, tab: .SAFE)
    }

    func remove(item: SafeDappViewItem, onComplete: @escaping (SafeDappAsyncState) -> Void) {
        operationState = .sending
        Task {
            do {
                _ = try await service.remove(id: item.info.id)
                await MainActor.run {
                    operationState = .completed
                    onComplete(operationState)
                    load()
                }
            } catch {
                await MainActor.run {
                    operationState = .failed(error.localizedDescription)
                    onComplete(operationState)
                }
            }
        }
    }
}

extension SafeDappManagerViewModel {
    struct DetailViewType: Hashable {
        let kind: Kind
        let viewModel: AnyObject

        enum Kind: Hashable {
            case edit
            case logo
        }

        static func == (lhs: DetailViewType, rhs: DetailViewType) -> Bool {
            lhs.kind == rhs.kind && lhs.viewModel === rhs.viewModel
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(kind)
            hasher.combine(ObjectIdentifier(viewModel))
        }
    }
}

struct SafeDappOpenAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let url: String?

    static func blocked(title: String, message: String) -> SafeDappOpenAlert {
        SafeDappOpenAlert(title: title, message: message, url: nil)
    }

    static func confirm(title: String, message: String, url: String) -> SafeDappOpenAlert {
        SafeDappOpenAlert(title: title, message: message, url: url)
    }
}
