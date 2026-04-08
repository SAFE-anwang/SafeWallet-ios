import UIKit
import SectionsTableView
import SnapKit
import RxSwift
import RxCocoa
import MarketKit

class RedeemSafe3ViewController: ThemeViewController {
    
    private let disposeBag = DisposeBag()
    private let viewModel: RedeemSafe3ViewModel
    private let tableView = SectionsTableView(style: .grouped)
    private let spinner = HUDActivityView.create(with: .medium24)
    private let emptyView = PlaceholderView()
    private let syncStateView = PlaceholderView()
    private let tipsCell = Safe4WarningCell()
    private var isLoaded = false
    private let stepCell = RedeemSafe3StepCell()
    private let privateKeyInputCell = Safe4BaseInputCell()
    private let privateKeyInputCautionCell = FormCautionCell()

    private let buttonCell = PrimaryButtonCell()
    private var viewItems = [ RedeemSafe3ViewModel.LocalSafe3WalletBalanceInfoItem]()
    private var balanceInfo: RedeemSafe3ViewModel.LocalBalanceInfo?
    weak var parentNavigationController: UINavigationController?
    private let account: Account
    init(account: Account, viewModel: RedeemSafe3ViewModel) {
        self.account = account
        self.viewModel = viewModel

 
        privateKeyInputCell.setTitle(text: "safe_zone.safe3.private_key".localized)
        privateKeyInputCell.setInput(keyboardType: .default, placeholder: "safe_zone.enter_private_key".localized)
        tipsCell.bind(text: "safe_zone.safe3.migration_tip".localized, type: .normal)
        
        switch viewModel.redeemWalletType {
        case.local:
            privateKeyInputCell.isUserInteractionEnabled = false
        case .other:
            privateKeyInputCell.isUserInteractionEnabled = true
        }
    
        super.init()
        hidesBottomBarWhenPushed = true
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        view.addSubview(tableView)
        tableView.snp.makeConstraints { maker in
            maker.edges.equalToSuperview()
        }

        tableView.separatorStyle = .none
        tableView.backgroundColor = .clear
//        tableView.allowsSelection = false
        tableView.keyboardDismissMode = .onDrag
        tableView.sectionDataSource = self

        let tap = UITapGestureRecognizer(target: view, action: #selector(UIView.endEditing))
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)

        privateKeyInputCell.onChangeEditing = { [weak self] isEditing in
            self?.privateKeyInputCautionCell.isHidden = isEditing
            if isEditing == false {
                if self?.isLoaded == true {
                    self?.viewModel.validate(privateKey: self?.privateKeyInputCell.inputText)
                }
            } else {
                self?.privateKeyInputCell.set(cautionType: nil)
                self?.privateKeyInputCautionCell.set(caution: nil)
                self?.reloadTable()
            }
        }

        privateKeyInputCautionCell.onChangeHeight = { [weak self] in self?.reloadTable() }

        privateKeyInputCell.onChangeHeight = { [weak self] in self?.reloadTable() }
        privateKeyInputCell.onChangeText = { [weak self] in
            self?.viewModel.onEnter(safe3PrivateKey: $0)
        }
        
        buttonCell.onTap = {[weak self] in
            self?.didTapProceed()
        }
        
        view.addSubview(spinner)
        spinner.snp.makeConstraints { maker in
            maker.center.equalToSuperview()
        }
        spinner.isHidden = true
        spinner.startAnimating()
        
        
        emptyView.isHidden = true
        emptyView.image = UIImage(named: "safe4_empty")
        emptyView.text = "safe_zone.safe4.empty.description".localized
        view.addSubview(emptyView)
        emptyView.snp.makeConstraints { maker in
            maker.edges.equalToSuperview()
        }
        
        syncStateView.isHidden = true
        syncStateView.image = UIImage(named: "sync_error_48")
        view.addSubview(syncStateView)
        syncStateView.snp.makeConstraints { maker in
            maker.edges.equalToSuperview()
        }
        
        
        subscribe(disposeBag, viewModel.stateDriver) { [weak self] in self?.sync(state: $0)}
        subscribe(disposeBag, viewModel.stepDriver) { [weak self]  step in
            DispatchQueue.main.async { [weak self] in
                guard let strongSelf = self else { return }
                strongSelf.stepCell.bind(step: step.rawValue)
            }
        }
        
        subscribe(disposeBag, viewModel.privateKeyDriver) { [weak self] in
            self?.privateKeyInputCell.setInput(value: $0)
        }
        
        subscribe(disposeBag, viewModel.privateKeyCautionDriver) { [weak self] in
            self?.privateKeyInputCell.set(cautionType: $0?.type)
            self?.privateKeyInputCautionCell.set(caution: $0)
            self?.reloadTable()
        }
        
        subscribe(disposeBag, viewModel.safe3BalanceDriver) { [weak self] _ in self?.syncState() }
        subscribe(disposeBag, viewModel.safe4AddressDriver) { [weak self] _ in self?.syncState() }
        subscribe(disposeBag, viewModel.isEnabledSendDriver) { [weak self] isEnabled in
            DispatchQueue.main.async { [weak self] in
                guard let strongSelf = self else { return }
                if isEnabled == true {
                    strongSelf.buttonCell.isEnabled = true
                    strongSelf.buttonCell.set(style: .yellow)
                    strongSelf.buttonCell.title =  strongSelf.viewModel.redeemWalletType != .local ? "safe_zone.safe4.redeem.send.button".localized : "safe_zone.safe4.redeem.send.button.self".localized
                }else {
                    strongSelf.buttonCell.isEnabled = false
                    strongSelf.buttonCell.set(style: .gray)
                    strongSelf.buttonCell.title =  strongSelf.viewModel.redeemWalletType != .local ? "safe_zone.safe4.redeem.send.button".localized : "safe_zone.safe4.redeem.send.button.self".localized
                }
            }
        }
        
        tableView.buildSections()
        isLoaded = true
        
        if case .local = viewModel.redeemWalletType {
            syncStateView.isHidden = false
            let wallets = Core.shared.walletManager.activeWallets
            guard let safe3Wallet = wallets.filter({$0.token.blockchain.type == .safe}).first else {
                syncStateView.text = "safe_zone.send.openCoin".localized("SAFE")
                syncStateView.isHidden = false
                return
            }
            guard let safe3Adapter = Core.shared.adapterManager.depositAdapter(for: safe3Wallet) as? SafeCoinAdapter else { return  }

            if let state = WalletAdapterService(account: account, adapterManager: Core.shared.adapterManager).state(wallet: safe3Wallet), state == .synced {
                syncStateView.isHidden = true
                viewModel.syncLocalWalletInfo(safe3Wallet: safe3Wallet, safe3Adapter: safe3Adapter)
            } else {
                syncStateView.text = "SAFE" + "balance.syncing".localized
                syncStateView.isHidden = false
            }
            
            subscribe(disposeBag, safe3Adapter.balanceStateUpdatedObservable) { [weak self] in
                if $0 == .synced {
                    self?.viewModel.syncLocalWalletInfo(safe3Wallet: safe3Wallet, safe3Adapter: safe3Adapter)
                }else {
                    
                }
            }
        }


    }
    
