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

class MasterNodeDetailViewController: ThemeViewController {
    
    private let disposeBag = DisposeBag()
    private let viewModel: MasterNodeDetailViewModel
    private let viewType: MasterNodeDetailViewModel.ViewType
    private let tableView = SectionsTableView(style: .plain)
    
    private var viewItems = [MasterNodeDetailViewModel.ViewItem]()
    
    private let incentiveCell = MasterNodeDetailIncentiveCell()
    private let joinPartnerCell = Safe4NodeJoinPartnerViewCell()
    
    private let emptyView = PlaceholderView()
    private let headerView = NodeDetailVoteRecordHeaderView(hasTopSeparator: true)
    
    weak var parentNavigationController: UINavigationController?
    var needReload: (() -> Void)?
    
    init(viewModel: MasterNodeDetailViewModel, viewType: MasterNodeDetailViewModel.ViewType) {
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
        tableView.sectionDataSource = self
        tableView.buildSections()
        viewItems = viewModel.viewItems
        emptyView.isHidden = viewItems.count > 0 ? true : false

        incentiveCell.bind(creator: viewModel.detailInfo.info.incentivePlan.creator, partner: viewModel.detailInfo.info.incentivePlan.partner)
        tableView.reload()
                
        subscribe(disposeBag, viewModel.balanceDriver) { [weak self] in
            if let strongSelf = self {
                let maximumValue = Float(strongSelf.viewModel.detailInfo.foundersBalanceAmount.cgFloatValue)
                strongSelf.joinPartnerCell.bind(minValue: strongSelf.viewModel.minimumSafeValue, step: strongSelf.viewModel.minimumSafeValue, minimumValue: 0, maximumValue: maximumValue, balance: $0)
            }
        }
        
        joinPartnerCell.joinPartner = { [weak self] in
            self?.onTapJoinPartner(sendAmount: $0)
        }
    }
}
extension MasterNodeDetailViewController {
    
    private func onTapJoinPartner(sendAmount: Float) {
        let vc = MasterNodeDetailSendViewController(viewModel: viewModel, sendAmount: sendAmount)
        vc.partnerCompleted = { [weak self] in
            self?.tableView.reload()
            self?.navigationController?.popToViewController(ofClass: MasterNodeTabViewController.self)
        }
        navigationController?.pushViewController(vc, animated: true)
    }
}

private extension MasterNodeDetailViewController {
    
