import UIKit
import ThemeKit
import SnapKit
import RxSwift
import ComponentKit

class SuperNodeRegisterSliderCell: UITableViewCell {
 
    private let disposeBag = DisposeBag()
    private let titleLabel: UILabel
    private let leftSlider: UISlider
    private let rightSlider: UISlider
    private let creatorLabel: UILabel
    private let partnerLabel: UILabel
    private let voterLabel: UILabel
    private let viewModel: SuperNodeRegisterViewModel
    
    init(viewModel: SuperNodeRegisterViewModel) {
        self.viewModel = viewModel
        
        titleLabel = UILabel(frame: .zero)
        titleLabel.font = UIFont.systemFont(ofSize: 14)
        titleLabel.textColor = .themeGray
        
        leftSlider = UISlider()
        leftSlider.semanticContentAttribute = .forceRightToLeft

        rightSlider = UISlider()
        
        partnerLabel = UILabel(frame: .zero)
        partnerLabel.font = .subhead1
        partnerLabel.textColor = .themeBlack
        
        creatorLabel = UILabel(frame: .zero)
        creatorLabel.font = .subhead1
        creatorLabel.textColor = .themeBlack
        creatorLabel.textAlignment = .center
        
        voterLabel = UILabel(frame: .zero)
        voterLabel.font = .subhead1
        voterLabel.textColor = .themeBlack
        voterLabel.textAlignment = .right
        
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
        
        addSubview(leftSlider)
        leftSlider.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(CGFloat.margin16)
            make.top.equalTo(titleLabel.snp.bottom).offset(CGFloat.margin8)
        }
        
        addSubview(rightSlider)
        rightSlider.snp.makeConstraints { make in
            make.leading.equalTo(leftSlider.snp.trailing)
            make.trailing.equalToSuperview()
            make.top.equalTo(leftSlider)
            make.width.equalTo(leftSlider)
        }
                
        addSubview(partnerLabel)
        partnerLabel.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(CGFloat.margin16)
            make.top.equalTo(leftSlider.snp.bottom).offset(CGFloat.margin8)
        }
        
        addSubview(creatorLabel)
        creatorLabel.snp.makeConstraints { make in
            make.leading.equalTo(partnerLabel.snp.trailing).offset(CGFloat.margin8)
            make.centerX.equalToSuperview()
            make.top.equalTo(partnerLabel)
            make.width.equalTo(partnerLabel)
        }
        
        addSubview(voterLabel)
        voterLabel.snp.makeConstraints { make in
            make.leading.equalTo(creatorLabel.snp.trailing).offset(CGFloat.margin8)
            make.trailing.equalToSuperview().inset(CGFloat.margin16)
            make.top.equalTo(creatorLabel)
            make.width.equalTo(creatorLabel)
        }
        
        leftSlider.addTarget(self, action: #selector(leftSliderValueChanged(_:)), for: .valueChanged)
        rightSlider.addTarget(self, action: #selector(rightSliderValueChanged(_:)), for: .valueChanged)
        
        leftSlider.minimumValue = viewModel.superNodeIncentive.sliderMinimumValue
        leftSlider.maximumValue  = viewModel.superNodeIncentive.sliderMaximumValue
        leftSlider.value = viewModel.superNodeIncentive.leftSliderValue
        
        rightSlider.minimumValue = viewModel.superNodeIncentive.sliderMinimumValue
        rightSlider.maximumValue  = viewModel.superNodeIncentive.sliderMaximumValue
        rightSlider.value = viewModel.superNodeIncentive.rightSliderValue
        
        titleLabel.text = "挖矿奖励分配方案".localized
        partnerLabel.text = "合伙人 \(viewModel.superNodeIncentive.partnerIncentive)%"
        creatorLabel.text = "创建者 \(viewModel.superNodeIncentive.creatorIncentive)%"
        voterLabel.text = "投票人 \(viewModel.superNodeIncentive.voterIncentive)%"
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @objc
    private func leftSliderValueChanged(_ sender: UISlider) {
        guard (sender.value + rightSlider.value) <= viewModel.superNodeIncentive.creatorMaxIncentive else {
             leftSlider.value = viewModel.superNodeIncentive.creatorMaxIncentive - rightSlider.value
            sync()
            return
        }
        leftSlider.value = Float(Int(sender.value))
        sync()
        
    }
    
    @objc
    private func rightSliderValueChanged(_ sender: UISlider) {
        guard (leftSlider.value + sender.value) <= viewModel.superNodeIncentive.creatorMaxIncentive else {
            rightSlider.value = viewModel.superNodeIncentive.creatorMaxIncentive - leftSlider.value
            sync()
            return
        }
        rightSlider.value = Float(Int(sender.value))
        sync()
    }
    
    func sync() {
        viewModel.update(leftSliderValue: leftSlider.value)
        viewModel.update(rightSliderValue: rightSlider.value)
        partnerLabel.text = "合伙人 \(viewModel.superNodeIncentive.partnerIncentive)%"
        creatorLabel.text = "创建者 \(viewModel.superNodeIncentive.creatorIncentive)%"
        voterLabel.text = "投票人 \(viewModel.superNodeIncentive.voterIncentive)%"
    }
}