    private func reloadTable() {
        guard isLoaded else {
            return
        }

        UIView.animate(withDuration: 0.2) {
            self.tableView.beginUpdates()
            self.tableView.endUpdates()
        }
    }
    
    private func syncState() {
        guard isLoaded else {
            return
        }
        DispatchQueue.main.async { [weak self] in
   
            self?.tableView.reload()
        }
    }
    
    private func sync(state: RedeemSafe3ViewModel.SendState) {
        DispatchQueue.main.async { [weak self] in
            switch state {
            case .loading:
                self?.spinner.isHidden = false
                
            case .sent:
                self?.spinner.isHidden = true
                self?.show(message: "safe_zone.migration_success".localized)
                self?.parentNavigationController?.popViewController(animated: true)
                
            case .success:
                self?.spinner.isHidden = true
                
            case let .complated(datas, balanceInfo):
                self?.spinner.isHidden = true
                self?.emptyView.isHidden = datas.count > 0
                self?.syncStateView.isHidden = true
                self?.viewItems = datas
                self?.balanceInfo = balanceInfo
                self?.tableView.reload()
                
            case let .failed(error):
                self?.spinner.isHidden = true
                self?.show(error: error)
            }
        }
    }
    
    @objc private func didTapProceed() {
        guard viewModel.state != .loading else { return }
        switch viewModel.redeemWalletType {
        case .local:
            viewModel.loalWalletRedeem(items: viewItems)

        case .other:
            viewModel.redeem()
        }
    }
    
