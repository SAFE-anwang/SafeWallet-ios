import UIKit
import Foundation
import SectionsTableView
import RxSwift
import RxCocoa
import ComponentKit
import HUD

class MasterNodeDetailSendViewController: Safe4ConfirmBaseViewController {
    private let disposeBag = DisposeBag()
    private let viewModel: MasterNodeDetailViewModel
    private let sendData: MasterNodeSendData
    private let sendAmount: Float
    var partnerCompleted: (() -> Void)?

    init(viewModel: MasterNodeDetailViewModel, sendAmount: Float) {
        self.viewModel = viewModel
        self.sendData = viewModel.sendData
        self.sendAmount = sendAmount
        super.init()
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "safe_zone.safe4.partner.join".localized
        buttonCell.title = "safe_zone.safe4.send.button".localized
        tableView.buildSections()
        tableView.reload()
                
        subscribe(disposeBag, viewModel.stateDriver) { [weak self] in self?.sync(state: $0) }

        didTapSend = { [weak self] in
            guard let strongSelf = self else { return }
            guard strongSelf.sendLock == false else { return }
            self?.viewModel.joinPartner(value: strongSelf.sendAmount)
            self?.sendLock = true
        }
    }
    
    var amountRows: [RowProtocol] {
        [
            tableView.universalRow62(id: "node_amount", image: .local(UIImage(named: "lock_48")), title: .custom("\(sendAmount) SAFE", .title3, .themeBlackAndWhite), isFirst: true),
            tableView.multilineRow(id: "node_from", title: "safe_zone.safe4.send.from".localized, value: "safe_zone.safe4.account.regular".localized),
            tableView.multilineRow(id: "node_to", title: "safe_zone.safe4.send.to".localized, value: "safe_zone.safe4.account.lock".localized, isLast: true)
        ]
    }
    
    var nodeDetailInfoRows: [RowProtocol] {
        [
            tableView.multilineRow(id: "node_title", title: "safe_zone.safe4.node.mater.enode".localized, value: "\(sendData.ENODE)", isFirst: true),
            tableView.multilineRow(id: "node_desc", title: "safe_zone.safe4.node.mater.desc".localized, value: "\(sendData.desc)"),
        ]
    }
    
    override func buildSections() -> [SectionProtocol] {
        
        let amountSection = Section(id: "amount", rows: amountRows)
        let infoSection = Section(id: "info", headerState: .margin(height: CGFloat.margin16), rows: nodeDetailInfoRows)
        return [amountSection, infoSection, buttonSection]
    }
}

private extension MasterNodeDetailSendViewController {
    private func sync(state: MasterNodeDetailViewModel.State) {
        DispatchQueue.main.async { [weak self] in
            switch state {
            case .loading:()
            case let .failed(error):
                self?.show(error: error)
                
            case .partnerCompleted:
                self?.show(message: "safe_zone.safe4.partner.join.success".localized)
                self?.partnerCompleted?()
            }
        }
    }
    
    func show(error: String) {
        HudHelper.instance.show(banner: .error(string: error))
    }
    
    func show(message: String) {
        HudHelper.instance.show(banner: .success(string: message))
    }
}

