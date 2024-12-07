import UIKit
import ThemeKit
import SnapKit
import RxSwift
import ComponentKit

class Safe4BaseInputCell: UITableViewCell {
    
    private let anInputView: MultilineInputView
    private let titleLabel: UILabel
    
    init() {
        anInputView = MultilineInputView()
        titleLabel = UILabel(frame: .zero)
        titleLabel.font = UIFont.systemFont(ofSize: 14)
        titleLabel.textColor = .themeGray
        
        super.init(style: .default, reuseIdentifier: nil)
        
        backgroundColor = .clear
        selectionStyle = .none
        contentView.addSubview(titleLabel)
        titleLabel.snp.makeConstraints { maker in
            maker.leading.trailing.equalTo(20)
            maker.top.equalTo(5)
        }
        
        contentView.addSubview(anInputView)
        anInputView.snp.makeConstraints { maker in
            maker.top.equalTo(titleLabel.snp.bottom).offset(4)
            maker.bottom.leading.trailing.equalToSuperview()
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func becomeFirstResponder() -> Bool {
        anInputView.becomeFirstResponder()
    }
    
    var inputText: String? {
        anInputView.inputText
    }
    
    var onChangeEditing: ((Bool) -> Void)? {
        get { anInputView.onChangeEditing }
        set { anInputView.onChangeEditing = newValue }
    }

    var onChangeText: ((String?) -> Void)? {
        get { anInputView.onChangeText }
        set { anInputView.onChangeText = newValue }
    }

    var isValidText: ((String) -> Bool)? {
        get { anInputView.isValidText }
        set { anInputView.isValidText = newValue }
    }
    
    var onChangeHeight: (() -> Void)? {
        get { anInputView.onChangeHeight }
        set { anInputView.onChangeHeight = newValue }
    }
    
    func setTitle(text: String?) {
        titleLabel.text = text
    }
    
    func setInput(value: String?) {
        anInputView.inputText = value
    }
    
    func setInput(keyboardType: UIKeyboardType, placeholder: String?) {
        anInputView.keyboardType = keyboardType
        anInputView.inputPlaceholder = placeholder
    }
    
    func set(cautionType: CautionType?) {
        anInputView.set(cautionType: cautionType)
    }
    
    func height(containerWidth: CGFloat) -> CGFloat {
        anInputView.height(containerWidth: containerWidth) + (titleLabel.text == nil ? 0 : 30)
    }
}
