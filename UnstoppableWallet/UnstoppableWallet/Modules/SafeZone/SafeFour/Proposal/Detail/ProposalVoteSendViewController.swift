import Foundation
import UIKit
import SectionsTableView
import RxSwift
import RxCocoa
import ComponentKit
import HUD

class ProposalVoteSendViewController: Safe4ConfirmBaseViewController {
    private let disposeBag = DisposeBag()
    private let viewModel: ProposalDetailViewModel
    private let sendData: ProposalSendData
    private let voteState: ProposalDetailViewModel.VoteState
    init(viewModel: ProposalDetailViewModel, voteState: ProposalDetailViewModel.VoteState) {
        self.viewModel = viewModel
        self.sendData = viewModel.sendData
        self.voteState = voteState
        super.init()
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "safe_zone.safe4.proposal.vote.title".localized
        buttonCell.title = "safe_zone.safe4.send.button".localized

        tableView.buildSections()
        tableView.reload()

        subscribe(disposeBag, viewModel.stateDriver) { [weak self] in self?.sync(state: $0) }
        didTapSend = { [weak self] in
            guard let strongSelf = self else { return }
            guard strongSelf.sendLock == false else { return }
            strongSelf.viewModel.vote(result: strongSelf.voteState)
            strongSelf.sendLock = true
        }
    }
    
    func sync(state: ProposalDetailViewModel.State) {
        DispatchQueue.main.async { [weak self] in
            switch state {
            case .loading: ()
            case .voteCompleted:
                self?.showSuccess()
            case let .failed(error):
                self?.show(error: error)
                self?.navigationController?.popToViewController(ofClass: ProposalTabViewController.self)
            case .completed(_): ()
            }
            self?.sendLock = false
        }
    }
    
    func showSuccess() {
        show(message: "safe_zone.safe4.proposal.vote.completed".localized)
        navigationController?.popToViewController(ofClass: ProposalTabViewController.self)
    }
    
    func show(error: String) {
        HudHelper.instance.show(banner: .error(string: error))
    }
    
    func show(message: String) {
        HudHelper.instance.show(banner: .success(string: message))
    }
    
    var voteRows: [RowProtocol] {
        [
            tableView.universalRow48(id: "proposal_vote",  image: .local(UIImage(named: voteState.image)?.withTintColor(voteState.color)), title: .custom(voteState.title, .headline2, voteState.color), isFirst: true, isLast: true),
        ]
    }
    
    var nodeDetailInfoRows: [RowProtocol] {
        [
            tableView.multilineRow(id: "proposal_title", title: "safe_zone.safe4.proposal.detail.info.title".localized, value: "\(sendData.title)", isFirst: true),
            tableView.multilineRow(id: "proposal_desc", title: "safe_zone.safe4.proposal.detail.info.desc".localized, value: "\(sendData.desc)"),
            tableView.multilineRow(id: "proposal_amount", title: "safe_zone.safe4.proposal.detail.info.num".localized, value: "\(sendData.amount)"),
            tableView.multilineRow(id: "proposal_time", title: "safe_zone.safe4.proposal.detail.info.method".localized, value: "\(sendData.payTypeDesc)", isLast: true)
        ]
    }
    
    override func buildSections() -> [SectionProtocol] {
        
        let amountSection = Section(id: "amount", rows: voteRows)
        let infoSection = Section(id: "info", headerState: .margin(height: CGFloat.margin16), rows: nodeDetailInfoRows)
        return [amountSection, infoSection, buttonSection]
    }
}

