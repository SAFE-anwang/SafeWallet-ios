import UIKit
import RxSwift

class SuperNodeRegisterCell: Safe4BaseInputCell {
    private let viewModel: SuperNodeRegisterViewModel
    private let disposeBag = DisposeBag()

    init(viewModel: SuperNodeRegisterViewModel, type: InputType) {
        self.viewModel = viewModel
        super.init()
        
        onChangeText = { [weak self] in
            self?.viewModel.onChange(text: $0, type: type)
        }
                
        setTitle(text: type.title)
        setInput(keyboardType: type.keyboardType, placeholder: type.placeholder)
        
        switch type {
        case .address:
            subscribe(disposeBag, viewModel.addressCautionDriver) {  [weak self] in
                self?.set(cautionType: $0?.type)
            }
        case .name:
            subscribe(disposeBag, viewModel.nameCautionDriver) {  [weak self] in
                self?.set(cautionType: $0?.type)
            }
        case .ENODE:
            subscribe(disposeBag, viewModel.enodeCautionDriver) {  [weak self] in
                self?.set(cautionType: $0?.type)
            }
        case .desc:
            subscribe(disposeBag, viewModel.descCautionDriver) {  [weak self] in
                self?.set(cautionType: $0?.type)
            }

        }

    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    enum InputType {
        case address
        case name
        case ENODE
        case desc
        
        var title: String {
            switch self {
            case .address: return "超级节点钱包地址"
            case .name: return "名称"
            case .ENODE: return "ENODE"
            case .desc: return "简介"
            }
        }
        
        var placeholder: String {
            switch self {
            case .address: return "输入超级节点钱包地址"
            case .name: return "输入超级节点名称"
            case .ENODE: return "输入超级节点ENODE"
            case .desc: return "输入超级节点简介信息"
            }
        }
        
        var keyboardType: UIKeyboardType {
            .default
        }
    }
}

