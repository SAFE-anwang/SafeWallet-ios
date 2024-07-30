import ComponentKit
import RxCocoa
import RxSwift
import SnapKit
import ThemeKit
import UIKit
import UIExtensions

class SuperNodeVoteLockRecordCell: BaseThemeCell {
    private let disposeBag = DisposeBag()
    private let selectAllButton = UIButton(type: .custom)
    private let voteButton = UIButton(type: .custom)
    private let sideMargin: CGFloat = .margin16
    private static let gridRowHeight: CGFloat = .heightSingleLineCell
    
    private let collectionView: UICollectionView
    private var viewItems = [SuperNodeDetailViewModel.LockRecoardItem]()
    
    var loadMore: (() -> Void)?
    var selectAll: ((Bool) -> Void)?
    var lockRecordVote: (() -> Void)?
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.sectionInset = .zero
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        
        set(backgroundStyle: .lawrence, isFirst: false, isLast: true)
        
        addSelectAllButton()
        wrapperView.addSubview(selectAllButton)
        selectAllButton.snp.makeConstraints { make in
            make.top.equalToSuperview()
            make.height.equalTo(CGFloat.heightCell48)
            make.leading.equalToSuperview().offset(CGFloat.margin24)
        }
        
        wrapperView.addSubview(collectionView)
        collectionView.snp.makeConstraints { make in
            make.top.equalTo(selectAllButton.snp.bottom)
            make.leading.trailing.equalToSuperview()
        }
        
        collectionView.delegate = self
        collectionView.dataSource = self
        collectionView.backgroundColor = .clear
        collectionView.scrollsToTop = false
//        collectionView.showsHorizontalScrollIndicator = false
        collectionView.registerCell(forClass: LockRecordCell.self)
        
        addVoteButton()
        wrapperView.addSubview(voteButton)
        voteButton.snp.makeConstraints { make in
            make.top.equalTo(collectionView.snp.bottom)
            make.bottom.equalToSuperview().inset(CGFloat.margin12)
            make.height.equalTo(32)
            make.leading.equalToSuperview().offset(CGFloat.margin16)
        }
    }
    
    @available(*, unavailable)
    public required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func addSelectAllButton() {
        selectAllButton.setTitle("选择全部可用锁仓记录", for: .normal)
        selectAllButton.setImage(UIImage(named: "safe4_unsel_20"), for: .normal)
        selectAllButton.setImage(UIImage(named: "safe4_sel_20")?.withTintColor(.themeIssykBlue), for: .selected)
        selectAllButton.imageEdgeInsets = UIEdgeInsets(top: 0, left: -5, bottom: 0, right: 5)
        selectAllButton.titleEdgeInsets = UIEdgeInsets(top: 0, left: 5, bottom: 0, right: -5)
        selectAllButton.titleLabel?.font = .headline2
        selectAllButton.setTitleColor(.black, for: .normal)
        selectAllButton.addTarget(self, action: #selector(selAll(_:)), for: .touchUpInside)
    }
    
    private func addVoteButton() {
        voteButton.cornerRadius = 6
        voteButton.setTitle("投票", for: .normal)
        voteButton.titleLabel?.font = .headline2
        voteButton.setTitleColor(.white, for: .normal)
        voteButton.setTitleColor(.gray, for: .disabled)
        voteButton.contentEdgeInsets = UIEdgeInsets(top: 5, left: 20, bottom: 5, right: 20)
        voteButton.setBackgroundColor(.themeIssykBlue, for: .normal)
        voteButton.setBackgroundColor(.lightGray.withAlphaComponent(0.5) , for: .disabled)
        voteButton.addTarget(self, action: #selector(vote), for: .touchUpInside)
    }
    
    @objc private func selAll(_ sender: UIButton) {
        sender.isSelected = !sender.isSelected
        selectAll?(sender.isSelected)
    }
    
    @objc private func vote() {
        lockRecordVote?()
    }
    
    func height() -> CGFloat {
        250
    }
    
    func bind(viewItems: [SuperNodeDetailViewModel.LockRecoardItem]) {
        self.viewItems = viewItems
        voteButton.isEnabled = viewItems.filter{$0.isSlected}.count > 0
        collectionView.reloadData()
    }
}
extension SuperNodeVoteLockRecordCell: UICollectionViewDelegateFlowLayout, UICollectionViewDataSource, UICollectionViewDelegate {

    func collectionView(_: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        viewItems.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        return collectionView.dequeueReusableCell(withReuseIdentifier: String(describing: LockRecordCell.self), for: indexPath)
    }

    func collectionView(_: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        if let cell = cell as? LockRecordCell {
            cell.bind(item: viewItems[indexPath.item])
        }
    }

    func collectionView(_ collectionView: UICollectionView, layout _: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        let minWidth = collectionView.frame.size.width / 2 - 20
        return CGSize(width: minWidth, height: Self.gridRowHeight)
    }

    func collectionView(_: UICollectionView, layout _: UICollectionViewLayout, minimumInteritemSpacingForSectionAt _: Int) -> CGFloat {
        5
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, minimumLineSpacingForSectionAt section: Int) -> CGFloat {
        5
    }
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let item = viewItems[indexPath.item]
        guard item.isEnabled else { return }
        item.update(isSelected: !item.isSlected)
        voteButton.isEnabled = viewItems.filter{$0.isSlected}.count > 0
        collectionView.reloadData()
    }
    

}
extension SuperNodeVoteLockRecordCell: UIScrollViewDelegate {
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let offsetX = scrollView.contentOffset.x
        let contentWidth = scrollView.contentSize.width
        let width = scrollView.frame.size.width
        
