import Combine
import UIKit
import Foundation
import HsExtensions
import MarketKit
import RxSwift
import EvmKit
import BigInt
import SwiftUI

class SRC20PromotionViewModel: ObservableObject {
    let token: Safe4CustomTokenRecord

    private let maxFileSize = 126 * 1024  // 126KB
    private let type: DeployType
    private let service: SRC20Service
    private let adapter: ISendEthereumAdapter
    @Published private(set) var fee: Decimal?
    @Published var sendState: SendState = .notReady
    @Published var balanceCautionState: CautionState = .none
    @Published var selectedImage: UIImage? {
        didSet {
            syncBalanceCautionState()
        }
    }
    init(token: Safe4CustomTokenRecord, service: SRC20Service, adapter: ISendEthereumAdapter) {
        self.token = token
        self.type = token.deployType
        self.service = service
        self.adapter = adapter
        
        getFee()
    }
    
    var balance: Decimal {
        adapter.balanceData.available
    }
    
    private func getFee() {
        Task{
            do{
                let fee = try await service.getLogoPayAmount(type: token.deployType).safe4ToDecimal()
                DispatchQueue.main.async {
                    self.fee = fee
                }
            }catch{}
        }
    }
    
    @MainActor
    func upload(onComplete: @escaping (SendState) -> Void) {
        guard let image = selectedImage, let imgData = compressImage(image, maxFileSize: maxFileSize) else{ return }
        sendState = .sending
        Task{
            do{
                _ = try await service.setLogoPayAmount(type: token.deployType, logo: imgData)
                sendState = .completed
                onComplete(.completed)
            }catch{
                sendState = .failed
                onComplete(.failed)
            }
        }
    }
    
    var isSendAble: Bool {
        guard let fee else{ return false }
        return balance > fee && selectedImage != nil
    }

}
extension SRC20PromotionViewModel {
    private func syncBalanceCautionState() {
        let caution = validateBalance()
        balanceCautionState = caution != nil ? .caution(caution!) : .none
    }
    
    private func validateBalance() -> Caution? {
        var caution: Caution?
        guard let fee else{
            caution = Caution(text: "未获取到费用".localized, type: .error)
            return caution
        }
        
        if balance < fee {
            caution = Caution(text: "safe_zone.send.insufficientBalance".localized, type: .error)
        }
        
        return caution
    }
}

extension SRC20PromotionViewModel {
    enum SendState: Equatable {
        case notReady
        case ready
        case sending
        case completed
        case failed
        public static func == (lhs: SendState, rhs: SendState) -> Bool {
            switch (lhs, rhs) {
            case (.notReady, .notReady): return true
            case (.ready, .ready): return true
            case (.sending, .sending): return true
            case (.completed, .completed): return true
            case (.failed, .failed): return true
            default: return false
            }
        }
    }
}
extension SRC20PromotionViewModel {
    
    private func compressImage(_ image: UIImage, maxFileSize: Int) -> Data? {
        var compression: CGFloat = 1.0
        var imageData = image.jpegData(compressionQuality: compression)
        
        if let data = imageData, data.count <= maxFileSize {
            return data
        }
        
        while compression > 0.1 {
            compression -= 0.1
            imageData = image.jpegData(compressionQuality: compression)
            
            if let data = imageData, data.count <= maxFileSize {
                return data
            }
        }
        
        var currentImage = image
        var currentSize = currentImage.size
        
        while true {
            let newSize = CGSize(width: currentSize.width * 0.8, height: currentSize.height * 0.8)
            UIGraphicsBeginImageContext(newSize)
            currentImage.draw(in: CGRect(origin: .zero, size: newSize))
            if let resizedImage = UIGraphicsGetImageFromCurrentImageContext() {
                currentImage = resizedImage
                currentSize = newSize
            }
            UIGraphicsEndImageContext()
            
            if let data = currentImage.jpegData(compressionQuality: 0.5), data.count <= maxFileSize {
                return data
            }
            if currentSize.width < 300 || currentSize.height < 300 {
                break
            }
        }
        
        return nil
    }
    
    private func formatFileSize(_ size: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(size))
    }
}
