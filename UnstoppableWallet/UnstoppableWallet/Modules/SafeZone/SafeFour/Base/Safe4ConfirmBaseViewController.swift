import Foundation
import UIKit
import SectionsTableView
import SnapKit
import ThemeKit
import UIExtensions
import RxSwift
import RxCocoa
import ComponentKit

class Safe4ConfirmBaseViewController: ThemeViewController, SectionsDataSource {
    let tableView = SectionsTableView(style: .grouped)
    let buttonCell = PrimaryButtonCell()
    var didTapSend: (() -> Void)?
    var sendLock: Bool = false
    
    override init() {
        super.init()
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.largeTitleDisplayMode = .never

        if (navigationController?.viewControllers.count ?? 0) == 1 {
            let iconImageView = UIImageView()
            navigationItem.leftBarButtonItem = UIBarButtonItem(customView: iconImageView)
        }
            
        view.addSubview(tableView)
        tableView.snp.makeConstraints { maker in
            maker.edges.equalToSuperview()
        }
        tableView.allowsSelection = false
        tableView.separatorStyle = .none
        tableView.backgroundColor = .clear
        tableView.sectionDataSource = self
        
        buttonCell.set(style: .yellow)
        buttonCell.title = "create_wallet.create".localized
        buttonCell.onTap = { [weak self] in
            self?.didTapProceed()
        }
    }
    
    @objc private func didTapCancel() {
        dismiss(animated: true)
    }
    
    @objc private func didTapProceed() {
        didTapSend?()
    }
    
    func buildSections() -> [SectionProtocol] {
        return [buttonSection]
    }
}

extension Safe4ConfirmBaseViewController {
    
    var buttonSection: SectionProtocol {
        Section(
            id: "button",
            footerState: .margin(height: .margin32),
            rows: [
                StaticRow(
                    cell: buttonCell,
                    id: "button",
                    height: PrimaryButtonCell.height
                ),
            ]
        )
    }
}

