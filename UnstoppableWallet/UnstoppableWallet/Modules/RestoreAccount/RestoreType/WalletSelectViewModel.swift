import SwiftUI
import Combine

class WalletSelectViewModel: ObservableObject {
    @Published var searchText: String = ""
    @Published var currentTabIndex: Int = 0
    
    var tabTitles: [String] {
        [
            "wallet_select.tab.hardware".localized,
            "wallet_select.tab.software".localized,
            "wallet_select.tab.both".localized
        ]
    }
    
    let categories: [String] = ["hardware", "software", "both"]
    
    @Published var walletData: WalletData?
    
    init() {
        loadWalletData()
    }
    
    private func loadWalletData() {
        guard let url = Bundle.main.url(forResource: "wallet", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            return
        }
        
        walletData = try? JSONDecoder().decode(WalletData.self, from: data)
    }
    
    func wallets(for category: String) -> [WalletItem] {
        guard let walletData = walletData else { return [] }
        let wallets: [WalletItem]
        
        switch category {
        case "hardware": wallets = walletData.hardware
        case "software": wallets = walletData.software
        case "both": wallets = walletData.both
        default: wallets = []
        }
        
        if searchText.isEmpty {
            return wallets
        } else {
            return wallets.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
    }
    
    func categoryName(for walletType: Int) -> String {
        switch walletType {
        case 0: return "wallet_select.tab.software".localized
        case 1: return "wallet_select.tab.hardware".localized
        case 2: return "wallet_select.tab.both".localized
        default: return ""
        }
    }
}

struct WalletData: Codable {
    let hardware: [WalletItem]
    let software: [WalletItem]
    let both: [WalletItem]
}

struct WalletItem: Codable, Identifiable, Hashable {
    let id = UUID()
    let name: String
    let wallet: Int
    let bip32path: [String]
    let custompath: Bool
    let needpassword: Int
    
    enum CodingKeys: String, CodingKey {
        case name, wallet, bip32path, custompath, needpassword
    }
}
