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

class ProposalDetailViewController: ThemeViewController {
    private let disposeBag = DisposeBag()
    private let viewModel: ProposalDetailViewModel
    private let tableView = SectionsTableView(style: .plain)
    private let spinner = HUDActivityView.create(with: .medium24)
    private var viewItems = [ProposalDetailViewModel.ViewItem]()
    private let refreshControl = UIRefreshControl()
    private let emptyView = PlaceholderView()
    private let headerView = ProposalDetailRecordHeaderView()
    private let voteCautionCell = Safe4WarningCell()
    weak var parentNavigationController: UINavigationController?
    private var isAbleVote: Bool = false
    init(viewModel: ProposalDetailViewModel) {
        self.viewModel = viewModel
        super.init()
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "safe_zone.safe4.detail".localized
        refreshControl.tintColor = .themeLeah
        refreshControl.alpha = 0.6
        refreshControl.addTarget(self, action: #selector(onRefresh), for: .valueChanged)
        
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
    
        view.addSubview(spinner)
        spinner.snp.makeConstraints { maker in
            maker.center.equalToSuperview()
        }
        spinner.startAnimating()
        viewModel.refresh()
        
        if viewModel.voteState == .voting {
            
            
        }
        subscribe(disposeBag, viewModel.isAbleVoteDriver) { [weak self] in self?.syncVote(isAble: $0) }
        subscribe(disposeBag, viewModel.stateDriver) { [weak self] in self?.sync(state: $0) }
    }
    
    private func syncVote(isAble: Bool) {
        DispatchQueue.main.async { [weak self] in
            self?.isAbleVote = isAble
            if isAble {
                self?.voteCautionCell.bind(text: "当前账户是排名前49且在线的超级节点，可以对提案进行投票!", type: .normal)
            }else {
                self?.voteCautionCell.bind(text: "当前账户不是排名前49且在线的超级节点，不能对提案进行投票!", type: .warning)
            }
            self?.tableView.reload()
        }
    }
    
    private func sync(state: ProposalDetailViewModel.State) {
        DispatchQueue.main.async { [weak self] in
            switch state {
            case .loading:
                self?.spinner.isHidden = (self?.viewItems.count)! > 0 ? true : false
                self?.emptyView.isHidden = true
                
            case let .completed(datas):
                self?.spinner.isHidden = true
                self?.emptyView.isHidden = datas.count > 0 ? true : false
                self?.viewItems = datas
                self?.tableView.reload()
                
            case let .failed(error):
                self?.show(error: error)
                self?.spinner.isHidden = true
                guard let count = self?.viewItems.count, count > 0 else { return (self?.emptyView.isHidden = false)! }
            case .voteCompleted:
                self?.voteCompleted()
            }
        }
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        tableView.refreshControl = refreshControl
    }

    @objc private func onRefresh() {
        viewModel.refresh()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.refreshControl.endRefreshing()
        }
    }
    
    private func show(error: String) {
        HudHelper.instance.show(banner: .error(string: error))
    }
    
    private func voteCompleted() {
        HudHelper.instance.show(banner: .success(string: "已完成投票"))
        navigationController?.popViewController(animated: true)
    }
}

extension ProposalDetailViewController: SectionsDataSource {

