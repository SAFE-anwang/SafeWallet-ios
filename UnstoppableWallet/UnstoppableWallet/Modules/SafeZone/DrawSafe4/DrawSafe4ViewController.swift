import UIKit
import RxSwift
import SectionsTableView

class DrawSafe4ViewController: ThemeViewController {
    private let viewModel: DrawSafe4ViewModel
    private let disposeBag = DisposeBag()
    private let addressCell = Safe4BaseInputCell()
    private let addressCautionCell = FormCautionCell()

    private let tableView = SectionsTableView(style: .grouped)
    private let tipsCell = Safe4WarningCell()
    private let buttonCell = PrimaryButtonCell()
    
    private var drawSafe4Info: DrawSafe4Info?
    var onDismiss: (() -> Void)?
    
    private var isLoaded = false

    init(viewModel: DrawSafe4ViewModel) {
        self.viewModel = viewModel
        super.init()
        hidesBottomBarWhenPushed = true
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "safe_zone.safe4.claim".localized
        tipsCell.bind(text: "safe_zone.safe4.claim_once_per_day".localized, type: .normal)
        addressCell.setTitle(text: "safe_zone.safe4.wallet_address".localized)
        addressCell.setInput(keyboardType: .default, placeholder: "safe_zone.enter_safe_address".localized)
        addressCell.onChangeHeight = { [weak self] in self?.reloadTable()}
        addressCautionCell.onChangeHeight = { [weak self] in self?.reloadTable() }
        
        view.addSubview(tableView)
        tableView.snp.makeConstraints { maker in
            maker.edges.equalToSuperview()
        }
        tableView.allowsSelection = false
        tableView.separatorStyle = .none
        tableView.backgroundColor = .clear
        tableView.sectionDataSource = self
        
        buttonCell.set(style: .yellow)
        buttonCell.title = "safe_zone.claim".localized
        buttonCell.onTap = { [weak self] in
            self?.viewModel.drawSafe4()
        }
        
        didLoad()
        addressCell.onChangeText = { [weak self] text in
            self?.viewModel.onChange(text: text)
        }
        
        subscribe(disposeBag, viewModel.stateObservable) { [weak self] in
            self?.sync(state: $0)
        }
        
        subscribe(disposeBag, viewModel.addressDriver) { [weak self] in
            self?.addressCell.setInput(value: $0)
            self?.drawSafe4Info = nil
            self?.buttonCell.title = "safe_zone.claim".localized
            self?.buttonCell.isEnabled = true
        }
        
        subscribe(disposeBag, viewModel.addressCautionDriver) { [weak self] in
            self?.addressCell.set(cautionType: $0?.type)
            self?.addressCautionCell.set(caution: $0)
            self?.reloadTable()
        }
        addressCell.setInput(value: viewModel.address)
    }
    
    private func sync(state: DrawSafe4Service.State) {
        DispatchQueue.main.async { [weak self] in
            switch state {
            case .loading:
                self?.drawSafe4Info = nil
                self?.tableView.reload()
                
            case let .success(info):
                self?.drawSafe4Info = info
                self?.tableView.reload()
                self?.buttonCell.title = "safe_zone.claim_success".localized
                self?.buttonCell.isEnabled = false
                HudHelper.instance.show(banner: .success(string: "safe_zone.claim_success".localized))
                
            case let .failed(error):
                self?.drawSafe4Info = nil
                self?.tableView.reload()
                HudHelper.instance.show(banner: .error(string: error ?? ""))
            }
        }
    }
    
    private func didLoad() {
        isLoaded = true
        tableView.reload()
    }
    
    private func reloadTable() {
        guard isLoaded else { return }
        UIView.animate(withDuration: 0) {
            self.tableView.beginUpdates()
            self.tableView.endUpdates()
        }
    }
}

extension DrawSafe4ViewController: SectionsDataSource {
    
    func buildSections() -> [SectionProtocol] {
        var sections = [SectionProtocol]()
        sections.append(addressSection)
        if drawSafe4Info != nil {
            sections.append(infoSection)
        }
        sections.append(buttonSection)
        return sections
    }

    var addressSection: SectionProtocol {
        Section(
            id: "address",
            footerState: .margin(height: .margin32),
            rows: [
                StaticRow(
                        cell: tipsCell,
                        id: "node-tips",
                        dynamicHeight: { [weak self] containerWidth in
                                self?.tipsCell.height(containerWidth: containerWidth) ?? 0
                        }
                ),
                StaticRow(
                        cell: addressCell,
                        id: "address-input",
                        dynamicHeight: { [weak self] containerWidth in
                            self?.addressCell.height(containerWidth: containerWidth) ?? 0
                        }
                ),
                StaticRow(
                        cell: addressCautionCell,
                        id: "address-tips",
                        dynamicHeight: { [weak self] containerWidth in
                            self?.addressCautionCell.height(containerWidth: containerWidth) ?? 0
                        }
                )
            ]
        )
    }
    
    var infoSection: SectionProtocol {
        Section(
            id: "info",
            footerState: .margin(height: .margin32),
            rows: [
                tableView.multilineRow(id: "amount", title: "safe_zone.claim_amount".localized, value: drawSafe4Info?.amount ?? ""),
                tableView.multilineRow(id: "tx_hash", title: "safe_zone.tx_hash".localized, value: drawSafe4Info?.transactionHash ?? ""),
                tableView.multilineRow(id: "time", title: "safe_zone.claim_time".localized, value: drawSafe4Info?.time ?? ""),
                tableView.multilineRow(id: "sender", title: "safe_zone.sender".localized, value: drawSafe4Info?.from ?? ""),
                tableView.multilineRow(id: "revicer", title: "safe_zone.receiver".localized, value: drawSafe4Info?.address ?? ""),
                tableView.multilineRow(id: "nonce", title: "Nonce".localized, value: "\(drawSafe4Info?.nonce ?? 0)"),
            ]
        )
    }

    var buttonSection: SectionProtocol {
        Section(
            id: "button",
            footerState: .margin(height: .margin32),
            rows: [
                StaticRow(
                    cell: buttonCell,
                    id: "send",
                    height: PrimaryButtonCell.height
                )
            ]
        )
    }
}
