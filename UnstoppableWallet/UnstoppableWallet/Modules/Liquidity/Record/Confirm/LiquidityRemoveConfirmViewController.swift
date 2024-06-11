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
import BigInt

class LiquidityRemoveConfirmViewController: ThemeViewController {
    private let disposeBag = DisposeBag()
    private let viewModel: LiquidityRecordViewModel
    private let spinner = HUDActivityView.create(with: .medium24)
    private let recordItem: LiquidityRecordViewModel.RecordItem
    private let infoView = LiquidityRemoveConfirmView()
    
    init(viewModel: LiquidityRecordViewModel, recordItem: LiquidityRecordViewModel.RecordItem) {
        self.viewModel = viewModel
        self.recordItem = recordItem
        super.init()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        
        title = "liquidity.remove".localized
        navigationItem.backBarButtonItem = UIBarButtonItem(title: title, style: .plain, target: nil, action: nil)

        view.addSubview(infoView)
        infoView.snp.makeConstraints { maker in
            maker.top.equalTo(view.safeAreaLayoutGuide)
            maker.leading.trailing.bottom.equalToSuperview()
        }
                
        view.addSubview(spinner)
        spinner.snp.makeConstraints { maker in
            maker.center.equalToSuperview()
        }
        spinner.isHidden = true
        spinner.startAnimating()
        
        infoView.bind(viewItem: recordItem) { [weak self] recordItem, ratio in
            self?.removeConfirmation(viewItem: recordItem, ratio: ratio)
        }
        
        subscribe(disposeBag, viewModel.statusDriver) { [weak self] state in
            self?.syncState(state: state)
        }
    }
    
    private func syncState(state: LiquidityRecordService.State) {
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
    
    private func removeConfirmation(viewItem: LiquidityRecordViewModel.RecordItem, ratio: BigUInt) {
        let viewController = BottomSheetModule.removeLiquidityConfirmation { [weak self] in
            DispatchQueue.main.async { [weak self] in
                self?.spinner.isHidden = false
            }
            self?.viewModel.removeLiquidity(recordItem: viewItem, ratio: ratio)
            self?.dismiss(animated: true)
        }
        present(viewController, animated: true)
    }
    
    private func show(error: String) {
        HudHelper.instance.show(banner: .error(string: error))
    }
    
    private func show(message: String) {
        HudHelper.instance.show(banner: .success(string: message))
    }
}

