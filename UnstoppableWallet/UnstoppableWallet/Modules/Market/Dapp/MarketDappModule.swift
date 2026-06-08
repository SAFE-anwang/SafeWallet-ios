import Foundation
import MarketKit
import RxSwift
import SwiftUI
import UIKit

struct MarketDappModule {
//    static func viewModel() -> MarketDappViewModel {
//        let dappProvider = MarketDappProvider(networkManager: Core.shared.networkManager)
//        let service = MarketDappService(provider: dappProvider)
//        let viewModel = MarketDappViewModel(service: service)
//        return viewModel
//    }
}

struct MarketDappListView: UIViewControllerRepresentable {
    typealias UIViewControllerType = UIViewController
    let tab: MarketDappModule.Tab
    func makeUIViewController(context _: Context) -> UIViewController {
        // TODO: must provide any VC
        let dappProvider = MarketDappProvider(networkManager: Core.shared.networkManager)
        let service = MarketDappService(provider: dappProvider, currentTab: tab)
        let viewModel = MarketDappListViewModel(service: service)
        return MarketDappListViewController(viewModel: viewModel, tab: tab)
    }

    func updateUIViewController(_: UIViewController, context _: Context) {}
}

extension MarketDappModule {
    static func normalizedUrl(from rawUrl: String) -> URL? {
        let trimmedUrl = rawUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedUrl.isEmpty else {
            return nil
        }

        let preparedUrl = trimmedUrl.contains("://") ? trimmedUrl : "https://\(trimmedUrl)"

        guard
            let url = URL(string: preparedUrl),
            let scheme = url.scheme?.lowercased(),
            ["http", "https"].contains(scheme),
            let host = url.host,
            !host.isEmpty
        else {
            return nil
        }

        return url
    }

    static func open(rawUrl: String, tab: Tab) {
        guard let url = normalizedUrl(from: rawUrl) else {
            print("[DApp] ERROR: Invalid URL: \(rawUrl)")
            return
        }

        open(url: url, tab: tab)
    }

    static func open(url: URL, tab: Tab) {
        print("[DApp] INFO: Opening DApp URL: \(url.absoluteString)")

        let connectInfo = connectInfo(tab: tab)

        Coordinator.shared.present(type: .alert) { isPresented in
            MarketDappBrowserView(url: url, connectInfo: connectInfo, onClose: {
                isPresented.wrappedValue = false
            })
        }
    }

    private static func connectInfo(tab: Tab) -> MarketDappBrowserConnectInfo? {
        guard let account = Core.shared.accountManager.activeAccount else {
            print("[DApp] WARNING: No active account, connectInfo will be nil")
            return nil
        }

        print("[DApp] INFO: Active account found: \(account.name)")

        let blockchainType = blockchainType(tab: tab)

        guard
            let chain = try? Core.shared.evmBlockchainManager.chain(blockchainType: blockchainType),
            let evmKitWrapper = try? Core.shared.evmBlockchainManager
                .evmKitManager(blockchainType: blockchainType)
                .evmKitWrapper(account: account, blockchainType: blockchainType)
        else {
            print("[DApp] WARNING: Failed to create evmKitWrapper, connectInfo will be nil")
            return nil
        }

        let address = evmKitWrapper.evmKit.receiveAddress.eip55
        print("[DApp] INFO: ConnectInfo created - chainId: \(chain.id), address: \(address)")
        return MarketDappBrowserConnectInfo(chainId: chain.id, address: address)
    }

    private static func blockchainType(tab: Tab) -> BlockchainType {
        switch tab {
        case .ALL, .ETH:
            print("[DApp] INFO: Using Ethereum chain")
            return .ethereum
        case .BSC:
            print("[DApp] INFO: Using BSC chain")
            return .binanceSmartChain
        case .SAFE:
            print("[DApp] INFO: Using SAFE chain")
            return .safe4
        }
    }
}

final class UrlRiskChecker: ObservableObject {
    private let provider = WhitelistDappProvider(networkManager: Core.shared.networkManager)
    private let securityManager = Core.shared.securityManager
    private let disposeBag = DisposeBag()

    private var trustedDomains = Set<String>()
    private var whitelistState: WhitelistState = .loading

    init() {
        loadWhitelist()
    }

    func check(url: URL) -> Result {
        guard securityManager.scamProtectionEnabled else {
            return .disabled
        }

        guard let host = Self.normalizedHost(url.host) else {
            return .risky
        }

        return check(host: host)
    }

    func check(enode: String) -> Result {
        guard securityManager.scamProtectionEnabled else {
            return .disabled
        }

        guard let host = Self.host(fromEnode: enode) else {
            return .risky
        }

        if Self.isIpv4(host) {
            return .secure
        }

        return check(host: host)
    }

    func check(host: String) -> Result {
        guard securityManager.scamProtectionEnabled else {
            return .disabled
        }

        guard let normalizedHost = Self.normalizedHost(host) else {
            return .risky
        }

        if Self.isTrusted(host: normalizedHost, trustedDomains: trustedDomains) {
            return .secure
        }

        if Self.isSuspicious(host: normalizedHost, trustedDomains: trustedDomains) {
            return .risky
        }

        switch whitelistState {
        case .loading, .error:
            return .notAvailable
        case .loaded:
            return .risky
        }
    }

