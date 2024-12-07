import ComponentKit
import RxCocoa
import RxSwift
import SnapKit
import ThemeKit
import UIKit

class SuperNodeDetailRecordHeaderView: UITableViewHeaderFooterView {

    private let tabsView = FilterView(buttonStyle: .tab)
    private let idLabel = UILabel()
    private let addressLabel = UILabel()
    private let amountLabel = UILabel()
    
    var onSelect: ((SuperNodeDetailRecordHeaderView.Tab) -> Void)?
    
    init(hasTopSeparator: Bool = true) {

        super.init(reuseIdentifier: nil)

        backgroundView = UIView()
        backgroundView?.backgroundColor = .clear

        if hasTopSeparator {
            let separatorView = UIView()
            contentView.addSubview(separatorView)
            separatorView.snp.makeConstraints { maker in
                maker.leading.trailing.equalToSuperview()
                maker.top.equalToSuperview()
                maker.height.equalTo(CGFloat.heightOnePixel)
            }

            separatorView.backgroundColor = .themeSteel20
        }
        
        contentView.addSubview(tabsView)
        tabsView.snp.makeConstraints { maker in
            maker.top.equalToSuperview()
            maker.leading.trailing.equalToSuperview()
            maker.height.equalTo(FilterView.height)
        }
        
        idLabel.text = "safe_zone.safe4.vote.record.id".localized
        idLabel.numberOfLines = 0
        idLabel.font = .subhead2
        idLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        contentView.addSubview(idLabel)
        idLabel.snp.makeConstraints { make in
            make.bottom.equalToSuperview().inset(CGFloat.margin8)
            make.top.equalTo(tabsView.snp.bottom).offset(CGFloat.margin8)
            make.leading.equalToSuperview().offset(CGFloat.margin16)
            make.width.lessThanOrEqualTo(CGFloat.margin48)
        }
        
        addressLabel.text = "safe_zone.safe4.vote.record.address".localized
        addressLabel.font = .subhead2
        contentView.addSubview(addressLabel)
        addressLabel.snp.makeConstraints { make in
            make.bottom.equalToSuperview().inset(CGFloat.margin8)
            make.top.equalTo(tabsView.snp.bottom).offset(CGFloat.margin8)
            make.leading.equalTo(idLabel.snp.trailing).offset(CGFloat.margin6)
        }
        
        amountLabel.text = "safe_zone.safe4.vote.record.amount".localized
        amountLabel.font = .subhead2
        amountLabel.textAlignment = .right
        amountLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        contentView.addSubview(amountLabel)
        amountLabel.snp.makeConstraints { make in
            make.bottom.equalToSuperview().inset(CGFloat.margin8)
            make.top.equalTo(tabsView.snp.bottom).offset(CGFloat.margin8)
            make.leading.equalTo(addressLabel.snp.trailing).offset(CGFloat.margin2)
            make.trailing.equalToSuperview().inset(CGFloat.margin32)
        }
        
        tabsView.reload(filters: Tab.allCases.map {
            FilterView.ViewItem.item(title: $0.title)
        })

        tabsView.onSelect = { [weak self] index in
            self?.onSelectTab(index: index)
        }
    }
    
    private func onSelectTab(index: Int) {
        idLabel.text = index == 0 ? "safe_zone.safe4.vote.record.id".localized : nil
        onSelect?(Tab.allCases[index])
    }
    
    static func height() -> CGFloat {
        return FilterView.height + 33
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

extension SuperNodeDetailRecordHeaderView {
    enum Tab: Int, CaseIterable {
        case creator
        case voter
        
        var title: String {
            switch self {
            case .creator: return "safe_zone.safe4.creator&partner".localized
            case .voter: return "safe_zone.safe4.node.record.voters".localized
            }
        }
    }
}

