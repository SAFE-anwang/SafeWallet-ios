import Foundation
import UIKit
import SectionsTableView
import SnapKit
import ThemeKit
import UIExtensions
import RxSwift
import RxCocoa
import ComponentKit
import HUD

class SuperNodeDetailViewController: ThemeViewController {
    
    private let disposeBag = DisposeBag()
    private let viewType: SuperNodeDetailViewModel.ViewType
    private let viewModel: SuperNodeDetailViewModel
    private let tableView = SectionsTableView(style: .plain)
    private var viewItems = [SuperNodeDetailViewModel.ViewItem]()
    private var voterItems = [SuperNodeDetailViewModel.VoterInfoItem]()
    private let emptyView = PlaceholderView()
    private let incentiveCell = SuperNodeDetailIncentiveCell()
    
    private let lockRecordCell = SuperNodeVoteLockRecordCell()
    private let safeVoteCell = SuperNodeSafeVoteCell()

    private let joinPartnerCell = Safe4NodeJoinPartnerViewCell()
    private let safeVoteTipsCell = Safe4WarningCell()
        
    private let recordHeaderView = SuperNodeDetailRecordHeaderView(hasTopSeparator: true)
    private let voteHeaderView = SuperNodeDetailVoteHeaderView()
    private var _tab: SuperNodeDetailRecordHeaderView.Tab = .creator
    private var voteType: SuperNodeDetailVoteHeaderView.VoteType = .safe
    
    private let tipsCell = Safe4WarningCell()
    
    weak var parentNavigationController: UINavigationController?
    
    var needReload: (() -> Void)?
    
    init(viewModel: SuperNodeDetailViewModel, viewType: SuperNodeDetailViewModel.ViewType) {
        self.viewModel = viewModel
        self.viewType = viewType
        super.init()
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "safe_zone.safe4.detail".localized
                
        view.addSubview(tableView)
        tableView.snp.makeConstraints { maker in
            maker.edges.equalToSuperview()
        }
        emptyView.frame = CGRect(x: 0, y: 0, width: view.width, height: 250)
        emptyView.image = UIImage(named: "safe4_empty")
        emptyView.text = "safe_zone.safe4.empty.description".localized
        emptyView.isHidden = true
        
        tableView.separatorStyle = .none
        tableView.backgroundColor = .clear
        tableView.tableFooterView = emptyView
        tableView.registerCell(forClass: SuperNodeVoteLockRecordCell.self)
        tableView.sectionDataSource = self
        tableView.buildSections()

        recordHeaderView.onSelect = { [weak self] tab in
            self?._tab = tab
            switch tab {
            case .creator:
                self?.emptyView.isHidden = (self?.viewItems.count ?? 0) > 0 ? true : false
            case .voter:
                self?.emptyView.isHidden = (self?.voterItems.count ?? 0) > 0 ? true : false
            }
            self?.tableView.reload()
        }
        
        voteHeaderView.onSelect = { [weak self] type in
            self?.voteType = type
            self?.tableView.reload()
        }
        
        viewItems = viewModel.viewItems
        emptyView.isHidden = viewItems.count > 0 ? true : false
        incentiveCell.bind(creator: viewModel.detailInfo.info.incentivePlan.creator, 
                           partner: viewModel.detailInfo.info.incentivePlan.partner,
                           voter: viewModel.detailInfo.info.incentivePlan.voter
        )
        tableView.reload()
        viewModel.refresh()
        
        subscribe(disposeBag, viewModel.stateDriver) { [weak self] in self?.sync(state: $0) }
        
        subscribe(disposeBag, viewModel.balanceDriver) { [weak self] in
            if let strongSelf = self {
                let maximumValue = Float(strongSelf.viewModel.detailInfo.foundersBalanceAmount.cgFloatValue)
                strongSelf.joinPartnerCell.bind(minValue: 500, step: 500, minimumValue: 0, maximumValue: maximumValue, balance: $0)
                strongSelf.safeVoteCell.update(balance: $0)
            }
        }
        
        joinPartnerCell.joinPartner = { [weak self] in
                self?.onTapJoinPartner(sendAmount:  $0)
        }

        tipsCell.bind(text: "safe_zone.safe4.node.super.vote.locked.tips".localized, type: .normal)
        safeVoteTipsCell.bind(text: "safe_zone.safe4.node.super.vote.locked.recoard.tips".localized, type: .normal)
        
        lockRecordCell.loadMore = { [weak self] in
            self?.viewModel.loadMoreLockRecord()
        }
        
        lockRecordCell.selectAll = { [weak self]  in
            self?.viewModel.selectAllLockRecord($0)
        }

        lockRecordCell.lockRecordVote = { [weak self] in
            guard let strongSelf = self else { return }
            self?.onTapVote(type: .lockRecord(items: strongSelf.viewModel.selectedLockRecoardItems))
        }
        
        safeVoteCell.safeVote = { [weak self]  in
            self?.onTapVote(type:.safe(amount: $0))
        }
    }
    
