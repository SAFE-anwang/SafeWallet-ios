import UIKit
import SnapKit

class BackupWordsController: WalletViewController {
    private let delegate: IBackupWordsViewDelegate

    private let scrollView = UIScrollView()
    private let wordsLabel = UILabel()

    private let proceedButtonHolder = GradientView(gradientHeight: BackupTheme.gradientHeight, viewHeight: BackupTheme.cancelHolderHeight, fromColor: BackupTheme.gradientTransparent, toColor: BackupTheme.gradientSolid)
    private let proceedButton = UIButton()

    init(delegate: IBackupWordsViewDelegate) {
        self.delegate = delegate

        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.backBarButtonItem = UIBarButtonItem(title: "", style: .plain, target: nil, action: nil)
        title = "backup.words.title".localized

        view.addSubview(scrollView)

        view.addSubview(proceedButtonHolder)
        proceedButtonHolder.addSubview(proceedButton)
        scrollView.addSubview(wordsLabel)

        scrollView.showsVerticalScrollIndicator = false
        scrollView.snp.makeConstraints { maker in
            maker.leading.equalToSuperview().offset(BackupTheme.sideMargin)
            maker.trailing.equalToSuperview().offset(-BackupTheme.sideMargin)
            maker.top.equalTo(self.view.snp.topMargin).offset(BackupTheme.wordsTopMargin)
            maker.bottom.equalToSuperview()
        }

        wordsLabel.numberOfLines = 0
        wordsLabel.snp.makeConstraints { maker in
            maker.edges.equalTo(self.scrollView.snp.edges)
            maker.bottom.equalTo(self.scrollView.snp.bottom).offset(-BackupTheme.wordsBottomMargin - BackupTheme.cancelHolderHeight)
        }

        proceedButtonHolder.snp.makeConstraints { maker in
            maker.leading.bottom.trailing.equalToSuperview()
            maker.height.equalTo(BackupTheme.cancelHolderHeight)
        }

        proceedButton.setTitle(delegate.isBackedUp ? "backup.close".localized : "button.next".localized, for: .normal)
        proceedButton.addTarget(self, action: #selector(nextDidTap), for: .touchUpInside)
        proceedButton.setBackgroundColor(color: BackupTheme.backupButtonBackground, forState: .normal)
        proceedButton.setTitleColor(BackupTheme.buttonTitleColor, for: .normal)
        proceedButton.titleLabel?.font = BackupTheme.buttonTitleFont
        proceedButton.cornerRadius = BackupTheme.buttonCornerRadius
        proceedButton.snp.makeConstraints { maker in
            maker.leading.equalToSuperview().offset(BackupTheme.sideMargin)
            maker.trailing.equalToSuperview().offset(-BackupTheme.sideMargin)
            maker.bottom.equalToSuperview().offset(-BackupTheme.sideMargin)
            maker.height.equalTo(BackupTheme.buttonHeight)
        }


        let joinedWords = delegate.words.enumerated().map { "\($0 + 1). \($1)" }.joined(separator: "\n")
        let attributedText = NSMutableAttributedString(string: joinedWords)
        attributedText.addAttribute(NSAttributedString.Key.font, value: UIFont.cryptoTitle4, range: NSMakeRange(0, joinedWords.count))
        attributedText.addAttribute(NSAttributedString.Key.foregroundColor, value: UIColor.crypto_White_Black, range: NSMakeRange(0, joinedWords.count))
        wordsLabel.attributedText = attributedText

    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        return AppTheme.statusBarStyle
    }

    @objc func nextDidTap() {
        delegate.didTapProceed()
    }

}
