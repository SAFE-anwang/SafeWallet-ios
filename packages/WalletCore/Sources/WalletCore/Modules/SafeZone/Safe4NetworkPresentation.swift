import Combine
import SwiftUI

extension Coordinator {
    func presentSafe4(@ViewBuilder content: @escaping (Binding<Bool>) -> some View) {
        let session = Safe4NetworkSession()
        present { isPresented in
            content(isPresented)
                .onAppear {
                    if !session.isValid { isPresented.wrappedValue = false }
                }
                .onReceive(NotificationCenter.default.publisher(for: .safe4NetworkWillSwitch)) { _ in
                    isPresented.wrappedValue = false
                }
        }
    }
}
