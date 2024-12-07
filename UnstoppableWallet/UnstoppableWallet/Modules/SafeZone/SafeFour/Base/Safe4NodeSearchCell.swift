import UIKit
import ThemeKit
import SnapKit
import RxSwift
import ComponentKit

class Safe4NodeSearchCell: BaseThemeCell {
    
    private let formValidatedView: FormValidatedView
    private let inputStackView = InputStackView()
    private let deleteView = InputSecondaryCircleButtonWrapperView()
    private let searchView = InputSecondaryCircleButtonWrapperView()
    private let lineView = SpaceWrapperView()
    var onChangeText: ((String?) -> Void)?
    var onSearch: ((String?) -> Void)?
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        
        formValidatedView = FormValidatedView(contentView: inputStackView, padding: UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0))

        super.init(style: style, reuseIdentifier: reuseIdentifier)

        backgroundColor = .clear
        selectionStyle = .none
        
        set(backgroundStyle: .lawrence, isFirst: true, isLast: true)
        wrapperView.snp.remakeConstraints { make in
            make.edges.equalToSuperview().inset(UIEdgeInsets(top: .margin4, left: .margin16, bottom: .margin4, right: .margin16))
        }

        wrapperView.addSubview(formValidatedView)
        formValidatedView.snp.makeConstraints { maker in
            maker.edges.equalToSuperview()
        }

        inputStackView.autocapitalizationType = .none
        inputStackView.autocorrectionType = .no
        
        deleteView.button.set(image: UIImage(named: "trash_20"))
        deleteView.onTapButton = { [weak self] in self?.onTapDelete() }
        inputStackView.appendSubview(deleteView)
        
        inputStackView.onChangeText = { [weak self] text in
            self?.handleChange(text: text)
        }
        inputStackView.appendSubview(lineView)
        
        searchView.button.set(image: UIImage(named: "search_24"), style: .transparent)
        searchView.onTapButton = { [weak self] in self?.onTapSearch() }
        inputStackView.appendSubview(searchView)

        syncButtonStates()
    }


    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func onTapDelete() {
        inputStackView.text = nil
        handleChange(text: nil)
    }
    
    private func onTapSearch() {
        onSearch?(inputStackView.text)
    }

    private func handleChange(text: String?) {
        if text == "" || text == nil {
            onSearch?(text)
        }
        onChangeText?(text)
        syncButtonStates()
    }

    private func syncButtonStates() {
        if let text = inputStackView.text, !text.isEmpty {
            deleteView.isHidden = false
        } else {
            deleteView.isHidden = true
        }
    }
}

extension Safe4NodeSearchCell {
    var inputPlaceholder: String? {
        get { inputStackView.placeholder }
        set { inputStackView.placeholder = newValue }
    }

    var inputText: String? {
        get { inputStackView.text }
        set {
            inputStackView.text = newValue
            syncButtonStates()
        }
    }
    
    var keyboardType: UIKeyboardType {
        get { inputStackView.keyboardType }
        set { inputStackView.keyboardType = newValue }
    }

    var isEditable: Bool {
        get { inputStackView.isEditable }
        set { inputStackView.isEditable = newValue }
    }

    func set(cautionType: CautionType?) {
        formValidatedView.set(cautionType: cautionType)
    }
    
    func setInput(keyboardType: UIKeyboardType, placeholder: String?) {
        inputStackView.keyboardType = keyboardType
        inputStackView.placeholder = placeholder
        inputStackView.font = UIFont.body.with(traits: .traitItalic)
    }
    
    var onChangeHeight: (() -> Void)? {
        get { formValidatedView.onChangeHeight }
        set { formValidatedView.onChangeHeight = newValue }
    }

    func height(containerWidth: CGFloat) -> CGFloat {
        formValidatedView.height(containerWidth: containerWidth) + 8
    }
}

class SpaceWrapperView: UIView, ISizeAwareView {
    let spaceView = UIView()

    init() {
        super.init(frame: .zero)

        addSubview(spaceView)
        spaceView.snp.makeConstraints { maker in
            maker.edges.equalToSuperview()
            maker.width.equalTo(1)
        }
        
        spaceView.backgroundColor = .themeElena
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func width(containerWidth: CGFloat) -> CGFloat {
        return 1
    }
}