    private func loadWhitelist() {
        provider.whitelistDapps()
            .subscribeOn(ConcurrentDispatchQueueScheduler(qos: .userInitiated))
            .observeOn(MainScheduler.instance)
            .subscribe(
                onSuccess: { [weak self] dApps in
                    self?.trustedDomains = Set(dApps.compactMap { Self.normalizedDomain($0.url) })
                    self?.whitelistState = .loaded
                },
                onError: { [weak self] _ in
                    self?.trustedDomains = []
                    self?.whitelistState = .error
                }
            )
            .disposed(by: disposeBag)
    }

    private static func normalizedDomain(_ rawValue: String) -> String? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        if let components = URLComponents(string: trimmed), let host = components.host {
            return normalizedHost(host)
        }

        if let components = URLComponents(string: "https://\(trimmed)"), let host = components.host {
            return normalizedHost(host)
        }

        return normalizedHost(trimmed)
    }

    private static func normalizedHost(_ rawHost: String?) -> String? {
        guard let rawHost else {
            return nil
        }

        let host = rawHost
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))

        guard !host.isEmpty else {
            return nil
        }

        return host
    }

    private static func host(fromEnode enode: String) -> String? {
        guard
            let separatorIndex = enode.lastIndex(of: "@")
        else {
            return nil
        }

        let hostPortPart = enode[enode.index(after: separatorIndex)...]
        guard
            let portSeparatorIndex = hostPortPart.lastIndex(of: ":")
        else {
            return nil
        }

        let host = String(hostPortPart[..<portSeparatorIndex])
        return normalizedHost(host)
    }

    private static func isIpv4(_ host: String) -> Bool {
        let regex = #"^((25[0-5]|2[0-4]\d|1?\d?\d)\.){3}(25[0-5]|2[0-4]\d|1?\d?\d)$"#
        return NSPredicate(format: "SELF MATCHES %@", regex).evaluate(with: host)
    }

    private static func isTrusted(host: String, trustedDomains: Set<String>) -> Bool {
        trustedDomains.contains { trustedDomain in
            host == trustedDomain || host.hasSuffix(".\(trustedDomain)")
        }
    }

    private static func isSuspicious(host: String, trustedDomains: Set<String>) -> Bool {
        if host.contains("xn--") {
            return true
        }

        guard
            let candidateRoot = registrableDomainApprox(from: host),
            let candidateParts = domainParts(from: candidateRoot)
        else {
            return false
        }

        for trustedDomain in trustedDomains {
            guard
                let trustedRoot = registrableDomainApprox(from: trustedDomain),
                let trustedParts = domainParts(from: trustedRoot),
                candidateParts.tld == trustedParts.tld
            else {
                continue
            }

            let candidateSkeleton = skeleton(candidateParts.label)
            let trustedSkeleton = skeleton(trustedParts.label)

            if candidateSkeleton == trustedSkeleton, candidateParts.label != trustedParts.label {
                return true
            }

            let distance = levenshteinDistance(candidateParts.label, trustedParts.label)
            if distance > 0, distance <= 2 {
                return true
            }
        }

        return false
    }

    private static func registrableDomainApprox(from host: String) -> String? {
        let labels = host.split(separator: ".").map(String.init)
        guard labels.count >= 2 else {
            return nil
        }

        return labels.suffix(2).joined(separator: ".")
    }

    private static func domainParts(from domain: String) -> (label: String, tld: String)? {
        let components = domain.split(separator: ".").map(String.init)
        guard components.count == 2 else {
            return nil
        }

        return (label: components[0], tld: components[1])
    }

    private static func skeleton(_ value: String) -> String {
        value.map { character in
            switch character {
            case "0": return "o"
            case "1", "l", "i": return "i"
            case "3": return "e"
            case "5": return "s"
            case "7": return "t"
            default: return character
            }
        }
        .reduce(into: "") { $0.append($1) }
    }

    private static func levenshteinDistance(_ lhs: String, _ rhs: String) -> Int {
        let lhsChars = Array(lhs)
        let rhsChars = Array(rhs)

        guard !lhsChars.isEmpty else {
            return rhsChars.count
        }

        guard !rhsChars.isEmpty else {
            return lhsChars.count
        }

        var distances = Array(0...rhsChars.count)

        for (lhsIndex, lhsChar) in lhsChars.enumerated() {
            var previousDiagonal = distances[0]
            distances[0] = lhsIndex + 1

            for (rhsIndex, rhsChar) in rhsChars.enumerated() {
                let current = distances[rhsIndex + 1]

                if lhsChar == rhsChar {
                    distances[rhsIndex + 1] = previousDiagonal
                } else {
                    distances[rhsIndex + 1] = min(
                        previousDiagonal + 1,
                        distances[rhsIndex] + 1,
                        current + 1
                    )
                }

                previousDiagonal = current
            }
        }

        return distances[rhsChars.count]
    }
}

extension UrlRiskChecker {
    enum Result {
        case secure
        case risky
        case notAvailable
        case disabled
    }

    private enum WhitelistState {
        case loading
        case loaded
        case error
    }
}

extension MarketDappModule {
    
    enum Tab: Int, CaseIterable, Identifiable {
        case ALL
        case ETH
        case BSC
        case SAFE
        
        var title: String {
            switch self {
            case .ALL: return "transactions.types.all".localized
            case .ETH: return "ETH"
            case .BSC: return "BSC"
            case .SAFE: return "SAFE"
            }
        }
        
        var id: Self {
            self
        }
    }
}