    func show(error: String) {
        HudHelper.instance.show(banner: .error(string: error))
    }
    
    func show(message: String) {
        HudHelper.instance.show(banner: .success(string: message))
    }
}

// local
extension RedeemSafe3ViewController {
    func localRow(id: String, item: RedeemSafe3ViewModel.LocalSafe3WalletBalanceInfoItem, backgroundStyle: BaseThemeCell.BackgroundStyle = .lawrence, layoutMargins: UIEdgeInsets? = nil, autoDeselect: Bool = false, isFirst: Bool = false, isLast: Bool = false, action: (() -> Void)? = nil) -> RowProtocol {
        let layout: UIEdgeInsets = layoutMargins ?? UIEdgeInsets(top: .margin8, left: .margin16, bottom: .margin12, right: .margin16)
        let titleFont: UIFont = .subhead2
        let valueFont: UIFont = .subhead1
        return CellBuilderNew.row(
            rootElement: .vStack([
                .text { (component: TextComponent) -> () in
                    component.setContentHuggingPriority(.required, for: .vertical)
                    component.font = titleFont
                    component.textColor = .themeGray
                    component.text = "safe_zone.safe3.wallet_address".localized
                },
                .margin4,
                .text { (component: TextComponent) -> () in
                    component.font = valueFont
                    component.numberOfLines = 0
                    component.text = item.address
                },
                .text { (component: TextComponent) -> () in
                    component.setContentHuggingPriority(.required, for: .vertical)
                    component.font = titleFont
                    component.textColor = .themeGray
                    component.text = "safe_zone.safe4.account.balance".localized
                },
                .margin4,
                .text { (component: TextComponent) -> () in
                    component.font = valueFont
                    let value = (item.isEnabledRedeem ? item.balance.safe4FomattedAmount : item.balance.safe3FomattedAmount) + " SAFE"
                    if !item.existAvailable {
                        let attributeString: NSMutableAttributedString = NSMutableAttributedString(string: value)
                        attributeString.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: NSRange(location: 0, length: attributeString.length))
                        component.attributedText = attributeString
                    }else {
                        component.attributedText = nil
                        component.text = value
                    }
                },
                .text { (component: TextComponent) -> () in
                    component.setContentHuggingPriority(.required, for: .vertical)
                    component.font = titleFont
                    component.textColor = .themeGray
                    component.text = "safe_zone.locked_balance_with_record".localized(item.maxLockedCount)
                },
                .margin4,
                .text { (component: TextComponent) -> () in
                    component.font = valueFont
                    let value = item.lockBalance.safe3FomattedAmount + " SAFE"
                    if !item.existLocked {
                        let attributeString: NSMutableAttributedString = NSMutableAttributedString(string: value)
                        attributeString.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: NSRange(location: 0, length: attributeString.length))
                        component.attributedText = attributeString
                    }else {
                        component.attributedText = nil
                        component.text = value
                    }
                },
                .margin4,
                .text { (component: TextComponent) -> () in
                    component.setContentHuggingPriority(.required, for: .vertical)
                    component.font = titleFont
                    component.textColor = .themeGray
                    component.text = "safe_zone.petty_locked_balance".localized
                },
                .margin4,
                .text { (component: TextComponent) -> () in
                    component.font = valueFont
                    let value = item.pettyBalance.safe4FomattedAmount + " SAFE"
                    if !item.existPettyLocked {
                        let attributeString: NSMutableAttributedString = NSMutableAttributedString(string: value)
                        attributeString.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: NSRange(location: 0, length: attributeString.length))
                        component.attributedText = attributeString
                    }else {
                        component.attributedText = nil
                        component.text = value
                    }
                },
            ]),
            layoutMargins: layout,
            tableView: tableView,
            id: id,
            hash: item.address,
            autoDeselect: autoDeselect,
            dynamicHeight: { containerWidth in
                return CellBuilderNew.height(
                    containerWidth: containerWidth,
                    backgroundStyle: backgroundStyle,
                    text: item.address,
                    font: valueFont,
                    elements: [
                        .margin16,
                        .margin16,
                        .multiline,
                    ]
                ) + 180
            },
            bind: { cell in
                cell.set(backgroundStyle: backgroundStyle, isFirst: isFirst, isLast: isLast)
            },
            action: action
        )
    }
    
    func balacneRow(id: String, balanceInfo: RedeemSafe3ViewModel.LocalBalanceInfo, backgroundStyle: BaseThemeCell.BackgroundStyle = .lawrence, layoutMargins: UIEdgeInsets? = nil, autoDeselect: Bool = false, isFirst: Bool = false, isLast: Bool = false, action: (() -> Void)? = nil) -> RowProtocol {
        let layout: UIEdgeInsets = layoutMargins ?? UIEdgeInsets(top: .margin8, left: .margin16, bottom: .margin12, right: .margin16)
        let titleFont: UIFont = .subhead2
        return CellBuilderNew.row(
            rootElement: .vStack([
                .hStack([
                    .text { (component: TextComponent) -> () in
                        component.setContentHuggingPriority(.required, for: .horizontal)
                        component.font = titleFont
                        component.text = "safe_zone.available_balance".localized + "\(balanceInfo.availableValue)"
                    },
                    .text { (component: TextComponent) -> () in
                        component.font = titleFont
                        component.textAlignment = .right
                        component.text = "safe_zone.redeemable_balance".localized + "\(balanceInfo.redeemableValue)"
                    }
                ]),
                .hStack([
                    .text { (component: TextComponent) -> () in
                        component.setContentHuggingPriority(.required, for: .horizontal)
                        component.font = titleFont
                        component.text = "safe_zone.locked_balance".localized + "\(balanceInfo.lockedValue)"
                    },
                    .text { (component: TextComponent) -> () in
                        component.font = titleFont
                        component.textAlignment = .right
                        component.text = "safe_zone.redeemable_balance".localized + "\(balanceInfo.redeemableLockedValue)"
                    },
                ]),
            ]),
            layoutMargins: layout,
            tableView: tableView,
            id: id,
            height: 80,
            bind: { cell in
                cell.set(backgroundStyle: backgroundStyle, isFirst: true, isLast: isLast)
            }
        )
    }
}

