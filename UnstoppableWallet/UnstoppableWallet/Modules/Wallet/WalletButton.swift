enum WalletButton {
    case send
    case receive
    case swap
    case chart
    case scan
    case liquidity
    
    var title: String {
        switch self {
        case .send: return "balance.send".localized
        case .receive: return "balance.receive".localized
        case .swap: return "balance.swap".localized
        case .chart: return "balance.chart".localized
        case .scan: return "balance.scan".localized
        case .liquidity: return "liquidity.title.add".localized
        }
    }

    var icon: String {
        switch self {
        case .send: return "arrow_m_up"
        case .receive: return "arrow_m_down"
        case .swap: return "swap_e"
        case .chart: return "chart"
        case .scan: return "scan"
        case .liquidity: return "arrow_swap_approval_2_24"
        }
    }

    var accent: Bool {
        switch self {
        case .scan, .chart: return true
        default: return false
        }
    }
}
