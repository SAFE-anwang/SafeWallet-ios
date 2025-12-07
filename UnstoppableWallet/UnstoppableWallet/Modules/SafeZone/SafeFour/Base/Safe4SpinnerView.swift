import Foundation
import UIKit

class Safe4SpinnerView: UIView {
    private let spinner = HUDActivityView.create(with: .medium24)

    init() {
        super.init(frame: .zero)
        backgroundColor = .clear
        addSubview(spinner)
        spinner.snp.makeConstraints { maker in
            maker.center.equalToSuperview()
        }
        spinner.startAnimating()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

