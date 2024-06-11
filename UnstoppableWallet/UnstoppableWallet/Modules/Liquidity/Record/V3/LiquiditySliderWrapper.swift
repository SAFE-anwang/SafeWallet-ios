import ComponentKit
import HUD
import UIKit

class LiquiditySliderWrapper: UIView {
    
    static let height: CGFloat = 150
    
    private static let margins = UIEdgeInsets(top: .margin4, left: .margin16, bottom: .margin4, right: .margin16)
    private let rateLabel = UILabel()
    private let roundedBackground = UIView()
    private let slider = FeeSlider()
    private var sliderLastValue: Float?
    private let autocompleteView = LiquidityInputAccessoryView(frame: .zero)

    var finishTracking: ((Float) -> Void)?
    
    var sliderRange: ClosedRange<Int> {
        Int(slider.minimumValue) ... Int(slider.maximumValue)
    }
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }
    
    required init() {
        super.init(frame: CGRect.zero)
        backgroundColor = .clear
        
        roundedBackground.backgroundColor = .themeLawrence
        roundedBackground.layer.cornerRadius = .cornerRadius16
        roundedBackground.layer.cornerCurve = .continuous
        roundedBackground.layer.borderColor = UIColor.lightGray.cgColor
        roundedBackground.layer.borderWidth = 1
        addSubview(roundedBackground)
        roundedBackground.snp.makeConstraints { maker in
            maker.edges.equalToSuperview()
        }
        
        rateLabel.text = "0%"
        rateLabel.font = .title3
        roundedBackground.addSubview(rateLabel)
        rateLabel.snp.makeConstraints { maker in
            maker.top.equalToSuperview().inset(CGFloat.margin16)
            maker.leading.trailing.equalToSuperview().inset(CGFloat.margin16)
        }
        
        let thumbImage: UIImage? = .circleImage(size: 18, color: .themeRemus)
        let selectedThumbImage: UIImage? = .circleImage(size: 24, color: .themeRemus)
        slider.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        slider.setContentHuggingPriority(.defaultLow, for: .vertical)
        slider.minimumTrackTintColor = .themeRemus
        slider.setThumbImage(thumbImage, for: .normal)
        slider.setThumbImage(selectedThumbImage, for: .highlighted)
        roundedBackground.addSubview(slider)
        slider.snp.makeConstraints { maker in
            maker.top.equalTo(rateLabel.snp.bottom).offset(CGFloat.margin16)
            maker.leading.trailing.equalToSuperview().inset(CGFloat.margin16)
        }
        
        autocompleteView.heightValue = 44
        autocompleteView.setAutoDeselect(auto: true)
        autocompleteView.setBackgroundColor(.clear)
        roundedBackground.addSubview(autocompleteView)
        autocompleteView.snp.makeConstraints { maker in
            maker.top.equalTo(slider.snp.bottom).offset(CGFloat.margin16)
            maker.leading.trailing.equalToSuperview()
            maker.height.equalTo(44)
        }
        
        slider.onTracking = { [weak self] value, position in
            self?.updateRate(value)
        }
        
        slider.finishTracking = { [weak self] value in
            self?.finishTracking?(value)
        }
        
        autocompleteView.onSelect = { [weak self] value in
            self?.slider.setValue(value, animated: false)
            self?.updateRate(value)
            self?.finishTracking?(value)
        }
    }

     private func updateRate(_ value: Float) {
         rateLabel.text = "\(Int(value * 100))%"
    }
}