    private func sync(state: SuperNodeDetailViewModel.State) {
        DispatchQueue.main.async { [weak self] in
            switch state {
            case .loading:()
            case let .failed(error):
                self?.show(error: error)
                
            case let .completed(datas):
                self?.voterItems = datas
                self?.emptyView.isHidden = datas.count > 0 ? true : false
                self?.tableView.reload()
                
            case .voteCompleted:()

            case .partnerCompleted:()
                
            case let .lockRecoardCompleted(datas):
                self?.lockRecordCell.bind(viewItems: datas)
                self?.tableView.reload()
            }
        }
    }
    
    private func show(error: String) {
        HudHelper.instance.show(banner: .error(string: error))
    }
    
    private func show(message: String) {
        HudHelper.instance.show(banner: .success(string: message))
    }
}
extension SuperNodeDetailViewController {
    
    private func onTapJoinPartner(sendAmount: Float) {
        let vc = SuperNodeDetailSendViewController(viewModel: viewModel, sendAmount: sendAmount)
        vc.partnerCompleted = { [weak self] in
            self?.tableView.reload()
            self?.navigationController?.popToViewController(ofClass: SuperNodeTabViewController.self)

        }
        navigationController?.pushViewController(vc, animated: true)
    }
    
    private func onTapVote(type: SuperNodeDetailViewModel.VoteType) {
        let vc = SuperNodeDetailVoteSendViewController(viewModel: viewModel, type: type)
        vc.partnerCompleted = { [weak self] in
            self?.tableView.reload()
            self?.navigationController?.popToViewController(ofClass: SuperNodeTabViewController.self)
        }
        navigationController?.pushViewController(vc, animated: true)
    }
}
private extension SuperNodeDetailViewController {
    
    func buildRecordCell(viewItem: SuperNodeDetailViewModel.ViewItem) -> BaseSelectableThemeCell {
        let cell = BaseSelectableThemeCell()
        cell.selectionStyle = .none
        cell.set(backgroundStyle: .lawrence)
        CellBuilderNew.buildStatic(cell: cell, rootElement: .hStack([
            .text { (component: TextComponent) -> () in
                component.font = .subhead1
                component.setContentHuggingPriority(.required, for: .horizontal)
                component.setContentCompressionResistancePriority(.required, for: .horizontal)
                component.text = viewItem.id
            },
            .text { (component: TextComponent) -> () in
                component.font = .subhead1
                component.textColor = viewItem.isSelf ? .themeIssykBlue : .themeGray
                component.numberOfLines = 0
                component.setContentHuggingPriority(.defaultLow, for: .horizontal)
                component.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
                component.text = viewItem.address
            },
            .text { (component: TextComponent) -> () in
                component.font = .subhead1
                component.textAlignment = .right
                component.setContentHuggingPriority(.defaultHigh, for: .horizontal)
                component.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
                component.text = viewItem.safeAmount
            }
        ]))
        return cell
    }
    
