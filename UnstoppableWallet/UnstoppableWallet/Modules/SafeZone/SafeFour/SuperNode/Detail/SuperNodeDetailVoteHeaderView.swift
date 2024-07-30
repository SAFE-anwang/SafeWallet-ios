import ComponentKit
import RxCocoa
import RxSwift
import SnapKit
import ThemeKit
import UIKit

class SuperNodeDetailVoteHeaderView: UITableViewHeaderFooterView {

    private let tabsView = FilterView(buttonStyle: .tab)

    var onSelect: ((SuperNodeDetailVoteHeaderView.VoteType) -> Void)?
    
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

        tabsView.reload(filters: VoteType.allCases.map {
            FilterView.ViewItem.item(title: $0.title)
        })

        tabsView.onSelect = { [weak self] index in
            self?.onSelectTab(index: index)
        }
    }
    
    private func onSelectTab(index: Int) {
        onSelect?(VoteType.allCases[index])
    }
    
    static func height() -> CGFloat {
        return FilterView.height
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

extension SuperNodeDetailVoteHeaderView {

    enum VoteType: Int, CaseIterable {
        case safe
        case lockRecord
        
        var title: String {
            switch self {
            case .safe: return "SAFE投票".localized
            case .lockRecord: return "锁仓记录投票".localized
            }
        }
    }
}
