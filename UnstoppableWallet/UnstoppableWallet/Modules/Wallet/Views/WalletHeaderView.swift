import ComponentKit
import SnapKit
import ThemeKit
import UIKit

class WalletHeaderView: UITableViewHeaderFooterView {
    static var height: CGFloat = TextDropDownAndSettingsView.height
    private let sortAddCoinView = TextDropDownAndSettingsView()
    private let watchAccountImage = ImageComponent(size: .iconSize24)

    var onTapSortBy: (() -> Void)?
    var onTapAddCoin: (() -> Void)?
    var onTapTransactions: (() -> Void)?
    var onTapLiquidityRecord: (() -> Void)?
    
    override init(reuseIdentifier: String?) {
        super.init(reuseIdentifier: reuseIdentifier)

        backgroundView = UIView()
        backgroundView?.backgroundColor = .themeNavigationBarBackground

        contentView.addSubview(sortAddCoinView)
        sortAddCoinView.snp.makeConstraints { maker in
            maker.leading.top.trailing.equalToSuperview()
            maker.height.equalTo(TextDropDownAndSettingsView.height)
        }

        sortAddCoinView.onTapDropDown = { [weak self] in self?.onTapSortBy?() }
        sortAddCoinView.onTapSettings = { [weak self] in self?.onTapAddCoin?() }
        sortAddCoinView.onTapTransactions = { [weak self] in self?.onTapTransactions?() }
        sortAddCoinView.onTapLiquidityRecord = { [weak self] in self?.onTapLiquidityRecord?() }
        
        contentView.addSubview(watchAccountImage)
        watchAccountImage.snp.makeConstraints { maker in
            maker.trailing.equalToSuperview().inset(CGFloat.margin16)
            maker.centerY.equalTo(sortAddCoinView)
        }

        watchAccountImage.imageView.image = UIImage(named: "binocule_24")?.withTintColor(.themeGray)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func set(sortByTitle: String?) {
        sortAddCoinView.set(dropdownTitle: sortByTitle)
    }

    func set(controlViewItem: WalletViewModel.ControlViewItem) {
        sortAddCoinView.set(settingsHidden: !controlViewItem.coinManagerVisible)
        watchAccountImage.isHidden = !controlViewItem.watchVisible
    }

}
