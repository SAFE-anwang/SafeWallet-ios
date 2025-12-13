import UIKit
import Foundation
import RxSwift
import RxRelay
import RxCocoa

class DrawSafe4ViewModel {
    private let service: DrawSafe4Service
    private let disposeBag = DisposeBag()

    init(service: DrawSafe4Service) {
        self.service = service
    }
    
    func onChange(text: String?) {
        service.address = text
    }
    
    func drawSafe4() {
        service.drawSafe4()
    }
    
    var address: String? {
        service.address
    }
    
    var stateObservable: Observable<DrawSafe4Service.State> {
        service.stateObservable
    }
    
    var addressDriver: Driver<String?> {
        service.addressDriver
    }
    
    var addressCautionDriver: Driver<Caution?> {
        service.addressCautionDriver
    }
}