    func buildVoterCell(viewItem: SuperNodeDetailViewModel.VoterInfoItem) -> BaseSelectableThemeCell {
        let cell = BaseSelectableThemeCell()
        cell.selectionStyle = .none
        cell.set(backgroundStyle: .lawrence)
        CellBuilderNew.buildStatic(cell: cell, rootElement: .hStack([
            .text { (component: TextComponent) -> () in
                component.font = .subhead1
                component.textColor = viewItem.isSelf ? .themeIssykBlue : .themeGray
                component.numberOfLines = 0
                component.setContentHuggingPriority(.defaultLow, for: .horizontal)
                component.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
                component.text = viewItem.address
            },
            .text { (component: TextComponent) -> () in
                component.font = .subhead1
                component.textAlignment = .right
                component.setContentHuggingPriority(.defaultHigh, for: .horizontal)
                component.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
                component.text = viewItem.amount
            }
        ]))
        return cell
    }
    
    func baseInfoCellRow(id: String, title: String, value: String, isFirst: Bool = false, isLast: Bool = false) -> RowProtocol {
        tableView.universalRow48(id: id, title: .subhead2(title, color: .themeGray), value: .subhead1(value), isFirst: isFirst, isLast: isLast)
    }
        
    func sectionHeaderCellRow(id: String, tableView: UITableView, title: String, isFirst: Bool = false, isLast: Bool = false) -> RowProtocol {
        let backgroundStyle: BaseThemeCell.BackgroundStyle = .lawrence
        let titleFont: UIFont = .headline2

        return CellBuilderNew.row(
            rootElement:  .hStack([
                .text { (component: TextComponent) -> () in
                    component.font = titleFont
                    component.setContentHuggingPriority(.required, for: .horizontal)
                    component.numberOfLines = 0
                    component.text = title
                },
            ]),
            tableView: tableView,
            id: id,
            hash: title,
            dynamicHeight: { containerWidth in
                return CellBuilderNew.height(
                    containerWidth: containerWidth,
                    backgroundStyle: backgroundStyle,
                    text: title,
                    font: titleFont,
                    elements: [
                        .margin16,
                        .margin16,
                        .multiline,
                    ]
                )
            },
            bind: { cell in
                cell.set(backgroundStyle: backgroundStyle, isFirst: isFirst, isLast: isLast)
            }
        )
    }
    
    func row(viewItem: SuperNodeDetailViewModel.ViewItem) -> RowProtocol {
        StaticRow(
                cell: buildRecordCell(viewItem: viewItem),
                id: "basic_Rows",
                height: .heightCell56
        )
    }
    
    func row(viewItem: SuperNodeDetailViewModel.VoterInfoItem) -> RowProtocol {
        StaticRow(
                cell: buildVoterCell(viewItem: viewItem),
                id: "voter_Rows",
                height: .heightCell56
        )
    }
    
    var joinPartnerRows: [RowProtocol] {
        [
            sectionHeaderCellRow(id: "header", tableView: tableView, title: "safe_zone.safe4.node.super.vote.locked.join".localized, isFirst: true),
            tableView.multilineRow(id: "node_balance", title: "超级节点剩余份额".localized, value: viewModel.detailInfo.foundersBalanceAmount.safe4FormattedAmount + " SAFE"),
            StaticRow(
                    cell: joinPartnerCell,
                    id: "node_join",
                    height: joinPartnerCell.height()
            ),
            
        ]
    }
    
    var safeVoteRows: [RowProtocol] {
        [
            sectionHeaderCellRow(id: "header", tableView: tableView, title: "safe_zone.safe4.node.super.vote.safe".localized, isFirst: true),
            StaticRow(
                    cell: safeVoteTipsCell,
                    id: "safe_vote_tips",
                    dynamicHeight: { [weak self] containerWidth in
                            self?.safeVoteTipsCell.height(containerWidth: containerWidth) ?? 0
                    }
            ),
            StaticRow(
                cell: safeVoteCell,
                id: "vote_Rows",
                height: safeVoteCell.height()
            )
        ]
    }
    
    var lockRecordVoteRows: [RowProtocol] {
        [
            sectionHeaderCellRow(id: "header", tableView: tableView, title: "safe_zone.safe4.node.super.vote.locked.recoard.choose".localized, isFirst: true),
            StaticRow(
                    cell: tipsCell,
                    id: "locked_tips",
                    dynamicHeight: { [weak self] containerWidth in
                            self?.tipsCell.height(containerWidth: containerWidth) ?? 0
                    }
            ),
            StaticRow(
                cell: lockRecordCell,
                id: "locked_Rows",
                height: lockRecordCell.height()
            )
        ]
    }
    
