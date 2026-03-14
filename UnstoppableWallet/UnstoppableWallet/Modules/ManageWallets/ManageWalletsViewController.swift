import Combine

import MarketKit
import RxCocoa
import RxSwift
import SectionsTableView
import SnapKit

import UIKit

class ManageWalletsViewController: ThemeSearchViewController {
    private let viewModel: ManageWalletsViewModel
    private let restoreSettingsView: RestoreSettingsView
    private let disposeBag = DisposeBag()
    private var cancellables = Set<AnyCancellable>()

    private let tableView = SectionsTableView(style: .grouped)
    private let filterButton = SecondaryButton()
    private let notFoundPlaceholder = PlaceholderView(layoutType: .keyboard)

    private var viewItems: [ManageWalletsViewModel.ViewItem] = []
    private var isLoaded = false

    init(viewModel: ManageWalletsViewModel, restoreSettingsView: RestoreSettingsView) {
        self.viewModel = viewModel
        self.restoreSettingsView = restoreSettingsView

        super.init(scrollViews: [tableView])
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = "manage_wallets.title".localized
        navigationItem.searchController?.searchBar.placeholder = "manage_wallets.search_placeholder".localized

        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "button.done".localized, style: .done, target: self, action: #selector(onTapDoneButton))
        navigationItem.rightBarButtonItem?.tintColor = .themeJacob

        if viewModel.addTokenEnabled {
            navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(onTapAddTokenButton))
        }
        setupFilterButton()
        
        view.addSubview(tableView)
        tableView.snp.makeConstraints { maker in
            maker.top.equalTo(filterButton.snp.bottom).offset(CGFloat.margin8)
            maker.leading.trailing.bottom.equalToSuperview()
        }

        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
        tableView.sectionDataSource = self

        view.addSubview(notFoundPlaceholder)
        notFoundPlaceholder.snp.makeConstraints { maker in
            maker.edges.equalTo(view.safeAreaLayoutGuide)
        }

        notFoundPlaceholder.image = UIImage(named: "not_found_48")
        notFoundPlaceholder.text = "manage_wallets.not_found".localized

        subscribe(disposeBag, viewModel.viewItemsDriver) { [weak self] in self?.onUpdate(viewItems: $0) }
        subscribe(disposeBag, viewModel.notFoundVisibleDriver) { [weak self] in self?.setNotFound(visible: $0) }
        subscribe(disposeBag, viewModel.disableItemSignal) { [weak self] in self?.setToggle(on: false, index: $0) }
        subscribe(disposeBag, viewModel.showInfoSignal) { [weak self] in self?.showInfo(viewItem: $0) }
        subscribe(disposeBag, viewModel.showContractSignal) { [weak self] in self?.showContract(viewItem: $0) }

