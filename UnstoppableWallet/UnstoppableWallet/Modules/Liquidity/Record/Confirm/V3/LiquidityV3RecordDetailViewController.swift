import Foundation
import UIKit
import SectionsTableView
import SnapKit
import ThemeKit
import UIExtensions
import RxSwift
import RxCocoa
import ComponentKit
import BigInt
import HUD

class LiquidityV3RecordDetailViewController: ThemeViewController {
    
    private let disposeBag = DisposeBag()
    private let viewModel: LiquidityV3RecordViewModel
    private let spinner = HUDActivityView.create(with: .medium24)
    private let detailHeaderView = LiquidityV3RecordDetailHeaderView()
    private let viewItem: LiquidityV3RecordViewModel.V3RecordItem
    private let tableView = SectionsTableView(style: .grouped)
    private let removeButton = PrimaryButton()
    private var ratio: Float = 0
    
    init(viewModel: LiquidityV3RecordViewModel, viewItem: LiquidityV3RecordViewModel.V3RecordItem) {
        self.viewModel = viewModel
        self.viewItem = viewItem
        super.init()
        hidesBottomBarWhenPushed = true
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
  
        detailHeaderView.bind(viewItem: viewItem)
        detailHeaderView.ratioOfRemove = { [weak self] ratio in
            self?.syncRatio(ratio: ratio)
        }
        
        tableView.sectionDataSource = self
        tableView.separatorStyle = .none
        tableView.backgroundColor = .clear
        tableView.registerHeaderFooter(forClass: LiquidityV3RecordDetailHeaderView.self)
        tableView.registerCell(forClass: LiquidityV3RecordDetailCell.self)
        view.addSubview(tableView)
        tableView.snp.makeConstraints { maker in
            maker.edges.equalToSuperview()
        }
        tableView.buildSections()
        
        view.addSubview(spinner)
        spinner.snp.makeConstraints { maker in
            maker.center.equalToSuperview()
        }
        spinner.isHidden = true
        spinner.startAnimating()
        
        removeButton.set(style: .yellow)
        removeButton.isEnabled = ratio > 0
        removeButton.setTitle("liquidity.remove".localized, for: .normal)
        removeButton.addTarget(self, action: #selector(tapRemove), for: .touchUpInside)
        view.addSubview(removeButton)
        removeButton.snp.makeConstraints { maker in
            maker.leading.trailing.equalToSuperview().inset(CGFloat.margin16)
            maker.bottom.equalToSuperview().inset(CGFloat.margin32)
            maker.height.equalTo(44)
        }
        
        subscribe(disposeBag, viewModel.statusDriver) { [weak self] state in
            self?.syncState(state: state)
        }
    }
    
    private func syncRatio(ratio: Float) {
        self.ratio = ratio
        removeButton.isEnabled = ratio > 0
        tableView.reload()
    }
    
    private func syncState(state: LiquidityV3RecordService.State) {
        DispatchQueue.main.async { [weak self] in
            self?.spinner.isHidden = true
            switch state {
            case let .failed(error):
                self?.show(error: error)
            case let .removeFailed(error):
                self?.show(error: error)
            case .removeSuccess:
                self?.show(message: "liquidity.remove.succ".localized)
                self?.navigationController?.popToRootViewController(animated: true)
            default: ()
            }
        }
    }
    
    @objc func tapRemove() {
        removeConfirmation()
    }

}

private extension LiquidityV3RecordDetailViewController {
    func buildCell(imageUrl: String, title: String, amount: String, backgroundStyle: BaseSelectableThemeCell.BackgroundStyle, isFirst: Bool = false, isLast: Bool = false) -> BaseSelectableThemeCell {
        let cell = BaseSelectableThemeCell()
        cell.set(backgroundStyle: backgroundStyle, isFirst: isFirst, isLast: isLast)
        CellBuilderNew.buildStatic(cell: cell, rootElement: .hStack([
            .image24 { (component: ImageComponent) -> () in
                component.imageView.setImage(withUrlString: imageUrl, placeholder: nil)
            },
            .text { (component: TextComponent) -> () in
                component.font = .body
                component.textColor = .themeLeah
                component.text = title
            },
            .text { (component: TextComponent) -> () in
                component.font = .caption
                component.textColor = .themeLeah
                component.textAlignment = .right
                component.text = amount
            },

        ]))
        return cell
    }
    
    func show(error: String) {
        HudHelper.instance.show(banner: .error(string: error))
    }
    
    func show(message: String) {
        HudHelper.instance.show(banner: .success(string: message))
    }
    
    func removeConfirmation() {
        
        let viewController = BottomSheetModule.removeLiquidityConfirmation { [weak self] in
            if  let strongSelf = self {
                DispatchQueue.main.async { [weak self] in
                    self?.spinner.isHidden = false
                }
                let ratio = BigUInt(Int(strongSelf.ratio * 100))
                strongSelf.viewModel.removeLiquidity(recordItem: strongSelf.viewItem, ratio: ratio)
            }
            self?.dismiss(animated: true)
        }
        present(viewController, animated: true)
    }
}

extension LiquidityV3RecordDetailViewController: SectionsDataSource {
    
    private var rows: [RowProtocol] {
        [
            StaticRow(
                cell: buildCell(imageUrl: viewItem.token0.coin.imageUrl,
                                title: "liquidity.remove.pooled".localized + viewItem.token0.coin.code,
                                amount: viewItem.token0Amount(ratio: ratio),
                                backgroundStyle: .lawrence,
                                isFirst: true
                               ),
                id: "row_0",
                height: .heightCell56
            ),
            
            StaticRow(
                cell: buildCell(imageUrl: viewItem.token1.coin.imageUrl,
                                title: "liquidity.remove.pooled".localized + viewItem.token1.coin.code,
                                amount: viewItem.token1Amount(ratio: ratio),
                                backgroundStyle: .lawrence,
                                isLast: true
                               ),
                id: "row_1",
                height: .heightCell56
            )
        ]
    }

    func buildSections() -> [SectionProtocol] {
        
        return [
            Section(
                id: "sec0",
                headerState: .static(view: detailHeaderView, height: LiquidityV3RecordDetailHeaderView.height),
                rows: []
            ),
            Section(
                id: "sec1",
                headerState: .text(text: "liquidity.remove.receive.title".localized, topMargin: 25, bottomMargin: 15),
                rows: rows
            )
        ]
    }
}