    var nodeDetailInfoRows: [RowProtocol] {
        [
            sectionHeaderCellRow(id: "header", tableView: tableView, title: "safe_zone.safe4.node.detail".localized, isFirst: true),
            baseInfoCellRow(id: "node_id", title: "safe_zone.safe4.node.id".localized, value: viewModel.detailInfo.id),
            baseInfoCellRow(id: "node_state", title: "safe_zone.safe4.node.status".localized, value: viewModel.detailInfo.nodeState.title),
            tableView.multilineRow(id: "node_address", title: "safe_zone.safe4.node.address".localized, value: viewModel.detailInfo.info.addr.address, subTextColor: .themeIssykBlue, action: { [self] in
                CopyHelper.copyAndNotify(value: viewModel.detailInfo.info.addr.address)
            }),
            tableView.multilineRow(id: "node_creater", title: "节点名称:".localized, value: viewModel.detailInfo.info.name),
            tableView.multilineRow(id: "node_creater", title: "safe_zone.safe4.node.creator".localized + ": ", value: viewModel.detailInfo.info.creator.address, subTextColor: .themeIssykBlue, action: { [self] in
                CopyHelper.copyAndNotify(value: viewModel.detailInfo.info.creator.address)
            }),
            baseInfoCellRow(id: "node_amount", title: "safe_zone.safe4.creator.pledge".localized, value: viewModel.detailInfo.foundersTotalAmount.safe4FormattedAmount + " SAFE"),
            baseInfoCellRow(id: "node_vote", title: "safe_zone.safe4.vote.pledge".localized, value: viewModel.detailInfo.totalAmount.safe4FomattedAmount + " SAFE"),
            tableView.multilineRow(id: "node_enode",  title: "safe_zone.safe4.node.enode".localized, value: viewModel.detailInfo.info.enode, subTextColor: .themeIssykBlue, action: { [self] in
                CopyHelper.copyAndNotify(value: viewModel.detailInfo.info.enode)
            }),
            tableView.multilineRow(id: "node_desc", title: "safe_zone.safe4.node.desc".localized, value: viewModel.detailInfo.desc),
            StaticRow(cell: incentiveCell, id: "slider-info", height: SuperNodeDetailIncentiveCell.height())
        ]
    }
}

extension SuperNodeDetailViewController: SectionsDataSource {

    func buildSections() -> [SectionProtocol] {
        
        var sections = [SectionProtocol]()
        
        let voteSection = Section(id: "SuperNode_vote", headerState: .static(view: voteHeaderView, height: SuperNodeDetailVoteHeaderView.height()),footerState: .margin(height: CGFloat.margin12), rows: voteType == .safe ? safeVoteRows : lockRecordVoteRows)
        
        let joinPartnerSection = Section(id: "SuperNode_join",footerState: .margin(height: CGFloat.margin12), rows: joinPartnerRows)

        if viewModel.detailInfo.isEnabledVote, viewType == .Vote {
            sections.append(voteSection)
        }else if viewModel.detailInfo.isEnabledJoin, viewType == .JoinPartner {
            sections.append(joinPartnerSection)
        }
        
        let infoSection = Section(id: "SuperNode_info", rows: nodeDetailInfoRows)
        
        let recordRows = viewItems.map{ row(viewItem: $0)}
        let voterRows = voterItems.map{ row(viewItem: $0)}
        let isPaginating = _tab == .voter
        let recordSection = Section(id: "SuperNode_record", paginating: isPaginating, headerState: .static(view: recordHeaderView, height: SuperNodeDetailRecordHeaderView.height()), rows: _tab == .voter ? voterRows : recordRows)
        sections.append(infoSection)
        sections.append(recordSection)
        return sections
    }
    
    func onBottomReached() {
        if case .voter = _tab {
            viewModel.loadMore()
        }
    }
}