        if offsetX > contentWidth - width - 100 {
            loadMore?()
        }
    }
}
extension SuperNodeVoteLockRecordCell {
    static func height(viewItems: [[CoinOverviewViewModel.PerformanceViewItem]]) -> CGFloat {
        CGFloat(viewItems.count) * gridRowHeight
    }
}


class LockRecordCell: UICollectionViewCell {

    private let contentBUtton = UIButton(type: .custom)
    private let topSeparator = UIView()
    private let leftSeparator = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)

        contentView.backgroundColor = .clear
        backgroundColor = .clear
        
        contentBUtton.isUserInteractionEnabled = false
        contentBUtton.setImage(UIImage(named: "safe4_unsel_20"), for: .normal)
        contentBUtton.setImage(UIImage(named: "safe4_sel_20")?.withTintColor(.themeIssykBlue), for: .selected)
        contentBUtton.setImage(UIImage(named: "safe4_disable_20"), for: .disabled)
        contentBUtton.imageEdgeInsets = UIEdgeInsets(top: 0, left: -5, bottom: 0, right: 5)
        contentBUtton.titleEdgeInsets = UIEdgeInsets(top: 0, left: 5, bottom: 0, right: -5)
        contentBUtton.titleLabel?.font = .subhead2
        contentBUtton.titleLabel?.numberOfLines = 0
        contentBUtton.setTitleColor(.black, for: .normal)
        contentBUtton.setTitleColor(.black, for: .selected)
        contentBUtton.setTitleColor(.lightGray, for: .disabled)
        contentView.addSubview(contentBUtton)
        contentBUtton.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        contentView.addSubview(topSeparator)
        topSeparator.snp.makeConstraints { maker in
            maker.leading.top.trailing.equalToSuperview()
            maker.height.equalTo(1)
        }

        topSeparator.backgroundColor = .themeSteel10

        contentView.addSubview(leftSeparator)
        leftSeparator.snp.makeConstraints { maker in
            maker.leading.top.bottom.equalToSuperview()
            maker.width.equalTo(1)
        }

        leftSeparator.backgroundColor = .themeSteel10
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func bind(item: SuperNodeDetailViewModel.LockRecoardItem) {
        contentBUtton.isEnabled = item.isEnabled
        contentBUtton.isSelected = item.isSlected
        let title = "锁仓记录ID:\(item.info.id)\n\(item.info.amount.safe4FomattedAmount) SAFE"
        contentBUtton.setTitle(title, for: .normal)
    }
}
