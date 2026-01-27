import RxCocoa
import RxSwift
import SectionsTableView
import UIKit
import UniswapKit

class SwapViewController: ThemeViewController {
    private let animationDuration: TimeInterval = 0.2
    private let disposeBag = DisposeBag()

    private let viewModel: SwapViewModel
    private let dataSourceManager: ISwapDataSourceManager
    private let tableView = SectionsTableView(style: .grouped)
    private var isLoaded = false

    private var dataSource: ISwapDataSource?

    init(viewModel: SwapViewModel, dataSourceManager: ISwapDataSourceManager) {
        self.viewModel = viewModel
        self.dataSourceManager = dataSourceManager

        super.init()

        hidesBottomBarWhenPushed = true
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = "swap.title".localized

        navigationItem.largeTitleDisplayMode = .never
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: "button.close".localized, style: .plain, target: self, action: #selector(onClose))
        navigationItem.backBarButtonItem = UIBarButtonItem(title: "", style: .plain, target: nil, action: nil)

        view.addSubview(tableView)
        tableView.snp.makeConstraints { maker in
            maker.edges.equalToSuperview()
        }

        tableView.sectionHeaderTopPadding = 0
        tableView.separatorStyle = .none
        tableView.backgroundColor = .clear
        tableView.sectionDataSource = self
        tableView.keyboardDismissMode = .onDrag

        let tap = UITapGestureRecognizer(target: view, action: #selector(UIView.endEditing))
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)

        subscribeToViewModel()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if !isLoaded {
            dataSource?.viewDidAppear()
        }
        isLoaded = true
    }

    private func subscribeToViewModel() {
        subscribe(disposeBag, dataSourceManager.dataSourceUpdated) { [weak self] _ in
            self?.updateDataSource()
        }
        updateDataSource()
    }

    private func updateDataSource() {
        dataSource = dataSourceManager.dataSource
        dataSource?.tableView = tableView

        dataSource?.onReload = { [weak self] in self?.reloadTable() }
        dataSource?.onClose = { [weak self] in self?.onClose() }
        dataSource?.onOpen = { [weak self] viewController, viaPush in
            if viaPush {
                self?.navigationController?.pushViewController(viewController, animated: true)
            } else {
                self?.present(viewController, animated: true)
            }
        }
        dataSource?.onOpenSelectProvider = { [weak self] in
            self?.onOpenSelectProvider()
        }
        dataSource?.onOpenSettings = { [weak self] in
            self?.onOpenSettings()
        }

        if isLoaded {
            tableView.reload()
        } else {
            tableView.buildSections()
        }
    }

    @objc func onClose() {
        dismiss(animated: true)
    }
    
    @objc func onkLines() {
        guard let token0 = dataSource?.state.tokenFrom, let token1 = dataSource?.state.tokenTo else { return }
        guard token0.blockchainType == .safe4, token1.blockchainType == .safe4 else { return }
        Coordinator.shared.present { _ in
            ThemeNavigationStack {
                KLineChartView(provider: Safe4Provider(networkManager: Core.shared.networkManager), token0: token0, token1: token1)
            }
        }
    }

    @objc func onOpenSettings() {
        guard let viewController = SwapSettingsModule.viewController(
            dataSourceManager: dataSourceManager,
            dexManager: viewModel.dexManager
        ) else {
            return
        }

        present(viewController, animated: true)
    }

    @objc func onOpenSelectProvider() {
        present(SwapSelectProviderModule.viewController(dexManager: viewModel.dexManager).toBottomSheet, animated: true)
    }

    private func reloadTable() {
        tableView.buildSections()
        udpateKlineBtn()
        guard isLoaded else {
            return
        }

        UIView.performWithoutAnimation {
            tableView.beginUpdates()
            tableView.endUpdates()
        }
    }
    
    private func udpateKlineBtn() {
        guard let token0 = dataSource?.state.tokenFrom, let token1 = dataSource?.state.tokenTo, token0.blockchainType == .safe4, token1.blockchainType == .safe4 else {
            navigationItem.rightBarButtonItem = nil
            return
        }
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "行情".localized, style: .plain, target: self, action: #selector(onkLines))
    }
}

extension SwapViewController: SectionsDataSource {
    func buildSections() -> [SectionProtocol] {
        var sections = [SectionProtocol]()

        if let dataSource {
            sections.append(contentsOf: dataSource.buildSections)
        }

        return sections
    }
}
