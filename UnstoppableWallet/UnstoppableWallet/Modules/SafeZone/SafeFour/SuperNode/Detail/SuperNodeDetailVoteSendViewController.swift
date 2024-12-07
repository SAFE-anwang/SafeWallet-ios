import UIKit
import Foundation
import SectionsTableView
import RxSwift
import RxCocoa
import ComponentKit
import HUD

class SuperNodeDetailVoteSendViewController: Safe4ConfirmBaseViewController {
    private let disposeBag = DisposeBag()
    private let viewModel: SuperNodeDetailViewModel
    private let lockRecordCell = SuperNodeDetailVoteLockRecordCell()

    private let sendData: SuperNodeSendData
    private let type: SuperNodeDetailViewModel.VoteType
    var partnerCompleted: (() -> Void)?

    init(viewModel: SuperNodeDetailViewModel, type: SuperNodeDetailViewModel.VoteType) {
        self.viewModel = viewModel
        self.sendData = viewModel.sendData
        self.type = type
        super.init()
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "safe_zone.safe4.proposal.vote.title".localized
        buttonCell.title = "safe_zone.safe4.send.button".localized
        tableView.registerCell(forClass: SuperNodeDetailVoteLockRecordCell.self)

        tableView.buildSections()
        tableView.reload()
                
        subscribe(disposeBag, viewModel.stateDriver) { [weak self] in self?.sync(state: $0) }

        didTapSend = { [weak self] in
            guard let strongSelf = self else { return }
            guard strongSelf.sendLock == false else { return }
            
            switch strongSelf.type {
            case let .safe(amount):
                strongSelf.viewModel.safeVote(amount: amount)
                
            case .lockRecord:
                strongSelf.viewModel.lockRecordVote()
            }
            self?.sendLock = true
        }
    }
    
    
    func lockRecordVoteRows(amount: String) -> [RowProtocol] {
        [
            tableView.universalRow62(id: "node_amount", title: .custom("\(amount) SAFE", .title3, .themeBlackAndWhite), isFirst: true),
            tableView.multilineRow(id: "node_from", title: "safe_zone.safe4.send.from".localized, value: "safe_zone.safe4.account.lock".localized),
            StaticRow(
                cell: lockRecordCell,
                id: "locked_Rows",
                height: lockRecordCell.height()
            ),
            tableView.multilineRow(id: "vote_to", title: "safe_zone.safe4.vote.to".localized, value: "safe_zone.safe4.node.super.title".localized, isLast: true)

        ]
    }
    
    func safeVoteRows(amount: String) -> [RowProtocol] {
        [
            tableView.universalRow62(id: "node_amount", image: .local(UIImage(named: "lock_48")), title: .custom("\(amount) SAFE", .title3, .themeBlackAndWhite), isFirst: true),
            tableView.multilineRow(id: "node_from", title: "safe_zone.safe4.send.from".localized, value: "safe_zone.safe4.account.regular".localized),
            tableView.multilineRow(id: "node_to", title: "safe_zone.safe4.send.tosafe_zone.safe4.send.to".localized, value: "safe_zone.safe4.account.lock".localized),
            tableView.multilineRow(id: "vote_to", title: "safe_zone.safe4.vote.to".localized, value: "safe_zone.safe4.node.super.title".localized, isLast: true)
        ]
    }
    
    var nodeDetailInfoRows: [RowProtocol] {
        [
            tableView.multilineRow(id: "node_name", title: "balance.sort.az".localized, value: "\(sendData.name)", isFirst: true),
            tableView.multilineRow(id: "node_title", title: "safe_zone.safe4.node.super.enode".localized, value: "\(sendData.ENODE)"),
            tableView.multilineRow(id: "node_desc", title: "safe_zone.safe4.node.super.desc".localized, value: "\(sendData.desc)"),
        ]
    }
    
    override func buildSections() -> [SectionProtocol] {
        
        var rows = [RowProtocol]()
        switch type {
        case let .safe(amount):
            rows = safeVoteRows(amount: amount.safe4FormattedAmount)
            
        case let .lockRecord(items):
            lockRecordCell.bind(viewItems: items)
            let total = items.map{$0.info.amount}.reduce(0, +).safe4FomattedAmount
            rows = lockRecordVoteRows(amount: total)
        }
        
        let amountSection = Section(id: "amount", rows: rows)
        let infoSection = Section(id: "info", headerState: .margin(height: CGFloat.margin16), rows: nodeDetailInfoRows)
        return [amountSection, infoSection, buttonSection]
    }
}

private extension SuperNodeDetailVoteSendViewController {
    private func sync(state: SuperNodeDetailViewModel.State) {
        DispatchQueue.main.async { [weak self] in
            switch state {
            case .loading:()
            case let .failed(error):
                self?.show(error: error)
                
            case .partnerCompleted:()
                self?.partnerCompleted?()
            case .completed(_): ()
            case .voteCompleted:
                self?.show(message: "safe_zone.safe4.vote.success".localized)
                self?.navigationController?.popToViewController(ofClass: SuperNodeTabViewController.self)
            case .lockRecoardCompleted(_): ()
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


class SuperNodeDetailVoteLockRecordCell: BaseThemeCell {
    private let disposeBag = DisposeBag()
    private let itemsPerRow: CGFloat = 2
    private let collectionView: UICollectionView
    private static let gridRowHeight: CGFloat = .heightSingleLineCell
    private var viewItems = [SuperNodeDetailViewModel.LockRecoardItem]()
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .vertical
        layout.sectionInset = .zero
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        
        set(backgroundStyle: .lawrence, isFirst: false, isLast: false)
        
        collectionView.delegate = self
        collectionView.dataSource = self
        collectionView.backgroundColor = .clear
        collectionView.scrollsToTop = false
        collectionView.registerCell(forClass: LockRecordCell.self)
        wrapperView.addSubview(collectionView)
        collectionView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
    }
    
    func height() -> CGFloat {
        let numberOfRows = Int(ceil(Double(viewItems.count) / Double(2)))
        return CGFloat(numberOfRows) * Self.gridRowHeight
    }
    
    func bind(viewItems: [SuperNodeDetailViewModel.LockRecoardItem]) {
        self.viewItems = viewItems
        collectionView.reloadData()
    }
}

extension SuperNodeDetailVoteLockRecordCell: UICollectionViewDelegateFlowLayout, UICollectionViewDataSource, UICollectionViewDelegate {

    func collectionView(_: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        viewItems.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: String(describing: LockRecordCell.self), for: indexPath)
        if let cell = cell as? LockRecordCell {
            cell.bind(item: viewItems[indexPath.item])
        }
        return cell
    }

    func collectionView(_: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        if let cell = cell as? LockRecordCell {
            cell.bind(item: viewItems[indexPath.item])
        }
    }

    func collectionView(_ collectionView: UICollectionView, layout _: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        let minWidth = collectionView.frame.size.width / itemsPerRow - 1
        return CGSize(width: minWidth, height: Self.gridRowHeight)
    }

    func collectionView(_: UICollectionView, layout _: UICollectionViewLayout, minimumInteritemSpacingForSectionAt _: Int) -> CGFloat {
        0.01
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, minimumLineSpacingForSectionAt section: Int) -> CGFloat {
        0.01
    }
}
