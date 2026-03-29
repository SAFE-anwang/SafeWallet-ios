import Foundation
import UIKit
import SectionsTableView
import SnapKit
import UIExtensions
import RxSwift
import RxCocoa
import Combine
import MarketKit
import EvmKit
import UniswapKit


class LiquidityRecordViewController: ThemeViewController {
    
    private let disposeBag = DisposeBag()
    private var cancellables = Set<AnyCancellable>()
    
    private let viewModel: LiquidityRecordViewModel?
    private let v3ViewModel: LiquidityV3RecordViewModel?
        
    private let tableView = SectionsTableView(style: .grouped)
    private let spinner = HUDActivityView.create(with: .medium24)
    private var viewItems = [LiquidityRecordViewModel.RecordItem]()
    private var v3ViewItems = [LiquidityV3RecordViewModel.V3RecordItem]()
    
    private let refreshControl = UIRefreshControl()
    private let emptyView = PlaceholderView()
    weak var parentNavigationController: UINavigationController?
    private var loadingStatus: (Bool, Bool) = (false, false)
        
    // MARK: - 单链模式初始化
    init(viewModel: LiquidityRecordViewModel, v3ViewModel: LiquidityV3RecordViewModel) {
        self.viewModel = viewModel
        self.v3ViewModel = v3ViewModel
        super.init()
        hidesBottomBarWhenPushed = true
    }
        
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        refreshControl.tintColor = .themeLeah
        refreshControl.alpha = 0.6
        refreshControl.addTarget(self, action: #selector(onRefresh), for: .valueChanged)

        tableView.sectionDataSource = self
        tableView.separatorStyle = .none
        tableView.backgroundColor = .clear
        
        tableView.registerCell(forClass: LiquidityRecordCell.self)
        tableView.registerCell(forClass: LiquidityV3RecordCell.self)
        
        view.addSubview(tableView)
        tableView.snp.makeConstraints { maker in
            maker.edges.equalToSuperview()
        }
        tableView.buildSections()
        
        view.addSubview(emptyView)
        emptyView.snp.makeConstraints { maker in
            maker.edges.equalTo(view.safeAreaLayoutGuide)
        }

        emptyView.image = UIImage(named: "add_to_wallet_2_48")
        emptyView.text = "liquidity.empty.description".localized
        emptyView.isHidden = true
        
        view.addSubview(spinner)
        spinner.snp.makeConstraints { maker in
            maker.center.equalToSuperview()
        }
        spinner.startAnimating()

        setupSingleChainBindings()
        
        // 初始加载
        refreshData()
    }
    
    // MARK: - 单链模式绑定
    private func setupSingleChainBindings() {
        guard let viewModel = viewModel, let v3ViewModel = v3ViewModel else { return }
        
        subscribe(disposeBag, viewModel.statusDriver) { [weak self] state in
            self?.sync(state: state)
        }
        
        subscribe(disposeBag, v3ViewModel.statusDriver) { [weak self] state in
            self?.sync(state: state)
        }
    }
    
    
    // MARK: - 数据刷新
    private func refreshData() {
        viewModel?.refresh()
        v3ViewModel?.refresh()
        loadingStatus = (true, true)
    }
    
    // MARK: - 状态同步（单链）
    private func sync(state: LiquidityRecordService.State) {
        DispatchQueue.main.async { [weak self] in
            if case .loading = state {
                self?.loadingStatus.0 = true
            } else {
                self?.loadingStatus.0 = false
            }
            
            switch state {
            case let .completed(datas):
                self?.sync(data: datas)
            case let .failed(error):
                self?.show(error: error)
            default: ()
            }
            self?.updateSpinner()
        }
    }
    
    private func sync(state: LiquidityV3RecordService.State) {
        DispatchQueue.main.async { [weak self] in
            if case .loading = state {
                self?.loadingStatus.1 = true
            } else {
                self?.loadingStatus.1 = false
            }
            
            switch state {
            case let .completed(datas):
                self?.sync(datas: datas)
            case let .failed(error):
                self?.show(error: error)
            default: ()
            }
            self?.updateSpinner()
        }
    }
    
    private func getEvmKit(for blockchainType: BlockchainType) throws -> EvmKit.Kit {
        guard let evmKitWrapper = try? Core.shared.evmBlockchainManager.evmKitManager(blockchainType: blockchainType).evmKitWrapper else {
            throw LiquidityRecordError.noWallet
        }
        return evmKitWrapper.evmKit
    }
    
    private func address(token: MarketKit.Token) throws -> EvmKit.Address {
        switch token.type {
        case .native: return try EvmKit.Address(hex: "0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee")
        case .eip20(let address): return try EvmKit.Address(hex: address)
        default: throw LiquidityRecordError.invalidAddress
        }
    }
    
    private func updateSpinner() {
        if loadingStatus.0 == true || loadingStatus.1 == true {
            spinner.isHidden = false
            emptyView.isHidden = true
        } else {
            spinner.isHidden = true
            updateEmptyView()
        }
    }
    
    private func updateEmptyView() {
        emptyView.isHidden = v3ViewItems.count > 0 || viewItems.count > 0
    }

    private func sync(data: [LiquidityRecordViewModel.RecordItem]) {
        self.viewItems = data
        tableView.reload()
    }
    
    private func sync(datas: [LiquidityV3RecordViewModel.V3RecordItem]) {
        self.v3ViewItems = datas
        tableView.reload()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        tableView.refreshControl = refreshControl
    }

