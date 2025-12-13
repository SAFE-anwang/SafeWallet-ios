import Foundation
import UIKit
import SnapKit
import RxSwift
import HsToolKit
class ProposalDatePickerCell: UITableViewCell, UITextFieldDelegate {
    private let titleLabel: UILabel
    
    private let startTimeField: DatePickerView
    private let endTimeField: DatePickerView
    
    private let disposeBag = DisposeBag()
    private let viewModel: ProposalCreateViewModel
        
    init(viewModel: ProposalCreateViewModel) {
        self.viewModel = viewModel
        
        titleLabel = UILabel(frame: .zero)
        titleLabel.text = "safe_zone.safe4.proposal.create.pay.time".localized
        titleLabel.font = UIFont.systemFont(ofSize: 14)
        titleLabel.textColor = .themeGray

        startTimeField = DatePickerView()
        startTimeField.font  = .subhead2
        startTimeField.placeholder = "safe_zone.safe4.proposal.create.time.start".localized
        startTimeField.borderStyle = .roundedRect
        if let start = viewModel.startMinimumDate {
            startTimeField.date = start
            startTimeField.minimumDate = start
        }
        
        endTimeField = DatePickerView()
        endTimeField.font  = .subhead2
        endTimeField.placeholder = "safe_zone.safe4.proposal.create.time.end".localized
        endTimeField.borderStyle = .roundedRect
        
        super.init(style: .default, reuseIdentifier: nil)
        backgroundColor = .clear
        selectionStyle = .none
        
        startTimeField.delegate = self
        endTimeField.delegate = self

        contentView.addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.leading.trailing.equalTo(20)
            make.top.equalTo(5)
        }
        
        contentView.addSubview(startTimeField)
        startTimeField.snp.makeConstraints { make in
            make.top.equalTo(titleLabel.snp.bottom).offset(4)
            make.leading.equalToSuperview().offset(16)
            make.bottom.equalToSuperview()
        }
        
        contentView.addSubview(endTimeField)
        endTimeField.snp.makeConstraints { make in
            make.top.equalTo(titleLabel.snp.bottom).offset(4)
            make.leading.equalTo(startTimeField.snp.trailing).offset(10)
            make.trailing.equalToSuperview().inset(16)
            make.width.equalTo(startTimeField)
            make.bottom.equalToSuperview()
        }
        
        sync()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func sync() {
        startTimeField.onChangeDate = {[weak self] in
            self?.viewModel.set(startDate: $0)
            if let end = self?.endTimeField.currentDate, $0 > end {
                self?.endTimeField.update(date: nil)
                self?.viewModel.set(endDate: nil)
            }else {
                self?.endTimeField.update(date: self?.viewModel.endMinimumDate($0))
                self?.viewModel.set(endDate: self?.viewModel.endMinimumDate($0))
            }
            self?.endTimeField.date = (self?.viewModel.endMinimumDate($0))!
            self?.endTimeField.minimumDate = self?.viewModel.endMinimumDate($0)
        }
        
        endTimeField.onChangeDate = {[weak self] in
            self?.viewModel.set(endDate: $0)
            if self?.startTimeField.currentDate == nil {
                self?.startTimeField.date = $0
                self?.viewModel.set(startDate: $0)
                self?.startTimeField.minimumDate = $0
            }
        }
        
        subscribe(disposeBag, viewModel.payTypeDriver) {  [weak self] type in
            switch type {
            case .all:
                self?.startTimeField.placeholder = "safe_zone.safe4.proposal.create.time.placeholder.choose".localized
                self?.endTimeField.isHidden = true
            case .periodization:
                self?.startTimeField.placeholder = "safe_zone.safe4.proposal.create.time.start".localized
                self?.endTimeField.isHidden = false
            }
        }
    }

    func textFieldShouldBeginEditing(_ textField: UITextField) -> Bool {
        return true
    }
}

class DatePickerView: UITextField {
    private let datePicker: UIDatePicker
    
    var onChangeDate: ((Date) -> Void)?

    init() {
        
        datePicker = UIDatePicker()
        datePicker.preferredDatePickerStyle = .compact
        datePicker.datePickerMode = .dateAndTime
        datePicker.backgroundColor = .white
        
        super.init(frame: .zero)
        
        let toolbar = UIToolbar()
        toolbar.sizeToFit()
        let doneButton = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(donePressed))
        let datePickerView = UIBarButtonItem(customView: datePicker)
        let flexibleSpace = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        toolbar.setItems([datePickerView,flexibleSpace, doneButton], animated: true)
        
        self.inputView = UIView(frame: CGRect(x: 0, y: 0, width: UIScreen().bounds.width, height: 100))
        self.inputAccessoryView = toolbar

        datePicker.addTarget(self, action: #selector(dateChanged(_:)), for: .valueChanged)
    }
    
    var minimumDate: Date? {
        get { datePicker.minimumDate }
        set { datePicker.minimumDate = newValue }
    }
    
    var date: Date {
        get { datePicker.date }
        set { datePicker.date = newValue }
    }
    
    private(set) var currentDate: Date?
    
    func update(date: Date?) {
        currentDate = date
        if let date {
            self.text = dateFormatter(date: date)
        }else {
            self.text = nil
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @objc private func donePressed() {
        onChangeDate?(datePicker.date)
        currentDate = datePicker.date
        self.text = dateFormatter(date: datePicker.date)
        self.endEditing(true)
    }
    
    @objc private func dateChanged(_ datePicker: UIDatePicker) {
        self.text = dateFormatter(date: datePicker.date)
        onChangeDate?(datePicker.date)
    }
    
    private func dateFormatter(date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }
    
}
