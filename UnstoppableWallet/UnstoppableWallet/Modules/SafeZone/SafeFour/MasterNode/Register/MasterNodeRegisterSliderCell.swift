import UIKit
import ThemeKit
import SnapKit
import RxSwift
import ComponentKit

class MasterNodeRegisterSliderCell: UITableViewCell {
 
    private let disposeBag = DisposeBag()
    private let titleLabel: UILabel
    private let slider: UISlider
    private let creatorLabel: UILabel
    private let partnerLabel: UILabel
    private let viewModel: MasterNodeRegisterViewModel
    init(viewModel: MasterNodeRegisterViewModel) {
        self.viewModel = viewModel
        
        titleLabel = UILabel(frame: .zero)
        titleLabel.font = UIFont.systemFont(ofSize: 14)
        titleLabel.textColor = .themeGray
        
        creatorLabel = UILabel(frame: .zero)
        creatorLabel.font = .subhead1
        creatorLabel.textColor = .themeBlackAndWhite
        
        
        partnerLabel = UILabel(frame: .zero)
        partnerLabel.font = .subhead1
        partnerLabel.textColor = .themeBlackAndWhite
        partnerLabel.textAlignment = .right
        
        slider = UISlider()
        
        super.init(style: .default, reuseIdentifier: nil)
        
        backgroundColor = .clear
        selectionStyle = .none
        
        contentView.addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(CGFloat.margin16)
            make.trailing.equalToSuperview().inset(CGFloat.margin16)
            make.height.equalTo(20)
            make.top.equalToSuperview().offset(CGFloat.margin12)
        }
        
        addSubview(slider)
        slider.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(CGFloat.margin16)
            make.trailing.equalToSuperview().inset(CGFloat.margin16)
            make.top.equalTo(titleLabel.snp.bottom).offset(CGFloat.margin8)
        }
        slider.addTarget(self, action: #selector(sliderValueChanged(_:)), for: .valueChanged)
        
        addSubview(creatorLabel)
        creatorLabel.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(CGFloat.margin16)
            make.top.equalTo(slider.snp.bottom).offset(CGFloat.margin8)
        }
        
        addSubview(partnerLabel)
        partnerLabel.snp.makeConstraints { make in
            make.leading.equalTo(creatorLabel.snp.trailing).offset(CGFloat.margin8)
            make.trailing.equalToSuperview().inset(CGFloat.margin16)
            make.top.equalTo(slider.snp.bottom).offset(CGFloat.margin8)
            make.width.equalTo(creatorLabel)
        }
        
        slider.minimumValue = viewModel.masterNodeIncentive.sliderMinimumValue
        slider.maximumValue  = viewModel.masterNodeIncentive.sliderMaximumValue
        slider.value = viewModel.masterNodeIncentive.sliderValue
        titleLabel.text = "safe_zone.safe4.mining.plan".localized
        creatorLabel.text = "safe_zone.safe4.node.creator".localized + "\(viewModel.masterNodeIncentive.creatorIncentive)%"
        partnerLabel.text = "safe_zone.safe4.partner".localized + "\(viewModel.masterNodeIncentive.partnerIncentive)%"
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @objc
    private func sliderValueChanged(_ sender: UISlider) {
        guard sender.value <= viewModel.masterNodeIncentive.creatorMaxIncentive else {
            slider.value = viewModel.masterNodeIncentive.creatorMaxIncentive
            sync()
            return
        }
        let value = Float(Int(sender.value))
        slider.value = max(viewModel.masterNodeIncentive.creatorMinIncentive, value)
        sync()
    }
    
    func sync() {
        viewModel.update(sliderValue: slider.value)
        
        creatorLabel.text = "safe_zone.safe4.node.creator".localized + "\(viewModel.masterNodeIncentive.creatorIncentive)%"
        partnerLabel.text = "safe_zone.safe4.partner".localized + "\(viewModel.masterNodeIncentive.partnerIncentive)%"
    }
}