        $filter
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.viewModel.onUpdate(filter: $0 ?? "") }
            .store(in: &cancellables)

        tableView.buildSections()

        isLoaded = true
    }

    private func open(controller: UIViewController) {
        navigationItem.searchController?.dismiss(animated: true)
        present(controller, animated: true)
    }

    @objc private func onTapDoneButton() {
        dismiss(animated: true)
    }

    @objc private func onTapAddTokenButton() {
        guard let module = AddTokenModule.viewController() else {
            return
        }

        present(module, animated: true)

        stat(page: .coinManager, event: .open(page: .addToken))
    }

    private func setupFilterButton() {
        view.addSubview(filterButton)
        filterButton.snp.makeConstraints { maker in
            maker.top.equalTo(view.safeAreaLayoutGuide).offset(CGFloat.margin8)
            maker.leading.equalToSuperview().inset(CGFloat.margin16)
            maker.height.equalTo(SecondaryButton.height(style: .default))
        }

        filterButton.set(style: .default, image: UIImage(named: "arrow_small_down_20"))
        updateFilterButtonTitle()
        filterButton.addTarget(self, action: #selector(onTapFilterButton), for: .touchUpInside)
    }

    private func updateFilterButtonTitle() {
        let filter = viewModel.currentBlockchainFilter
        updateFilterButtonTitle(filter: filter)
    }

    private func updateFilterButtonTitle(filter: ManageWalletsService.BlockchainFilter) {
        let title: String
        switch filter {
        case .all:
            title = "manage_wallets.filter_all_blockchains".localized
        case .bitcoinSeries:
            title = "manage_wallets.filter_bitcoin_series".localized
        case .blockchain(let type):
            title = viewModel.blockchainName(blockchainType: type) ?? type.uid
        }
        
        filterButton.setTitle(title, for: .normal)
        
        let imageName = "arrow_small_down_20"
        filterButton.setImage(UIImage(named: imageName), for: .normal)
    }

    @objc private func onTapFilterButton() {
        typealias BlockchainFilter = ManageWalletsService.BlockchainFilter
        
        let filters: [BlockchainFilter] = [
            .all,
            .bitcoinSeries,
            .blockchain(.safe4),
            .blockchain(.ethereum),
            .blockchain(.binanceSmartChain),
            .blockchain(.polygon),
            .blockchain(.arbitrumOne),
            .blockchain(.optimism),
            .blockchain(.avalanche),
            .blockchain(.tron),
            .blockchain(.zcash)
        ]

        let viewItems: [SelectorModule.ViewItem] = filters.map { filter in
            let title: String
            let image: CellBuilderNew.CellElement.Image?
            
            switch filter {
            case .all:
                title = "manage_wallets.filter_all_blockchains".localized
                image = nil
            case .bitcoinSeries:
                title = "manage_wallets.filter_bitcoin_series".localized
                image = .local(UIImage(named: "bitcoin_32"))
            case .blockchain(let type):
                title = viewModel.blockchainName(blockchainType: type) ?? type.uid
                image = .url(type.imageUrl, placeholder: "placeholder_circle_32")
            }
            
            let selected = viewModel.currentBlockchainFilter == filter
            return SelectorModule.ViewItem(
                image: image,
                title: title,
                selected: selected
            )
        }

        let viewController = SelectorModule.bottomSingleSelectorViewController(
            title: "manage_wallets.filter_by_blockchain".localized,
            viewItems: viewItems
        ) { [weak self] index in
            guard let self else { return }
            let selectedFilter = filters[index]
            self.updateFilterButtonTitle(filter: selectedFilter)
            self.viewModel.onUpdate(blockchainFilter: selectedFilter)
        }

        present(viewController, animated: true)
    }

    private func onUpdate(viewItems: [ManageWalletsViewModel.ViewItem]) {
        let animated = self.viewItems.map(\.uid) == viewItems.map(\.uid)
        self.viewItems = viewItems

        if isLoaded {
            tableView.reload(animated: animated)
        }
    }

    private func setNotFound(visible: Bool) {
        notFoundPlaceholder.isHidden = !visible
    }

    private func showInfo(viewItem: ManageWalletsViewModel.InfoViewItem) {
        showBottomSheet(viewItem: viewItem.coin, items: [
            .description(text: viewItem.text),
        ])
    }

    private func showContract(viewItem: ManageWalletsViewModel.ContractViewItem) {
        showBottomSheet(viewItem: viewItem.coin, items: [
            .contractAddress(imageUrl: viewItem.blockchainImageUrl, value: viewItem.value, explorerUrl: viewItem.explorerUrl),
        ])
    }

    private func showBottomSheet(viewItem: ManageWalletsViewModel.CoinViewItem, items: [BottomSheetModule.Item]) {
        let viewController = BottomSheetModule.viewController(
            image: .remote(url: viewItem.coin.imageUrl, placeholder: viewItem.coinPlaceholderImageName),
            title: viewItem.coin.code,
            subtitle: viewItem.coin.name,
            items: items
        )

        present(viewController, animated: true)
    }

    private func onToggle(index: Int, enabled: Bool) {
        if enabled {
            viewModel.onEnable(index: index)
        } else {
            viewModel.onDisable(index: index)
        }
    }

    func setToggle(on: Bool, index: Int) {
        guard let cell = tableView.cellForRow(at: IndexPath(row: index, section: 0)) as? BaseThemeCell else {
            return
        }

        CellBuilderNew.buildStatic(cell: cell, rootElement: rootElement(index: index, viewItem: viewItems[index], forceToggleOn: on))
    }
}

extension ManageWalletsViewController: SectionsDataSource {
    private func rootElement(index: Int, viewItem: ManageWalletsViewModel.ViewItem, forceToggleOn: Bool? = nil) -> CellBuilderNew.CellElement {
        .hStack([
            .image32 { component in
                component.imageView.setImage(coin: viewItem.coin, placeholder: viewItem.placeholderImageName)
            },
            .vStackCentered([
                .hStack([
                    .textElement(text: .body(viewItem.coin.code), parameters: .highHugging),
                    .margin8,
                    .badge { component in
                        component.isHidden = viewItem.badge == nil
                        component.badgeView.set(style: .small)
                        component.badgeView.text = viewItem.badge
                    },
                    .margin0,
                    .text { _ in },
                ]),
                .margin(1),
                .textElement(text: .subhead2(viewItem.coin.name)),
            ]),
            .secondaryCircleButton { [weak self] component in
                component.isHidden = !viewItem.hasInfo
                component.button.set(image: UIImage(named: "circle_information_20"), style: .transparent)
                component.onTap = {
                    self?.viewModel.onTapInfo(index: index)
                }
            },
            .switch { component in
                if let forceOn = forceToggleOn {
                    component.switchView.setOn(forceOn, animated: true)
                } else {
                    component.switchView.isOn = viewItem.enabled
                }

                component.onSwitch = { [weak self] enabled in
                    self?.onToggle(index: index, enabled: enabled)
                }
            },
        ])
    }

    func buildSections() -> [SectionProtocol] {
        [
            Section(
                id: "coins",
                headerState: .margin(height: .margin4),
                footerState: .margin(height: .margin32),
                rows: viewItems.enumerated().map { index, viewItem in
                    let isLast = index == viewItems.count - 1

                    return CellBuilderNew.row(
                        rootElement: rootElement(index: index, viewItem: viewItem),
                        tableView: tableView,
                        id: "token_\(viewItem.uid)",
                        hash: "token_\(viewItem.enabled)_\(viewItem.hasInfo)_\(isLast)",
                        height: .heightDoubleLineCell,
                        autoDeselect: true,
                        bind: { cell in
                            cell.set(backgroundStyle: .transparent, isLast: isLast)
                        }
                    )
                }
            ),
        ]
    }
}
