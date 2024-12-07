import UIKit
import Foundation
import SectionsTableView
import RxSwift
import RxCocoa
import ComponentKit
import HUD

class SuperNodeSendViewController: Safe4ConfirmBaseViewController {
    private let disposeBag = DisposeBag()
    private let viewModel: SuperNodeRegisterViewModel
    private let sendData: SuperNodeSendData
        
    init(viewModel: SuperNodeRegisterViewModel, sendData: SuperNodeSendData) {
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
            guard let data = self?.sendData else { return }
            guard self?.sendLock == false else { return }
            self?.viewModel.send(data: data)
            self?.sendLock = true
        }
    }
    
    var amountRows: [RowProtocol] {
        [
            tableView.universalRow62(id: "node_amount", image: .local(UIImage(named: "lock_48")), title: .custom("\(sendData.amount) SAFE", .title3, .themeBlackAndWhite), isFirst: true),
            tableView.multilineRow(id: "node_from", title: "safe_zone.safe4.send.from".localized, value: "safe_zone.safe4.account.regular".localized),
            tableView.multilineRow(id: "node_to", title: "safe_zone.safe4.send.to".localized, value: "safe_zone.safe4.account.lock".localized, isLast: true)
        ]
    }
    
    var nodeDetailInfoRows: [RowProtocol] {
        [
            tableView.multilineRow(id: "node_name", title: "safe_zone.safe4.node.detail.name".localized, value: "\(sendData.name)", isFirst: true),
            tableView.multilineRow(id: "node_title", title: "safe_zone.safe4.node.super.enode".localized, value: "\(sendData.ENODE)"),
            tableView.multilineRow(id: "node_desc", title: "safe_zone.safe4.node.super.desc".localized, value: "\(sendData.desc)"),
        ]
    }
    
    override func buildSections() -> [SectionProtocol] {
        
        let amountSection = Section(id: "amount", rows: amountRows)
        let infoSection = Section(id: "info", headerState: .margin(height: CGFloat.margin16), rows: nodeDetailInfoRows)
        return [amountSection, infoSection, buttonSection]
    }
}

private extension SuperNodeSendViewController {
    func sync(state: SuperNodeRegisterViewModel.State) {
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
        show(message: "safe_zone.safe4.node.super.register.success".localized)
        navigationController?.popToRootViewController(animated: true)
    }
    
    func show(error: String) {
        HudHelper.instance.show(banner: .error(string: error))
    }
    
    func show(message: String) {
        HudHelper.instance.show(banner: .success(string: message))
    }
}