    @objc private func onRefresh() {
        refreshData()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.refreshControl.endRefreshing()
        }
    }

    private func show(error: String?) {
        if let message = error {
            HudHelper.instance.show(banner: .error(string: message))
        }
    }
    
    private func removeConfirmation(viewItem: LiquidityRecordViewModel.RecordItem) {
        let vm = viewModel ?? createTempViewModel(for: viewItem.tokenA.blockchainType)
        let viewController = LiquidityRemoveConfirmViewController(viewModel: vm, recordItem: viewItem)
        Coordinator.shared.present { _ in
            LiquidityViewRepresentable(viewController: viewController)
        }
    }
    
    private func toDetailView(viewItem: LiquidityV3RecordViewModel.V3RecordItem) {
        let vm = v3ViewModel ?? createTempV3ViewModel(for: viewItem.token0.blockchainType)
        let viewController = LiquidityV3RecordDetailViewController(viewModel: vm, viewItem: viewItem)
        Coordinator.shared.present { _ in
            LiquidityViewRepresentable(viewController: viewController)
        }
    }
    
    private func createTempViewModel(for blockchainType: BlockchainType) -> LiquidityRecordViewModel {
        let service = LiquidityRecordService(
            marketKit: Core.shared.marketKit,
            walletManager: Core.shared.walletManager,
            adapterManager: Core.shared.adapterManager,
            blockchainType: blockchainType
        )
        return LiquidityRecordViewModel(service: service)
    }
    
    private func createTempV3ViewModel(for blockchainType: BlockchainType) -> LiquidityV3RecordViewModel {
        let dexType: DexType = blockchainType == .binanceSmartChain ? .pancakeSwap : .uniswap
        let service = LiquidityV3RecordService(
            dexType: dexType,
            marketKit: Core.shared.marketKit,
            walletManager: Core.shared.walletManager,
            adapterManager: Core.shared.adapterManager,
            blockchainType: blockchainType
        )!
        return LiquidityV3RecordViewModel(service: service)
    }
}

// MARK: - SectionsDataSource

extension LiquidityRecordViewController: SectionsDataSource {
    
    private func row(viewItem: LiquidityRecordViewModel.RecordItem) -> RowProtocol {
        Row<LiquidityRecordCell>(
            id: "v2_row_\(viewItem.pair.pairAddress.hex)",
            height: LiquidityRecordCell.height(),
            autoDeselect: true,
            bind: { cell, _ in
                cell.bind(viewItem: viewItem)
            },
            action: { [weak self] _ in
                self?.removeConfirmation(viewItem: viewItem)
            }
        )
    }
    
    private func row(viewItem: LiquidityV3RecordViewModel.V3RecordItem) -> RowProtocol {
        Row<LiquidityV3RecordCell>(
            id: "v3_row_\(viewItem.positions.tokenId)",
            height: LiquidityV3RecordCell.height(),
            autoDeselect: true,
            bind: { cell, _ in
                cell.bind(viewItem: viewItem)
            },
            action: { [weak self] _ in
                self?.toDetailView(viewItem: viewItem)
            }
        )
    }

    func buildSections() -> [SectionProtocol] {
        var sections = [SectionProtocol]()
        
        sections.append(contentsOf: buildSingleChainSections())
        
        return sections
    }
    
    private func buildSingleChainSections() -> [SectionProtocol] {
        var sections = [SectionProtocol]()
        
        if viewItems.count > 0 {
            let v2rows = viewItems.map { row(viewItem: $0) }
            let section = Section(
                id: "v2",
                headerState: .text(text: "V2 LP", topMargin: 25, bottomMargin: 15),
                rows: v2rows
            )
            sections.append(section)
        }
        
        if v3ViewItems.count > 0 {
            let v3Rows = v3ViewItems.map { row(viewItem: $0) }
            let section = Section(
                id: "v3",
                headerState: .text(text: "V3 LP", topMargin: 25, bottomMargin: 15),
                rows: v3Rows
            )
            sections.append(section)
        }
        
        return sections
    }
    
    private func buildMultiChainSections() -> [SectionProtocol] {
        var sections = [SectionProtocol]()
        
        // 按链分组
        let groupedV2 = Dictionary(grouping: viewItems) { $0.tokenA.blockchainType }
        let groupedV3 = Dictionary(grouping: v3ViewItems) { $0.token0.blockchainType }
        
        let allChains = Set(groupedV2.keys).union(Set(groupedV3.keys))
        let sortedChains = allChains.sorted { $0.order < $1.order }
        
        for chain in sortedChains {
            let chainName = chainName(for: chain)
            
            // V2 部分
            if let v2Items = groupedV2[chain], !v2Items.isEmpty {
                let v2rows = v2Items.map { row(viewItem: $0) }
                let section = Section(
                    id: "v2_\(chainName)",
                    headerState: .text(text: "\(chainName) V2 LP", topMargin: 25, bottomMargin: 15),
                    rows: v2rows
                )
                sections.append(section)
            }
            
            // V3 部分
            if let v3Items = groupedV3[chain], !v3Items.isEmpty {
                let v3Rows = v3Items.map { row(viewItem: $0) }
                let section = Section(
                    id: "v3_\(chainName)",
                    headerState: .text(text: "\(chainName) V3 LP", topMargin: 25, bottomMargin: 15),
                    rows: v3Rows
                )
                sections.append(section)
            }
        }
        
        return sections
    }
    
    private func chainName(for blockchainType: BlockchainType) -> String {
        switch blockchainType {
        case .safe4: return "SAFE"
        case .binanceSmartChain: return "BSC"
        case .ethereum: return "ETH"
        default: return ""
        }
    }
}

// MARK: - Error

enum LiquidityRecordError: Error {
    case invalidAddress
    case noWallet
}
