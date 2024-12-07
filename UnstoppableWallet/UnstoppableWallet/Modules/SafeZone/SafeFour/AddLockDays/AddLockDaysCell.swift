import ComponentKit
import RxCocoa
import RxSwift
import SnapKit
import ThemeKit
import UIKit
import UIExtensions

class AddLockDaysSliderCell: BaseThemeCell {
    private let slider: UISlider
    private let lockDaysLabel = UILabel()
    private var step: Float?

    var lockDays: ((Float) -> Void)?
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        slider = UISlider()
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        
        set(backgroundStyle: .lawrence, isFirst: true, isLast: true)
        
        lockDaysLabel.text = "锁定天数".localized
        lockDaysLabel.font = .body
        wrapperView.addSubview(lockDaysLabel)
        lockDaysLabel.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(CGFloat.margin8)
            make.leading.equalToSuperview().offset(CGFloat.margin16)
            make.trailing.equalToSuperview().inset(CGFloat.margin16)
            make.height.equalTo(CGFloat.margin24)
        }
        
        wrapperView.addSubview(slider)
        slider.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(CGFloat.margin16)
            make.trailing.equalToSuperview().inset(CGFloat.margin16)
            make.top.equalTo(lockDaysLabel.snp.bottom).offset(CGFloat.margin12)
        }
        slider.addTarget(self, action: #selector(sliderValueChanged(_:)), for: .valueChanged)
    }
    
    func bind(value: Float?, step: Float, minimumValue: Float, maximumValue: Float) {
        self.step = step
        slider.minimumValue = minimumValue
        slider.maximumValue = maximumValue
        slider.value = value ?? minimumValue
        lockDaysLabel.text = "锁定天数".localized + ": \(Int(slider.value))天"
        lockDays?(slider.value)
    }

    @objc
    private func sliderValueChanged(_ sender: UISlider) {
        guard let step else{ return }
        let roundedValue = round(sender.value / step) * step
        sender.value = roundedValue
        lockDaysLabel.text = "锁定天数".localized + ": \(Int(slider.value))天"
        lockDays?(slider.value)
    }
    
    func height() -> CGFloat {
        85
    }
}
