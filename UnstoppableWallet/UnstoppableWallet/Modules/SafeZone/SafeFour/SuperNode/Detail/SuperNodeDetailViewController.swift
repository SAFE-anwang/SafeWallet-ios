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
    private var tab: SuperNodeDetailRecordHeaderView.Tab = .creator
    private var voteType: SuperNodeDetailVoteHeaderView.VoteType = .safe
    
    private let tipsCell = Safe4WarningCell()
    weak var parentNavigationController: UINavigationController?
    init(viewModel: SuperNodeDetailViewModel) {
        self.viewModel = viewModel
        super.init()
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "safe_zone.safe4.detail".localized
        
//        view.addEndEditingTapGesture()
        
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
            self?.tab = tab
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
                let minValue = Float(strongSelf.viewModel.detailInfo.foundersTotalAmount.cgFloatValue)
                strongSelf.joinPartnerCell.bind(minValue: 1000, step: 1000, minimumValue: 0, maximumValue: maximumValue, balance: $0)
                strongSelf.safeVoteCell.update(balance: $0)
            }
        }
        
        joinPartnerCell.joinPartner = { [weak self] in
                self?.viewModel.joinPartner(value: $0)
        }

        tipsCell.bind(text: "必须同时满足如下条件的锁仓记录才可以进行投票\n1. 未关联超级节点的锁仓记录\n2. 未投票的锁仓记录\n3. 锁仓数量大于 1 SAFE", type: .normal)
        safeVoteTipsCell.bind(text: "用于投票的SAFE将会在锁仓账户中创建一个新的锁仓记录", type: .normal)
        
        lockRecordCell.loadMore = { [weak self] in
            self?.viewModel.loadMoreLockRecord()
        }
        lockRecordCell.selectAll = { [weak self]  in
            self?.viewModel.selectAllLockRecord($0)
        }

        lockRecordCell.lockRecordVote = { [weak self] in
            self?.viewModel.lockRecordVote()
        }
        
        safeVoteCell.safeVote = { [weak self]  in
            self?.viewModel.safeVote(amount: $0)
            self?.tableView.reload()
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
                
            case .voteCompleted:
                self?.show(message: "投票成功")
                self?.navigationController?.popViewController(animated: true)
                
            case .partnerCompleted:
                self?.show(message: "加入合伙人成功！")
                self?.navigationController?.popViewController(animated: true)
                
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
                component.textColor = .themeGray
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
                component.textColor = .themeGray
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
    
    func baseInfoCellRow(id: String, tableView: UITableView, title: String, value: String, isFirst: Bool = false, isLast: Bool = false) -> RowProtocol {
        let backgroundStyle: BaseThemeCell.BackgroundStyle = .lawrence
        let titleFont: UIFont = .subhead2
        let valueFont: UIFont = .subhead1

        return CellBuilderNew.row(
            rootElement:  .hStack([
                .text { (component: TextComponent) -> () in
                    component.font = titleFont
                    component.textColor = .themeGray
                    component.setContentHuggingPriority(.required, for: .horizontal)
                    component.text = title
                },
                .text { (component: TextComponent) -> () in
                    component.font = valueFont
                    component.setContentHuggingPriority(.defaultLow, for: .horizontal)
                    component.text = value
                }
            ]),
            tableView: tableView,
            id: id,
            hash: value,
            height: .heightCell48,
            bind: { cell in
                cell.set(backgroundStyle: backgroundStyle, isFirst: isFirst, isLast: isLast)
            }
        )
    }
    
    func multilineInfoRow(id: String, tableView: UITableView, title: String, value: String, isFirst: Bool = false, isLast: Bool = false) -> RowProtocol {
        let backgroundStyle: BaseThemeCell.BackgroundStyle = .lawrence
        let layoutMargins = UIEdgeInsets(top: .margin8, left: .margin16, bottom: .margin12, right: .margin16)
        let titleFont: UIFont = .subhead2
        let valueFont: UIFont = .subhead1
        return CellBuilderNew.row(
            rootElement: .vStack([
                .text { (component: TextComponent) -> () in
                    component.font = titleFont
                    component.textColor = .themeGray
                    component.text = title
                },
                .margin4,
                .text { (component: TextComponent) -> () in
                    component.font = valueFont
                    component.numberOfLines = 0
                    component.text = value
                }
            ]),
            layoutMargins: layoutMargins,
            tableView: tableView,
            id: id,
            hash: value,
            dynamicHeight: { containerWidth in
                return CellBuilderNew.height(
                    containerWidth: containerWidth,
                    backgroundStyle: backgroundStyle,
                    text: value,
                    font: valueFont,
                    elements: [
                        .margin16,
                        .margin16,
                        .multiline,
                    ]
                ) + 30
            },
            bind: { cell in
                cell.set(backgroundStyle: backgroundStyle, isFirst: isFirst, isLast: isLast)
            }
        )
    }
    
    func sectionHeaderCellRow(id: String, tableView: UITableView, title: String, isFirst: Bool = false, isLast: Bool = false) -> RowProtocol {
        let backgroundStyle: BaseThemeCell.BackgroundStyle = .lawrence
        let titleFont: UIFont = .headline2

        return CellBuilderNew.row(
            rootElement:  .hStack([
                .text { (component: TextComponent) -> () in
                    component.font = titleFont
                    component.textColor = .themeBlack
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
            sectionHeaderCellRow(id: "header", tableView: tableView, title: "通过锁仓SAFE来成为这个超级节点的合伙人", isFirst: true),
            multilineInfoRow(id: "node_balance", tableView: tableView, title: "超级节点剩余份额".localized, value: viewModel.detailInfo.foundersBalanceAmount.safe4FormattedAmount + " SAFE"),
            StaticRow(
                    cell: joinPartnerCell,
                    id: "node_join",
                    height: joinPartnerCell.height()
            ),
            
        ]
    }
    
    var safeVoteRows: [RowProtocol] {
        [
            sectionHeaderCellRow(id: "header", tableView: tableView, title: "使用账户中的SAFE余额进行投票", isFirst: true),
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
            sectionHeaderCellRow(id: "header", tableView: tableView, title: "选择锁仓记录对超级节点进行投票", isFirst: true),
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
            sectionHeaderCellRow(id: "header", tableView: tableView, title: "节点详情", isFirst: true),
            baseInfoCellRow(id: "node_id", tableView: tableView, title: "节点ID: ".localized, value: viewModel.detailInfo.id),
            baseInfoCellRow(id: "node_state", tableView: tableView, title: "节点状态:".localized, value: viewModel.detailInfo.nodeState.title),
            multilineInfoRow(id: "node_address", tableView: tableView, title: "节点地址:".localized, value: viewModel.detailInfo.info.addr.address),
            multilineInfoRow(id: "node_creater", tableView: tableView, title: "节点名称:".localized, value: viewModel.detailInfo.info.name),
            multilineInfoRow(id: "node_creater", tableView: tableView, title: "创建者:".localized, value: viewModel.detailInfo.info.creator.address),
            baseInfoCellRow(id: "node_amount", tableView: tableView, title: "创建质押:".localized, value: viewModel.detailInfo.pledgeNum.description + " SAFE"),
            baseInfoCellRow(id: "node_vote", tableView: tableView, title: "投票质押:".localized, value: viewModel.detailInfo.totalAmount.safe4FomattedAmount + " SAFE"),
            multilineInfoRow(id: "node_enode", tableView: tableView, title: "节点ENODE:".localized, value: viewModel.detailInfo.info.enode),
            multilineInfoRow(id: "node_desc", tableView: tableView, title: "节点描述:".localized, value: viewModel.detailInfo.desc),
            StaticRow(cell: incentiveCell, id: "slider-info", height: SuperNodeDetailIncentiveCell.height())
        ]
    }
}

extension SuperNodeDetailViewController: SectionsDataSource {

    func buildSections() -> [SectionProtocol] {
        
        var sections = [SectionProtocol]()
        
        let voteSection = Section(id: "SuperNode_vote", headerState: .static(view: voteHeaderView, height: SuperNodeDetailVoteHeaderView.height()),footerState: .margin(height: CGFloat.margin12), rows: voteType == .safe ? safeVoteRows : lockRecordVoteRows)
        
        let joinPartnerSection = Section(id: "SuperNode_join",footerState: .margin(height: CGFloat.margin12), rows: joinPartnerRows)

        if viewModel.nodeType != .superNode, viewModel.detailInfo.joinEnabled == false {
            sections.append(voteSection)
        }else if viewModel.detailInfo.joinEnabled == true {
            sections.append(joinPartnerSection)
        }
        
        let infoSection = Section(id: "SuperNode_info", rows: nodeDetailInfoRows)
        
        let recordRows = viewItems.map{ row(viewItem: $0)}
        let voterRows = voterItems.map{ row(viewItem: $0)}
        let isPaginating = tab == .voter
        let recordSection = Section(id: "SuperNode_record", paginating: isPaginating, headerState: .static(view: recordHeaderView, height: SuperNodeDetailRecordHeaderView.height()), rows: tab == .voter ? voterRows : recordRows)
        sections.append(infoSection)
        sections.append(recordSection)
        return sections
    }
    
    func onBottomReached() {
        if case .voter = tab {
            viewModel.loadMore()
        }
    }
}
