

import Foundation
import UIKit
import ComponentKit

class RedeemSafe3StepCell: BaseThemeCell {
    let stackView = UIStackView()
    let step1 = StepItemView()
    let step2 = StepItemView()
    let step3 = StepItemView()
    
    override init(style: CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        
        selectionStyle = .none
        set(backgroundStyle: .transparent, isLast: true)
        
        wrapperView.addSubview(stackView)
        stackView.snp.makeConstraints { maker in
            maker.edges.equalToSuperview()
        }

        stackView.distribution = .fillEqually
        stackView.axis = .horizontal
        stackView.spacing = .margin8
        
        stackView.addArrangedSubview(step1)
        stackView.addArrangedSubview(step2)
        stackView.addArrangedSubview(step3)
        
        bind(step: 1) 
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func bind(step: Int) {
        step1.bind(title: "safe_zone.safe4.redeem.private.verify".localized, num: "1", isShow: step > 1, isCurrent: step == 1)
        step2.bind(title: "safe_zone.safe4.redeem.fund".localized, num: "2", isShow: step > 2, isCurrent: step == 2)
        step3.bind(title: "safe_zone.safe4.redeem.fund.query".localized, num: "3", isShow: step > 3, isCurrent: step == 3)
    }
}

class StepItemView: UIView {
    let imageView = UIImageView()
    let numLabel = UILabel()
    let titleLabel = UILabel()
    
    init() {
        super.init(frame: .zero)
        backgroundColor = .clear

        addSubview(imageView)
        addSubview(titleLabel)
        
        imageView.layer.cornerRadius = 15
        imageView.clipsToBounds = true
        imageView.contentMode = .center
        imageView.image = UIImage(named: "circle_check_24")?.withTintColor(.themeGreenD)
        imageView.backgroundColor = .themeGray50
        imageView.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(CGFloat.margin12)
            make.centerY.equalToSuperview()
            make.size.equalTo(CGSize(width: 30, height: 30))
        }
        
        numLabel.textAlignment = .center
        numLabel.font = .subhead1
        numLabel.textColor = .white
        numLabel.layer.cornerRadius = 15
        numLabel.clipsToBounds = true
        addSubview(numLabel)
        numLabel.snp.makeConstraints { make in
            make.edges.equalTo(imageView)
            make.size.equalTo(imageView)
        }
        
        titleLabel.font = .subhead2
        titleLabel.snp.makeConstraints { make in
            make.trailing.top.bottom.equalToSuperview()
            make.leading.equalTo(imageView.snp.trailing).offset(CGFloat.margin8)
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func bind(title: String?, num: String?, isShow: Bool, isCurrent: Bool) {
        numLabel.isHidden = isShow
        numLabel.backgroundColor = isCurrent ? .themeIssykBlue : .lightGray
        numLabel.text = num
        titleLabel.text = title
    }
}
