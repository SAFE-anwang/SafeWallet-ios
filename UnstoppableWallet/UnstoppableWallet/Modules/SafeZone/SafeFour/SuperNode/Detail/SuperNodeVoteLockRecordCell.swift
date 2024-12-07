import ComponentKit
import RxCocoa
import RxSwift
import SnapKit
import ThemeKit
import UIKit
import UIExtensions
import HUD

class SuperNodeVoteLockRecordCell: BaseThemeCell {
    private let disposeBag = DisposeBag()
    private let selectAllButton = UIButton(type: .custom)
    private let voteButton = UIButton(type: .custom)
    private let sideMargin: CGFloat = .margin16
    private static let gridRowHeight: CGFloat = .heightSingleLineCell
    private let emptyView = PlaceholderView()
    private let spinner = HUDActivityView.create(with: .medium24)
    private let itemsPerRow: CGFloat = 2
    private let collectionView: UICollectionView
    private var viewItems = [SuperNodeDetailViewModel.LockRecoardItem]()
    
    var loadMore: (() -> Void)?
    var selectAll: ((Bool) -> Void)?
    var lockRecordVote: (() -> Void)?
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .vertical
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
        collectionView.registerCell(forClass: LockRecordCell.self)
        
        wrapperView.addSubview(emptyView)
        emptyView.snp.makeConstraints { make in
            make.edges.equalTo(collectionView)
        }
        
        wrapperView.addSubview(spinner)
        spinner.snp.makeConstraints { maker in
            maker.center.equalTo(collectionView)//equalToSuperview()
        }
        spinner.startAnimating()

        emptyView.image = UIImage(named: "safe4_empty")
        emptyView.text = "safe_zone.safe4.empty.description".localized
        emptyView.isHidden = true
        
        addVoteButton()
        wrapperView.addSubview(voteButton)
        voteButton.snp.makeConstraints { make in
            make.top.equalTo(collectionView.snp.bottom)
            make.bottom.equalToSuperview().inset(CGFloat.margin12)
            make.height.equalTo(32)
            make.leading.equalToSuperview().offset(CGFloat.margin16)
        }
        
        loading(true)
    }
    
    @available(*, unavailable)
    public required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func addSelectAllButton() {
        selectAllButton.setTitle("safe_zone.safe4.node.super.vote.locked.recoard.choose.all".localized, for: .normal)
        selectAllButton.setImage(UIImage(named: "safe4_unsel_20"), for: .normal)
        selectAllButton.setImage(UIImage(named: "safe4_sel_20")?.withTintColor(.themeIssykBlue), for: .selected)
        selectAllButton.imageEdgeInsets = UIEdgeInsets(top: 0, left: -5, bottom: 0, right: 5)
        selectAllButton.titleEdgeInsets = UIEdgeInsets(top: 0, left: 5, bottom: 0, right: -5)
        selectAllButton.titleLabel?.font = .headline2
        selectAllButton.setTitleColor(.themeBlackAndWhite, for: .normal)
        selectAllButton.addTarget(self, action: #selector(selAll(_:)), for: .touchUpInside)
    }
    
    private func addVoteButton() {
        voteButton.cornerRadius = 6
        voteButton.setTitle("safe_zone.safe4.proposal.vote.title".localized, for: .normal)
        voteButton.titleLabel?.font = .headline2
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
        guard viewItems.count > 0 else { return }
        lockRecordVote?()
    }
    
    func height() -> CGFloat {
        if viewItems.count == 0 {
            return 250
        }else {
            let numberOfRows = Int(ceil(Double(viewItems.count) / Double(2)))
            return CGFloat(numberOfRows) * SuperNodeVoteLockRecordCell.gridRowHeight + 92// - 20
        }
    }
    
    func loading(_ isLoading: Bool) {
        spinner.isHidden = !isLoading
    }
    
    func bind(viewItems: [SuperNodeDetailViewModel.LockRecoardItem]) {
        self.viewItems = viewItems
        spinner.isHidden = true
        emptyView.isHidden = viewItems.count > 0
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
        let minWidth = collectionView.frame.size.width / itemsPerRow - 1
        return CGSize(width: minWidth, height: Self.gridRowHeight)
    }

    func collectionView(_: UICollectionView, layout _: UICollectionViewLayout, minimumInteritemSpacingForSectionAt _: Int) -> CGFloat {
        0.01
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, minimumLineSpacingForSectionAt section: Int) -> CGFloat {
        0.01
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
        let offsetY = scrollView.contentOffset.y
        let contentHeight = scrollView.contentSize.height
        let height = scrollView.frame.size.height
        
        if offsetY > contentHeight - height - 100 {
            loading(true)
            loadMore?()
        }
    }
}