// other
extension RedeemSafe3ViewController {
    var tipsRow: RowProtocol {
        StaticRow(
                cell: tipsCell,
                id: "node-tips",
                dynamicHeight: { [weak self] containerWidth in
                        self?.tipsCell.height(containerWidth: containerWidth) ?? 0
                }
        )
    }
    var stepRow: RowProtocol {
        StaticRow(
            cell: stepCell,
            id: "safe-step",
            height: .heightDoubleLineCell
        )
    }
    
    var privatekeyRows: [RowProtocol] {
        [
            tipsRow,
            stepRow,
            StaticRow(
                    cell: privateKeyInputCell,
                    id: "privatekey-input",
                    dynamicHeight: { [weak self] width in
                        self?.privateKeyInputCell.height(containerWidth: width) ?? 0
                    }
            ),
            StaticRow(
                    cell: privateKeyInputCautionCell,
                    id: "privatekey-caution",
                    dynamicHeight: { [weak self] width in
                        self?.privateKeyInputCautionCell.height(containerWidth: width) ?? 0
                    }
            )
        ]
    }

    var buttonSection: SectionProtocol {
        Section(
            id: "button",
            footerState: .margin(height: .margin32),
            rows: [
                StaticRow(
                    cell: buttonCell,
                    id: "button",
                    height: PrimaryButtonCell.height
                ),
            ]
        )
    }
}
extension RedeemSafe3ViewController: SectionsDataSource {
    
