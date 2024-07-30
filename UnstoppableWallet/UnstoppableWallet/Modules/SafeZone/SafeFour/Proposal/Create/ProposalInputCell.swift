import UIKit
import ComponentKit
import RxSwift

class ProposalInputCell: Safe4BaseInputCell {
    private let viewModel: ProposalCreateViewModel
    private let disposeBag = DisposeBag()

    init(viewModel: ProposalCreateViewModel, type: InputType) {
        self.viewModel = viewModel
        super.init()
        
        onChangeText = { [weak self] in
            self?.viewModel.onChange(text: $0, type: type)
        }
        
        onChangeEditing =  { [weak self] isEditing in
            guard !isEditing else { return }
            switch type {
            case .safeAmount:
                if let text = self?.viewModel.amount {
                    self?.setInput(value: "\(text)")
                }else {
                    self?.setInput(value: nil)
                }
            case .payTimes:
                if let text = self?.viewModel.payTimes {
                    self?.setInput(value: "\(text)")
                }else {
                    self?.setInput(value: nil)
                }
            case .title, .desc: ()
            }
        }
        
        setTitle(text: type.title)
        setInput(keyboardType: type.keyboardType, placeholder: type.placeholder)

        switch type {
        case .title:
            subscribe(disposeBag, viewModel.titleCautionDriver) {  [weak self] in
                self?.set(cautionType: $0?.type)
            }
        case .desc:
            subscribe(disposeBag, viewModel.descCautionDriver) {  [weak self] in
                self?.set(cautionType: $0?.type)
            }
        case .safeAmount:
            subscribe(disposeBag, viewModel.amountCautionDriver) {  [weak self] in
                self?.set(cautionType: $0?.type)
            }
        case .payTimes:
            subscribe(disposeBag, viewModel.payTimesCautionDriver) {  [weak self] in
                self?.set(cautionType: $0?.type)
            }
        }

    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    

}
extension ProposalInputCell: UITextFieldDelegate {
    
}

extension ProposalInputCell {
    enum InputType {
        case title
        case desc
        case safeAmount
        case payTimes
        
        var title: String {
            switch self {
            case .title: return "safe_zone.safe4.proposal.create.title".localized
            case .desc: return "safe_zone.safe4.proposal.create.desc".localized
            case .safeAmount: return "safe_zone.safe4.proposal.create.apply.amount".localized
            case .payTimes: return "safe_zone.safe4.proposal.create.payTimes".localized
            }
        }
        
        var placeholder: String {
            switch self {
            case .title: return "safe_zone.safe4.proposal.create.placeholder.title".localized
            case .desc: return "safe_zone.safe4.proposal.create.placeholder.desc".localized
            case .safeAmount: return "safe_zone.safe4.proposal.create.placeholder.apply.amount".localized
            case .payTimes: return "safe_zone.safe4.proposal.create.placeholder.payTimes".localized
            }
        }
        
        var keyboardType: UIKeyboardType {
            switch self {
            case .title: return .default
            case .desc: return .default
            case .safeAmount: return .decimalPad
            case .payTimes: return .numberPad
            }
        }
    }
}
