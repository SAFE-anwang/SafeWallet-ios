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
    private let tableView = SectionsTableView(style: .plain)
    
    private var viewItems = [MasterNodeDetailViewModel.ViewItem]()
    
    private let incentiveCell = MasterNodeDetailIncentiveCell()
    private let joinPartnerCell = Safe4NodeJoinPartnerViewCell()
    
    private let emptyView = PlaceholderView()
    private let headerView = NodeDetailVoteRecordHeaderView(hasTopSeparator: true)
    
    weak var parentNavigationController: UINavigationController?
    init(viewModel: MasterNodeDetailViewModel) {
        self.viewModel = viewModel
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
        
        subscribe(disposeBag, viewModel.stateDriver) { [weak self] in self?.sync(state: $0) }
        
        subscribe(disposeBag, viewModel.balanceDriver) { [weak self] in
            if let strongSelf = self {
                let maximumValue = Float(strongSelf.viewModel.detailInfo.foundersBalanceAmount.cgFloatValue)
                strongSelf.joinPartnerCell.bind(minValue: 200, step: 200, minimumValue: 0, maximumValue: maximumValue, balance: $0)
            }
        }
        
        joinPartnerCell.joinPartner = { [weak self] in
                self?.viewModel.joinPartner(value: $0)
        }
    }
    
    private func sync(state: MasterNodeDetailViewModel.State) {
        DispatchQueue.main.async { [weak self] in
            switch state {
            case .loading:()
            case let .failed(error):
                self?.show(error: error)
                
            case .partnerCompleted:
                self?.show(message: "加入合伙人成功！")
                self?.navigationController?.popViewController(animated: true)
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
                    component.text = "主节点剩余份额"
                },
                .text { (component: TextComponent) -> () in
                    component.font = .subhead1
                    component.textColor = .themeGray
                    component.textAlignment = .right
                    component.setContentHuggingPriority(.required, for: .vertical)
                    component.text = "账户余额"
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
                ) + 27
            },
            bind: { cell in
                cell.set(backgroundStyle: backgroundStyle, isFirst: isFirst, isLast: isLast)
            }
        )
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
                component.text = "发放方式"
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
    
    func row(viewItem: MasterNodeDetailViewModel.ViewItem) -> RowProtocol {
        StaticRow(
                cell: buildRecordCell(viewItem: viewItem),
                id: "basic_Rows",
                height: .heightCell56
        )
    }
    
    var joinPartnerRows: [RowProtocol] {
        [
            sectionHeaderCellRow(id: "header", tableView: tableView, title: "通过锁仓SAFE来成为这个主节点的合伙人", isFirst: true),
            multilineInfoRow(id: "node_balance", tableView: tableView, title: "主节点剩余份额".localized, value: viewModel.detailInfo.foundersBalanceAmount.safe4FormattedAmount + " SAFE"),
            StaticRow(
                    cell: joinPartnerCell,
                    id: "node_join",
                    height: joinPartnerCell.height()
            ),
            
        ]
    }

    var nodeDetailInfoRows: [RowProtocol] {
        [
            sectionHeaderCellRow(id: "header", tableView: tableView, title: "节点详情", isFirst: true),
            baseInfoCellRow(id: "node_id", tableView: tableView, title: "节点ID: ".localized, value: viewModel.detailInfo.id),
            baseInfoCellRow(id: "node_state", tableView: tableView, title: "节点状态:".localized, value: viewModel.detailInfo.nodeState.title),
            multilineInfoRow(id: "node_address", tableView: tableView, title: "节点地址:".localized, value: viewModel.detailInfo.info.addr.address),
            multilineInfoRow(id: "node_creater", tableView: tableView, title: "创建者:".localized, value: viewModel.detailInfo.info.creator.address),
            baseInfoCellRow(id: "node_amount", tableView: tableView, title: "创建质押:".localized, value: viewModel.detailInfo.amount + " SAFE"),
            multilineInfoRow(id: "node_enode", tableView: tableView, title: "节点ENODE:".localized, value: viewModel.detailInfo.info.enode),
            multilineInfoRow(id: "node_desc", tableView: tableView, title: "节点描述:".localized, value: viewModel.detailInfo.info.description),
            StaticRow(cell: incentiveCell, id: "slider-info", height: MasterNodeDetailIncentiveCell.height())
        ]
    }
}

extension MasterNodeDetailViewController: SectionsDataSource {
    func buildSections() -> [SectionProtocol] {

        var sections = [SectionProtocol]()
        let joinPartnerSection = Section(id: "Node_join",footerState: .margin(height: CGFloat.margin12), rows: joinPartnerRows)

        if viewModel.detailInfo.joinEnabled == true {
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
