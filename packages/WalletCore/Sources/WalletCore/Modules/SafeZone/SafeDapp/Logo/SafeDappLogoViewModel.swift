import BigInt
import Foundation
import UIKit
import web3swift

class SafeDappLogoViewModel: ObservableObject {
    let info: DAppInfo
    private let service: SafeDappService

    @Published var selectedImage: UIImage? {
        didSet { syncLogoData() }
    }
    @Published private(set) var logoData: Data?
    @Published private(set) var fee: Decimal?
    @Published var logoCautionState: CautionState = .none
    @Published var sendState: SafeDappAsyncState = .idle

    init(info: DAppInfo, currentLogo: UIImage?, service: SafeDappService) {
        self.info = info
        self.selectedImage = currentLogo
        self.service = service
        loadFee()
    }

    private func loadFee() {
        Task {
            let fee = try? await service.getLogoPayAmount().safe4ToDecimal()
            await MainActor.run {
                self.fee = fee
            }
        }
    }

    private func syncLogoData() {
        guard let selectedImage else {
            logoData = nil
            logoCautionState = .none
            sendState = .idle
            return
        }
        guard let data = SafeDappValidation.logoData(from: selectedImage) else {
            logoData = nil
            logoCautionState = .caution(Caution(text: "safe_dapp.logo_oversize".localized, type: .error))
            sendState = .idle
            return
        }
        logoData = data
        logoCautionState = .none
        sendState = .ready
    }

    func upload(onComplete: @escaping (SafeDappAsyncState) -> Void) {
        guard let logoData else {
            logoCautionState = .caution(Caution(text: "safe_dapp.logo_required".localized, type: .error))
            onComplete(sendState)
            return
        }
        sendState = .sending
        Task {
            do {
                let logoPayAmount = try await service.getLogoPayAmount()
                let availableBalance = try await service.availableBalance()
                guard availableBalance > logoPayAmount else {
                    await MainActor.run {
                        sendState = .ready
                        onComplete(.failed("safe_dapp.insufficient_safe_balance".localized))
                    }
                    return
                }
                _ = try await service.setLogo(id: info.id, logo: logoData)
                await MainActor.run {
                    sendState = .completed
                    onComplete(sendState)
                }
            } catch {
                await MainActor.run {
                    sendState = .failed(error.localizedDescription)
                    onComplete(sendState)
                }
            }
        }
    }
}
