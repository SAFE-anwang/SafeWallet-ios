import Foundation
import UIKit
import SectionsTableView
import SnapKit
import UIExtensions
import RxSwift
import RxCocoa
import MarketKit
import BigInt

// MARK: - MultiChainLiquidityViewController
// 使用旧的 UI 展示多链流动性数据

class MultiChainLiquidityViewController: ThemeViewController {
    
    private let disposeBag = DisposeBag()
    private let viewModel: MultiChainLiquidityViewModel
    private let tableView = SectionsTableView(style: .grouped)
    private let spinner = HUDActivityView.create(with: .medium24)
    private var v2ViewItems: [LiquidityRecordViewModel.RecordItem] = []
    private var v3ViewItems: [LiquidityV3RecordViewModel.V3RecordItem] = []
    
    private let refreshControl = UIRefreshControl()
    private let emptyView = PlaceholderView()
    private var isLoading = false
    
    init(viewModel: MultiChainLiquidityViewModel = MultiChainLiquidityViewModel()) {
        self.viewModel = viewModel
        super.init()
        hidesBottomBarWhenPushed = true
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        title = "liquidity.title.record".localized
        navigationItem.backBarButtonItem = UIBarButtonItem(title: title, style: .plain, target: nil, action: nil)
        
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

        setupBindings()
        
        viewModel.refreshAll()
        isLoading = true
    }
    
    private func setupBindings() {
        // 监听状态变化
        viewModel.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.handleState(state)
            }
            .store(in: &viewModel.cancellables)
        
        // 监听过滤后的记录变化
        viewModel.$filteredRecords
            .receive(on: DispatchQueue.main)
            .sink { [weak self] records in
                self?.convertAndDisplay(records: records)
            }
            .store(in: &viewModel.cancellables)
    }
    
    private func handleState(_ state: MultiChainLiquidityService.State) {
        switch state {
        case .idle:
            isLoading = false
        case .loading:
            isLoading = true
            spinner.isHidden = false
            emptyView.isHidden = true
        case .completed:
            isLoading = false
            spinner.isHidden = true
            updateEmptyView()
        case .failed(let error):
            isLoading = false
            spinner.isHidden = true
            show(error: error)
            updateEmptyView()
        }
    }
    
    private func updateEmptyView() {
        emptyView.isHidden = v2ViewItems.count > 0 || v3ViewItems.count > 0
    }
    
    private func convertAndDisplay(records: [ChainLiquidityRecord]) {
        // 转换为 V2 ViewItems
        v2ViewItems = records
            .filter { $0.poolType == .v2 }
            .compactMap { record in
                guard let rawData = record.rawData as? V2RawData else { return nil }
                return convertToV2ViewItem(record: record, rawData: rawData)
            }
        
        // 转换为 V3 ViewItems
        v3ViewItems = records
            .filter { $0.poolType == .v3 }
            .compactMap { record in
                guard let rawData = record.rawData as? V3RawData else { return nil }
                return convertToV3ViewItem(record: record, rawData: rawData)
            }
        
        tableView.reload()
        updateEmptyView()
    }
    
    private func convertToV2ViewItem(record: ChainLiquidityRecord, rawData: V2RawData) -> LiquidityRecordViewModel.RecordItem? {
        // 创建 PoolInfo
        let poolInfo = LiquidityRecordService.PoolInfo(
            pooltToken0Amount: rawData.poolInfo.pooltToken0Amount,
            pooltToken1Amount: rawData.poolInfo.pooltToken1Amount,
            balanceOfAccount: rawData.poolInfo.balanceOfAccount,
            poolTokenTotalSupply: rawData.poolInfo.poolTokenTotalSupply
        )
        
        // 创建 LiquidityPair
        guard let evmKit = try? getEvmKit(for: record.blockchainType) else { return nil }
        
        let pairItem0 = LiquidityPairItem(token: record.token0, address: try! address(token: record.token0))
        let pairItem1 = LiquidityPairItem(token: record.token1, address: try! address(token: record.token1))
        
        guard let liquidityPair = LiquidityPair.getPairAddress(
            evmKit: evmKit,
            itemA: pairItem0,
            itemB: pairItem1
        ) else { return nil }
        
        return LiquidityRecordViewModel.RecordItem(poolInfo: poolInfo, pair: liquidityPair)
    }
    
    private func convertToV3ViewItem(record: ChainLiquidityRecord, rawData: V3RawData) -> LiquidityV3RecordViewModel.V3RecordItem? {
        return LiquidityV3RecordViewModel.V3RecordItem(
            positions: rawData.position,
            token0: record.token0,
            token1: record.token1,
            isInRange: true, // 需要计算
            token0Amount: rawData.position.liquidity,
            token1Amount: rawData.position.liquidity,
            lowerPrice: nil,
            upperPrice: nil
        )
    }
    
    private func getEvmKit(for blockchainType: BlockchainType) throws -> EvmKit.Kit {
        guard let evmKitWrapper = try? Core.shared.evmBlockchainManager.evmKitManager(blockchainType: blockchainType).evmKitWrapper else {
            throw ChainProviderError.noWallet
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
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        tableView.refreshControl = refreshControl
    }

    @objc private func onRefresh() {
        viewModel.refreshAll()
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
        // 创建临时的 ViewModel 用于移除流动性
        let service = LiquidityRecordService(
            marketKit: Core.shared.marketKit,
            walletManager: Core.shared.walletManager,
            adapterManager: Core.shared.adapterManager,
            blockchainType: viewItem.tokenA.blockchainType
        )
        let vm = LiquidityRecordViewModel(service: service)
        let viewController = LiquidityRemoveConfirmViewController(viewModel: vm, recordItem: viewItem)
        Coordinator.shared.present { _ in
            LiquidityViewRepresentable(viewController: viewController)
        }
    }
    
    func toDetailView(viewItem: LiquidityV3RecordViewModel.V3RecordItem) {
        // 创建临时的 ViewModel 用于 V3 详情
        let service = LiquidityV3RecordService(
            dexType: .uniswap,
            marketKit: Core.shared.marketKit,
            walletManager: Core.shared.walletManager,
            adapterManager: Core.shared.adapterManager,
            blockchainType: viewItem.token0.blockchainType
        )
        guard let v3Service = service else { return }
        let vm = LiquidityV3RecordViewModel(service: v3Service)
        let viewController = LiquidityV3RecordDetailViewController(viewModel: vm, viewItem: viewItem)
        Coordinator.shared.present { _ in
            LiquidityViewRepresentable(viewController: viewController)
        }
    }
}

// MARK: - SectionsDataSource

extension MultiChainLiquidityViewController: SectionsDataSource {
    
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
        
        if v2ViewItems.count > 0 {
            let v2rows = v2ViewItems.map { row(viewItem: $0) }
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
}

// MARK: - Error

enum LiquidityRecordError: Error {
    case invalidAddress
}