    private func buildRecordCell(viewItem: ProposalDetailViewModel.ViewItem, backgroundStyle: BaseSelectableThemeCell.BackgroundStyle) -> BaseSelectableThemeCell {
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
                component.text = viewItem.info.voter.address
            },
            .image24 { (component: ImageComponent) -> () in
                guard let state = viewItem.voteState else { return }
                component.imageView.image = UIImage(named: state.image)?.withTintColor(state.color)
            },
            .text { (component: TextComponent) -> () in
                component.font = .subhead1
                component.setContentHuggingPriority(.defaultHigh, for: .horizontal)
                component.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
                guard let state = viewItem.voteState else { return }
                component.textColor =  state.color
                component.text = state.title
            }
        ]))
        return cell
    }
    
    private func row(viewItem: ProposalDetailViewModel.ViewItem) -> RowProtocol {
        StaticRow(
                cell: buildRecordCell(viewItem: viewItem, backgroundStyle: .externalBorderOnly),
                id: "basic_Rows",
                height: .heightCell56
        )
    }
    
    private func multilineRow(id: String, tableView: UITableView, title: String, value: String, isFirst: Bool = false, isLast: Bool = false) -> RowProtocol {
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
    
    private func detailCellRow(id: String, tableView: UITableView, title: String, value: String, isFirst: Bool = false, isLast: Bool = false) -> RowProtocol {
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
    func voteResaultCell(state: ProposalDetailViewModel.VoteState) -> BaseSelectableThemeCell {
        let cell = BaseSelectableThemeCell()
        cell.set(backgroundStyle: .lawrence)
        cell.selectionStyle = .none
        cell.backgroundColor = .clear
        let font: UIFont = .subhead1
        let insets = UIEdgeInsets(top: 4, left: 4, bottom: 4, right: 4)
        CellBuilderNew.buildStatic(cell: cell, rootElement: .hStack([
            .text { (component: TextComponent) -> () in
                component.font = font
                component.textColor = .themeGray
                component.setContentHuggingPriority(.required, for: .horizontal)
                component.text = "已投"
            },
            .margin8,
            .secondaryButton { (component: SecondaryButtonComponent) -> () in
                component.setContentHuggingPriority(.required, for: .horizontal)
                component.button.semanticContentAttribute = .forceLeftToRight
                component.button.titleLabel?.font = font
                component.button.setTitleColor(state.color, for: .normal)
                component.button.imageView?.contentMode = .scaleAspectFit
                component.button.contentEdgeInsets = insets
                component.button.setImage(UIImage(named: state.image)?.withTintColor(state.color), for: .normal)
                component.button.setTitle(state.title, for: .normal)
            },
            .text { (component: TextComponent) -> () in}
        ]), layoutMargins: UIEdgeInsets(top: .margin16, left: .margin16, bottom: .margin8, right: .margin16))
        return cell
    }
    
    func voteButtonsCell(viewModel: ProposalDetailViewModel, backgroundStyle: BaseSelectableThemeCell.BackgroundStyle) -> BaseSelectableThemeCell {
        let cell = BaseSelectableThemeCell()
        cell.set(backgroundStyle: backgroundStyle)
        cell.selectionStyle = .none
        cell.backgroundColor = .clear
        let font: UIFont = .subhead1
        let insets = UIEdgeInsets(top: 4, left: 4, bottom: 4, right: 4)
        CellBuilderNew.buildStatic(cell: cell, rootElement: .hStack([
            .secondaryButton { (component: SecondaryButtonComponent) -> () in
                let state = ProposalDetailViewModel.VoteState.passed
                component.setContentHuggingPriority(.required, for: .horizontal)
                component.button.semanticContentAttribute = .forceLeftToRight
                component.button.titleLabel?.font = font
                component.button.setTitleColor(.themeLeah, for: .normal)
                component.button.borderColor = .themeGray
                component.button.borderWidth = 1
                component.button.cornerRadius = .cornerRadius4
                component.button.imageView?.contentMode = .scaleAspectFit
                component.button.contentEdgeInsets = insets
                component.button.setImage(UIImage(named: state.image)?.withTintColor(state.color), for: .normal)
                component.button.setTitle(state.title, for: .normal)
                component.onTap = {
                    viewModel.vote(result: state)
                }
            },
            .secondaryButton { (component: SecondaryButtonComponent) -> () in
                let state = ProposalDetailViewModel.VoteState.refuse
                component.setContentHuggingPriority(.required, for: .horizontal)
                component.button.semanticContentAttribute = .forceLeftToRight
                component.button.titleLabel?.font = font
                component.button.setTitleColor(.themeLeah, for: .normal)
                component.button.borderColor = .themeGray
                component.button.borderWidth = 1
                component.button.cornerRadius = .cornerRadius4
                component.button.imageView?.contentMode = .scaleAspectFit
                component.button.contentEdgeInsets = insets
                component.button.setImage(UIImage(named: state.image)?.withTintColor(state.color), for: .normal)
                component.button.setTitle(state.title, for: .normal)
                component.onTap = {
                    viewModel.vote(result: state)
                }
            },
            .secondaryButton { (component: SecondaryButtonComponent) -> () in
                let state = ProposalDetailViewModel.VoteState.abstain
                component.setContentHuggingPriority(.required, for: .horizontal)
                component.button.semanticContentAttribute = .forceLeftToRight
                component.button.titleLabel?.font = font
                component.button.setTitleColor(.themeLeah, for: .normal)
                component.button.borderColor = .themeGray
                component.button.borderWidth = 1
                component.button.cornerRadius = .cornerRadius4
                component.button.imageView?.contentMode = .scaleAspectFit
                component.button.contentEdgeInsets = insets
                component.button.setImage(UIImage(named: state.image)?.withTintColor(state.color), for: .normal)
                component.button.setTitle(state.title, for: .normal)
                component.onTap = {
                    viewModel.vote(result: state)
                }
            },
            .text { (component: TextComponent) -> () in}
        ]), layoutMargins: UIEdgeInsets(top: .margin16, left: .margin16, bottom: .margin8, right: .margin16))
        return cell
    }

    private var proposalDetailInfoRows: [RowProtocol] {
        [
            detailCellRow(id: "proposal_id", tableView: tableView, title: "提案ID: ".localized, value: viewModel.detailInfo.id, isFirst: true),
            multilineRow(id: "proposal_title", tableView: tableView, title: "提案标题:".localized, value: viewModel.detailInfo.info.title),
            multilineRow(id: "proposal_creater", tableView: tableView, title: "创建人:".localized, value: viewModel.detailInfo.info.creator.address),
            detailCellRow(id: "proposal_amount", tableView: tableView, title: "申请SAFE数量:".localized, value: viewModel.detailInfo.amount + " SAFE"),
            multilineRow(id: "proposal_desc", tableView: tableView, title: "提案简介:".localized, value: viewModel.detailInfo.info.description),
            multilineRow(id: "proposal_time", tableView: tableView, title: "发放方式:".localized, value: viewModel.detailInfo.distribution),
            multilineRow(id: "proposal_state", tableView: tableView, title: "投票状态: \(viewModel.detailInfo.status.title)".localized, value: viewModel.voteStateDesc)
        ]
    }
    
    var voteWarningRow: RowProtocol {
        StaticRow(
                cell: voteCautionCell,
                id: "vote-warning",
                dynamicHeight: { [weak self] containerWidth in
                        self?.voteCautionCell.height(containerWidth: containerWidth) ?? 0
                }
        )
    }
    
    var voteRow: RowProtocol {
        StaticRow(
            cell: voteButtonsCell(viewModel: viewModel, backgroundStyle: .lawrence),
                id: "vote-btn",
                height: .heightCell56
        )
    }

    func buildSections() -> [SectionProtocol] {
        var infoRows = [RowProtocol]()
        infoRows.append(contentsOf: proposalDetailInfoRows)
        if viewModel.voteState == .voting {
            infoRows.append(voteWarningRow)
            if isAbleVote, viewModel.votedResult == nil {
                infoRows.append(voteRow)
            }
        }
        
        if let votedResult = viewModel.votedResult {
            let voteResaultRow = StaticRow(cell: voteResaultCell(state: votedResult), id: "vote-btn", height: .heightCell56)
            infoRows.append(voteResaultRow)
        }
        
        let recordRows = viewItems.map{ row(viewItem: $0)}
        return [Section(id: "proposal_info", rows: infoRows),
                Section(id: "proposal_record", paginating: true, headerState: .static(view: headerView, height: ProposalDetailRecordHeaderView.height()),rows: recordRows)]
    }
    
    func onBottomReached() {
        viewModel.loadMore()
    }
}
