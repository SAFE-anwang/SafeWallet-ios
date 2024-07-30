import UIKit
import ThemeKit
import SnapKit
import RxSwift
import ComponentKit

class MultilineInputView: UIView {
    private let formValidatedView: FormValidatedView
    private let inputStackView = InputStackView()

    private let stateView = InputStateWrapperView()

    private let deleteView = InputSecondaryCircleButtonWrapperView()
    var onChangeText: ((String?) -> Void)?

    var showContacts: Bool = false {
        didSet {
            syncButtonStates()
        }
    }

    init() {
        formValidatedView = FormValidatedView(contentView: inputStackView, padding: UIEdgeInsets(top: 0, left: .margin16, bottom: 0, right: .margin16))

        super.init(frame: .zero)

        backgroundColor = .clear

        addSubview(formValidatedView)
        formValidatedView.snp.makeConstraints { maker in
            maker.edges.equalToSuperview()
        }

        stateView.isSpinnerVisible = false
        stateView.isSuccessVisible = false

        deleteView.button.set(image: UIImage(named: "trash_20"))
        deleteView.onTapButton = { [weak self] in self?.onTapDelete() }
        
        inputStackView.autocapitalizationType = .none
        inputStackView.autocorrectionType = .no

        inputStackView.appendSubview(stateView)
        inputStackView.appendSubview(deleteView)

        inputStackView.onChangeText = { [weak self] text in
            self?.handleChange(text: text)
        }
        
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

    private func handleChange(text: String?) {
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

extension MultilineInputView {
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

    func set(isSuccess: Bool) {
        stateView.isSuccessVisible = isSuccess
    }

    func set(isLoading: Bool) {
        stateView.isSpinnerVisible = isLoading
    }

    var onChangeEditing: ((Bool) -> Void)? {
        get { inputStackView.onChangeEditing }
        set { inputStackView.onChangeEditing = newValue }
    }

    var onChangeHeight: (() -> Void)? {
        get { formValidatedView.onChangeHeight }
        set { formValidatedView.onChangeHeight = newValue }
    }

    func height(containerWidth: CGFloat) -> CGFloat {
        formValidatedView.height(containerWidth: containerWidth)
    }

    var isValidText: ((String) -> Bool)? {
        get { inputStackView.isValidText }
        set { inputStackView.isValidText = newValue }
    }
}