    func buildRecordCell(viewItem: MasterNodeDetailViewModel.ViewItem) -> BaseSelectableThemeCell {
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
    
    func balanceCell(lockNum: String, balance: String) -> BaseSelectableThemeCell {
        let cell = BaseSelectableThemeCell()
        cell.set(backgroundStyle: .transparent)
        cell.selectionStyle = .none
        cell.backgroundColor = .clear
        CellBuilderNew.buildStatic(cell: cell, rootElement: .vStack([
            .hStack([
                .text { (component: TextComponent) -> () in
                    component.font = .subhead1
                    component.textColor = .themeGray
                    component.setContentHuggingPriority(.required, for: .vertical)
                    component.text = "safe_zone.safe4.node.mater.balance".localized
                },
                .text { (component: TextComponent) -> () in
                    component.font = .subhead1
                    component.textColor = .themeGray
                    component.textAlignment = .right
                    component.setContentHuggingPriority(.required, for: .vertical)
                    component.text = "safe_zone.safe4..account.balance".localized
                },
            ]),
            .margin8,
            .hStack([
                .text { (component: TextComponent) -> () in
                    component.font = .subhead1
                    component.textColor = .themeBlack
                    component.setContentHuggingPriority(.required, for: .vertical)
                    component.text = "\(lockNum) SAFE"
                },
                .text { (component: TextComponent) -> () in
                    component.font = .subhead1
                    component.textColor = .themeGray
                    component.textAlignment = .right
                    component.setContentHuggingPriority(.required, for: .vertical)
                    component.text = balance
                },
            ])
        ]), layoutMargins: UIEdgeInsets(top: .margin6, left: .margin16, bottom: .margin6, right: .margin16))
        return cell
    }
    
    func baseInfoCellRow(id: String, title: String, value: String, isFirst: Bool = false, isLast: Bool = false) -> RowProtocol {
        tableView.universalRow48(id: id, title: .subhead2(title, color: .themeGray), value: .subhead1(value), isFirst: isFirst, isLast: isLast)
    }
        
    func payTypeCell(viewModel: ProposalCreateViewModel, backgroundStyle: BaseSelectableThemeCell.BackgroundStyle) -> BaseSelectableThemeCell {
        let cell = BaseSelectableThemeCell()
        cell.set(backgroundStyle: backgroundStyle)
        cell.selectionStyle = .none
        cell.backgroundColor = .clear
        CellBuilderNew.buildStatic(cell: cell, rootElement: .vStack([
            .text { (component: TextComponent) -> () in
                component.font = .subhead1
                component.textColor = .themeGray
                component.setContentHuggingPriority(.required, for: .vertical)
                component.text = "safe_zone.safe4.pay.method".localized
            },
        ]), layoutMargins: UIEdgeInsets(top: .margin16, left: .margin16, bottom: .margin8, right: .margin16))
        return cell
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
    
    func row(viewItem: MasterNodeDetailViewModel.ViewItem) -> RowProtocol {
        StaticRow(
                cell: buildRecordCell(viewItem: viewItem),
                id: "basic_Rows",
                height: .heightCell56
        )
    }
    
    var joinPartnerRows: [RowProtocol] {
        [
            sectionHeaderCellRow(id: "header", tableView: tableView, title: "safe_zone.safe4.node.master.lock.tips".localized, isFirst: true),
            tableView.multilineRow(id: "node_balance", title: "safe_zone.safe4.node.mater.balance".localized, value: viewModel.detailInfo.foundersBalanceAmount.safe4FormattedAmount + " SAFE"),
            StaticRow(
                    cell: joinPartnerCell,
                    id: "node_join",
                    height: joinPartnerCell.height()
            ),
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
            tableView.multilineRow(id: "node_creater", title: "safe_zone.safe4.node.creator".localized + ": ", value: viewModel.detailInfo.info.creator.address, subTextColor: .themeIssykBlue, action: { [self] in
                CopyHelper.copyAndNotify(value: viewModel.detailInfo.info.creator.address)
            }),
            baseInfoCellRow(id: "node_amount", title: "safe_zone.safe4.creator.pledge".localized, value: viewModel.detailInfo.amount + " SAFE"),
            tableView.multilineRow(id: "node_enode", title: "safe_zone.safe4.node.enode".localized, value: viewModel.detailInfo.info.enode, subTextColor: .themeIssykBlue, action: { [self] in
                CopyHelper.copyAndNotify(value: viewModel.detailInfo.info.enode)
            }),
            tableView.multilineRow(id: "node_desc", title: "safe_zone.safe4.node.desc".localized, value: viewModel.detailInfo.info.description),
            StaticRow(cell: incentiveCell, id: "slider-info", height: MasterNodeDetailIncentiveCell.height())
        ]
    }
}

extension MasterNodeDetailViewController: SectionsDataSource {
    func buildSections() -> [SectionProtocol] {

        var sections = [SectionProtocol]()
        let joinPartnerSection = Section(id: "Node_join",footerState: .margin(height: CGFloat.margin12), rows: joinPartnerRows)
        if viewType == .JoinPartner, viewModel.detailInfo.isEnabledJoin == true {
           sections.append(joinPartnerSection)
       }
        
        let recordRows = viewItems.map{ row(viewItem: $0)}
        let infoSection = Section(id: "masterNode_info", rows: nodeDetailInfoRows)
        let recordSection = Section(id: "masterNode_record", headerState: .static(view: headerView, height: NodeDetailVoteRecordHeaderView.height()), rows: recordRows)
        sections.append(infoSection)
        sections.append(recordSection)
        return sections
    }
}