    func buildSections() -> [SectionProtocol] {
        var sections = [SectionProtocol]()
        if viewModel.redeemWalletType == .local {
            var rows = [RowProtocol]()

            rows.append(contentsOf: [tipsRow, stepRow])
            if let balanceInfo {
                let balacneRow = balacneRow(id: "balacneRow", balanceInfo: balanceInfo)
                rows.append(balacneRow)
            }
            let itemRows = viewItems.map{ localRow(id: "item", item: $0) }
            rows.append(contentsOf: itemRows)
            
            sections.append(Section(id: "items",rows: rows))
            
            if viewItems.count > 0 {
                if let safe4Address = viewModel.targetSafe4Address {
                    sections.append(
                        Section(
                            id: "safe4-address",
                            headerState: .margin(height: CGFloat.margin12),
                            rows: [
                                tableView.multilineRow(id: "safe4-address", title: "safe_zone.safe4_address".localized, value: safe4Address, backgroundStyle: .transparent, isFirst: true, isLast: true)
                            ]
                        )
                    )
                    sections.append(buttonSection)
                }
            }
        }
        
        if viewModel.redeemWalletType == .other {
            sections.append(Section(id: "privatekey",rows: privatekeyRows))
            
            if let info = viewModel.safe3BalanceInfo {
                sections.append(
                    Section(
                        id: "info",
                        headerState: .margin(height: CGFloat.margin12),
                        rows: [
                            tableView.multilineRow(id: "balance", title: "safe_zone.safe4..account.balance".localized, value: "\(info.balance.safe4FomattedAmount) SAFE", isFirst: true, isLineThrough: !viewModel.existAvailable),
                            tableView.multilineRow(id: "pettyBalance", title: "safe_zone.petty_locked_balance".localized, value: "\(info.pettyBalance.safe4FomattedAmount) SAFE", isFirst: true, isLineThrough: !viewModel.existPettyLocked),
                            tableView.multilineRow(id: "balance_lock", title: "safe_zone.account_balance_with_lock_record".localized(info.maxLockedCount), value: "\(info.lockBalance.safe4FomattedAmount) SAFE", isLineThrough: !viewModel.existLocked),
                            tableView.multilineRow(id: "node", title: "safe_zone.master_node".localized, value: "\(info.masterNodeLockBalance.safe4FomattedAmount) SAFE" ,isLast: true, isLineThrough: !viewModel.existMasterNode),
                        ]
                    )
                )
                if let safe4Address = viewModel.safe4Address {
                    let isLocalWallet = viewModel.localWalletSafe4Address == viewModel.targetSafe4Address
                    sections.append(
                        Section(
                            id: "safe4-address",
                            headerState: .text(text: "safe_zone.safe4_address".localized, topMargin: CGFloat.margin12, bottomMargin: CGFloat.margin12),
                            rows: [
                                tableView.multilineRow(id: "local-address", title: "safe_zone.local_wallet_address".localized, value: viewModel.localWalletSafe4Address,  isFirst: true, isShowCheckbox: true, isChoosed: isLocalWallet, action: {
                                    self.viewModel.choosed(address: self.viewModel.localWalletSafe4Address)
                                    self.tableView.reload()
                                }),
                                tableView.multilineRow(id: "privateKey-address", title: "safe_zone.private_key_address".localized, value: safe4Address, isLast: true, isShowCheckbox: true, isChoosed: viewModel.targetSafe4Address == safe4Address,action: {
                                    self.viewModel.choosed(address: safe4Address)
                                    self.tableView.reload()
                                })
                            ]
                        )
                    )
                    sections.append(buttonSection)
                }
            }
        }
        return sections
    }
}
