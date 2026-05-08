import Foundation
import Combine

class MarketDappViewModel: ObservableObject {
    @Published var currentTab: MarketDappModule.Tab = .ALL
    func load() {}
}


