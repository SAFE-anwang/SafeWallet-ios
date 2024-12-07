
import UIKit
import ThemeKit
import SnapKit
import RxSwift
import ComponentKit

class Safe4NodeUpdateButtonCell: BaseThemeCell {

    private let updateButton = UIButton(type: .custom)
    var onTap: (() -> Void)?
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        
        updateButton.titleLabel?.font = .subhead1
        updateButton.borderColor = .themeLightGray
        updateButton.borderWidth = 1
        updateButton.cornerRadius = .cornerRadius4
        updateButton.contentEdgeInsets = UIEdgeInsets(top: 4, left: 10, bottom: 4, right: 10)
        updateButton.setBackgroundColor(.themeIssykBlue, for: .normal)
        updateButton.setBackgroundColor(.lightGray.withAlphaComponent(0.4) , for: .disabled)
        updateButton.setTitle("safe_zone.safe4.info.update.button".localized, for: .normal)
        updateButton.addTarget(self, action: #selector(update), for: .touchUpInside)
        updateButton.isEnabled = false
        
        wrapperView.addSubview(updateButton)
        updateButton.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(CGFloat.margin16)
            make.centerY.equalToSuperview()
        }
    }
    
    @objc private func update() {
        onTap?()
    }
    
    func bind(isEnabled: Bool) {
        updateButton.isEnabled = isEnabled
    }
}
