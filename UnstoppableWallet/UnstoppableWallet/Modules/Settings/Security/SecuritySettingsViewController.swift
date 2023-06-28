import UIKit
import RxSwift
import ThemeKit
import MarketKit
import ComponentKit
import SectionsTableView
import PinKit

class SecuritySettingsViewController: ThemeViewController {
    private let viewModel: SecuritySettingsViewModel
    
    private let blockchainSettingsViewModel: BlockchainSettingsViewModel
    private var blockchainSettingsViewItem = BlockchainSettingsViewModel.ViewItem(btcViewItems: [], evmViewItems: [])

    private let disposeBag = DisposeBag()

    private let tableView = SectionsTableView(style: .grouped)

    private var pinViewItem = SecuritySettingsViewModel.PinViewItem(enabled: false, editVisible: false, biometryViewItem: nil)
    private var loaded = false
    
    private let vpnManager: SafeVPNViewModel
    
    init(viewModel: SecuritySettingsViewModel, blockchainSettingsViewModel: BlockchainSettingsViewModel) {
        self.viewModel = viewModel
        self.blockchainSettingsViewModel = blockchainSettingsViewModel
        vpnManager = App.shared.SafeVPNManager
        super.init()

        hidesBottomBarWhenPushed = true
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = "settings_security.title".localized
        navigationItem.backBarButtonItem = UIBarButtonItem(title: title, style: .plain, target: nil, action: nil)

        view.addSubview(tableView)
        tableView.snp.makeConstraints { maker in
            maker.edges.equalToSuperview()
        }

        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none

        tableView.sectionDataSource = self

        subscribe(disposeBag, viewModel.pinViewItemDriver) { [weak self] in self?.sync(pinViewItem: $0) }
        subscribe(disposeBag, viewModel.showErrorSignal) { [weak self] in self?.show(error: $0) }
        subscribe(disposeBag, viewModel.openSetPinSignal) { [weak self] in self?.openSetPin() }
        subscribe(disposeBag, viewModel.openUnlockSignal) { [weak self] in self?.openUnlock() }
        
        subscribe(disposeBag, blockchainSettingsViewModel.viewItemDriver) { [weak self] in self?.sync(viewItem: $0) }
        subscribe(disposeBag, blockchainSettingsViewModel.openBtcBlockchainSignal) { [weak self] in self?.openBtc(blockchain: $0) }
        subscribe(disposeBag, blockchainSettingsViewModel.openEvmBlockchainSignal) { [weak self] in self?.openEvm(blockchain: $0) }

        loaded = true
    }

    private func sync(pinViewItem: SecuritySettingsViewModel.PinViewItem) {
        self.pinViewItem = pinViewItem
        reloadTable()
    }
    
    private func sync(viewItem: BlockchainSettingsViewModel.ViewItem) {
        self.blockchainSettingsViewItem = viewItem
        reloadTable()
    }

    private func reloadTable() {
        if loaded {
            tableView.reload(animated: true)
        } else {
            tableView.buildSections()
        }
    }

    private func show(error: String) {
        HudHelper.instance.show(banner: .error(string: error))
    }

    private func openSetPin() {
        present(App.shared.pinKit.setPinModule(delegate: self), animated: true)
    }

    private func openEditPin() {
        present(App.shared.pinKit.editPinModule, animated: true)
    }

    private func openUnlock() {
        present(App.shared.pinKit.unlockPinModule(delegate: self, biometryUnlockMode: .disabled, insets: .zero, cancellable: true, autoDismiss: true), animated: true)
    }

}

extension SecuritySettingsViewController: SectionsDataSource {
    
    private func passcodeRows(viewItem: SecuritySettingsViewModel.PinViewItem) -> [RowProtocol] {
        var elements = tableView.universalImage24Elements(
                image: .local(UIImage(named: "dialpad_alt_2_24")?.withTintColor(.themeGray)),
                title: .body("settings_security.passcode".localized),
                accessoryType: .switch(isOn: viewItem.enabled) { [weak self] in self?.viewModel.onTogglePin(isOn: $0) }
        )
        elements.insert(.image20 { (component: ImageComponent) -> () in
            component.isHidden = viewItem.enabled
            component.imageView.image = UIImage(named: "warning_2_20")?.withTintColor(.themeLucian)
        }, at: 2)

        let passcodeRow = CellBuilderNew.row(
                rootElement: .hStack(elements),
                tableView: tableView,
                id: "passcode",
                hash: "\(viewItem.enabled)",
                height: .heightCell48,
                bind: { cell in
                    cell.set(backgroundStyle: .lawrence, isFirst: true, isLast: !viewItem.editVisible)
                }
        )

        var rows: [RowProtocol] = [passcodeRow]

        if viewItem.editVisible {
            let editRow = tableView.universalRow48(
                    id: "edit-passcode",
                    title: .body("settings_security.change_pin".localized),
                    accessoryType: .disclosure,
                    autoDeselect: true,
                    isLast: true,
                    action: { [weak self] in
                        self?.openEditPin()
                    }
            )

            rows.append(editRow)
        }

        return rows
    }

    private func biometryRow(viewItem: SecuritySettingsViewModel.BiometryViewItem) -> RowProtocol {
        tableView.universalRow48(
                id: "biometry",
                image: .local(UIImage(named: viewItem.icon)?.withTintColor(.themeGray)),
                title: .body(viewItem.title),
                accessoryType: .switch(
                        isOn: viewItem.enabled,
                        onSwitch: { [weak self] isOn in
                            self?.viewModel.onToggleBiometry(isOn: isOn)
                        }),
                hash: "\(viewItem.enabled)",
                isFirst: true,
                isLast: true
        )
    }

