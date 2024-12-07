import UIKit
import RxSwift

class MasterNodeChangeCell: Safe4BaseInputCell {
    private let viewModel: MasterNodeChangeViewModel
    private let disposeBag = DisposeBag()

    init(viewModel: MasterNodeChangeViewModel, type: MasterNodeInputType) {
        self.viewModel = viewModel
        super.init()
        
        onChangeText = { [weak self] in
            self?.viewModel.onChange(text: $0, type: type)
        }

        setTitle(text: type.title)
        setInput(keyboardType: type.keyboardType, placeholder: type.placeholder)
        
        switch type {
        case .address:
            setInput(value: viewModel.nodeInfo.info.addr.address)
            subscribe(disposeBag, viewModel.addressCautionDriver) {  [weak self] in
                self?.set(cautionType: $0?.type)
            }
        case .ENODE:
            setInput(value: viewModel.nodeInfo.info.enode)
            subscribe(disposeBag, viewModel.enodeCautionDriver) {  [weak self] in
                self?.set(cautionType: $0?.type)
            }
        case .desc:
            setInput(value: viewModel.nodeInfo.info.description)
            subscribe(disposeBag, viewModel.descCautionDriver) {  [weak self] in
                self?.set(cautionType: $0?.type)
            }
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
