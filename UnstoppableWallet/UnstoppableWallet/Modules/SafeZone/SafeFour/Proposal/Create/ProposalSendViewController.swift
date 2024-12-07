import Foundation
import SectionsTableView
import RxSwift
import RxCocoa
import ComponentKit
import HUD

class ProposalSendViewController: Safe4ConfirmBaseViewController {
    private let disposeBag = DisposeBag()
    private let viewModel: ProposalCreateViewModel
    private let sendData: ProposalSendData
        
    init(viewModel: ProposalCreateViewModel, sendData: ProposalSendData) {
        self.viewModel = viewModel
        self.sendData = sendData
        super.init()
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "create_wallet.create".localized
        tableView.buildSections()
        tableView.reload()

        subscribe(disposeBag, viewModel.stateDriver) { [weak self] in self?.sync(state: $0) }
        didTapSend = { [weak self] in
            guard let strongSelf = self else { return }
            guard strongSelf.sendLock == false else { return }
            strongSelf.sendLock = true
            strongSelf.viewModel.send(data: strongSelf.sendData)
        }
    }
    
    func sync(state: ProposalCreateViewModel.State) {
        DispatchQueue.main.async { [weak self] in
            switch state {
            case .loading: ()
            case .completed:
                self?.showSuccess()
            case let .failed(error):
                self?.show(error: error)
                self?.navigationController?.popViewController(animated: true)
            }
            self?.sendLock = false
        }
    }
    
    func showSuccess() {
        show(message: "safe_zone.safe4.creat.success".localized)
        navigationController?.popToRootViewController(animated: true)
    }
    
    func show(error: String) {
        HudHelper.instance.show(banner: .error(string: error))
    }
    
    func show(message: String) {
        HudHelper.instance.show(banner: .success(string: message))
    }
    
    var amountRows: [RowProtocol] {
        [
            tableView.universalRow62(id: "proposal_amount",  title: .custom("1 SAFE", .title3, .themeBlackAndWhite), isFirst: true),
            tableView.multilineRow(id: "proposal_from", title: "safe_zone.safe4.send.from".localized, value: "safe_zone.safe4.account.regular".localized),
            tableView.multilineRow(id: "proposal_to", title: "safe_zone.safe4.send.to".localized, value: "safe_zone.safe4.proposal.contract".localized, isLast: true)
        ]
    }
    
    var nodeDetailInfoRows: [RowProtocol] {
        [
            tableView.multilineRow(id: "proposal_title", title: "safe_zone.safe4.proposal.detail.info.title".localized, value: "\(sendData.title)", isFirst: true),
            tableView.multilineRow(id: "proposal_desc", title: "safe_zone.safe4.proposal.detail.info.desc".localized, value: "\(sendData.desc)"),
            tableView.multilineRow(id: "proposal_amount", title: "safe_zone.safe4.proposal.detail.info.apply.num".localized, value: "\(sendData.amount)"),
            tableView.multilineRow(id: "proposal_time", title: "safe_zone.safe4.proposal.detail.info.method".localized, value: "\(sendData.payTypeDesc)", isLast: true)
        ]
    }
    
    override func buildSections() -> [SectionProtocol] {
        
        let amountSection = Section(id: "amount", rows: amountRows)
        let infoSection = Section(id: "info", headerState: .margin(height: CGFloat.margin16), rows: nodeDetailInfoRows)
        return [amountSection, infoSection, buttonSection]
    }
}