    func buildSections() -> [SectionProtocol] {
        var sections = [SectionProtocol]()

        let passcodeSection = Section(
                id: "passcode",
                headerState: .margin(height: .margin12),
                footerState: .margin(height: .margin24),
                rows: passcodeRows(viewItem: pinViewItem)
        )
        sections.append(passcodeSection)

        if let biometryViewItem = pinViewItem.biometryViewItem {
            let biometrySection = Section(
                    id: "biometry",
                    footerState: .margin(height: .margin32),
                    rows: [
                        biometryRow(viewItem: biometryViewItem)
                    ]
            )
            sections.append(biometrySection)
        }

        return sections + safeBlockchainBack() +  buildBlockchainSettingsSections()
    }

}

extension SecuritySettingsViewController {
    
    private func vpnSwitch() -> [SectionProtocol] {
        let cell = tableView.universalRow62(
                id: "vpnSwitchCell",
                image: .local(UIImage(named: "safelog")),
                title: .body("VPN"),
                description: .subhead2("已断开"),
                accessoryType: .switch(
                    isOn: false,
                    onSwitch: { [weak self] isOn in
//                        if isOn == false {
//                            self?.vpnManager.closeService(nil)
//                            return
//                        }
                        self?.vpnManager.openService(completion: { (error) in
//                            cell.switchOn((error != nil) ? false : true)
                        })
                    }),
                isFirst: true,
                isLast: true
        )
        return [Section(
                id: "vpnSwitch",
                headerState: .text(text: "网络".localized, topMargin: .margin12, bottomMargin: .margin12),
                footerState: .margin(height: .margin24),
                rows:[cell]
        )]
    }
}


extension SecuritySettingsViewController {
    
    private func safeBlockchainBack() -> [SectionProtocol] {
        let cell = tableView.universalRow62(
                id: "safeBlockchain",
                image: .local(UIImage(named: "safelog")),
                title: .body("settings_security.safe_block_height".localized),
                accessoryType: .disclosure,
                isFirst: true,
                isLast: true,
                action: { [weak self] in
                    // self?.navigationController?.pushViewController(BlockchainSettingsModule.viewController(), animated: true)
                    HudHelper.instance.show(banner: .attention(string: "safe_zone.Safe4_Coming_Soon".localized))
                    self?.tableView.deselectCell(withCoordinator: self?.transitionCoordinator, animated: true)
                }
        )
        return [Section(
                id: "safeBlockchain",
                headerState: .text(text: "settings_security.safe_fallback".localized, topMargin: .margin12, bottomMargin: .margin12),
                footerState: .margin(height: .margin24),
                rows:[cell]
        )]
    }
}
extension SecuritySettingsViewController {
    
    private func blockchainRow(id: String, viewItem: BlockchainSettingsViewModel.BlockchainViewItem, isFirst: Bool, isLast: Bool, action: @escaping () -> ()) -> RowProtocol {
        tableView.universalRow62(
            id: id,
            image: .url(viewItem.iconUrl),
            title: .body(viewItem.name),
            description: .subhead2(viewItem.value),
            accessoryType: .disclosure,
            hash: "\(viewItem.value)-\(isFirst)-\(isLast)",
            autoDeselect: true,
            isFirst: isFirst,
            isLast: isLast,
            action: action
        )
    }
    
    private func buildBlockchainSettingsSections() -> [SectionProtocol] {
        
        [
            Section(
                    id: "btc",
                    headerState: .text(text: "coin_settings.title".localized, topMargin: .margin12, bottomMargin: .margin12),
                    rows: blockchainSettingsViewItem.btcViewItems.enumerated().map { index, btcViewItem in
                        blockchainRow(
                                id: "btc-\(index)",
                                viewItem: btcViewItem,
                                isFirst: index == 0,
                                isLast: false,
                                action: { [weak self] in
                                    self?.blockchainSettingsViewModel.onTapBtc(index: index)
                                }
                        )
                    }
            ),
            Section(
                    id: "evm",
                    footerState: .margin(height: .margin32),
                    rows: blockchainSettingsViewItem.evmViewItems.enumerated().map { index, evmViewItem in
                        blockchainRow(
                                id: "btc-\(index)",
                                viewItem: evmViewItem,
                                isFirst: false,
                                isLast: index == blockchainSettingsViewItem.evmViewItems.count - 1,
                                action: { [weak self] in
                                    self?.blockchainSettingsViewModel.onTapEvm(index: index)
                                }
                        )
                    }
            )
        ]
    }
    
    
    private func openBtc(blockchain: Blockchain) {
        present(BtcBlockchainSettingsModule.viewController(blockchain: blockchain), animated: true)
    }

    private func openEvm(blockchain: Blockchain) {
        present(EvmNetworkModule.viewController(blockchain: blockchain), animated: true)
    }
    
}
extension SecuritySettingsViewController: ISetPinDelegate {

    func didCancelSetPin() {
        tableView.reloadData()
    }

}

extension SecuritySettingsViewController: IUnlockDelegate {

    func onUnlock() {
        let success = viewModel.onUnlock()

        if !success {
            tableView.reloadData()
        }
    }

    func onCancelUnlock() {
        tableView.reloadData()
    }

}
