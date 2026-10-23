import SwiftUI

struct Safe4NetworkToggleRow: View {
    @StateObject private var service = Safe4NetworkSwitchService.live()
    @State private var showingSwitchError = false

    var body: some View {
        HStack(spacing: .margin16) {
            VStack(spacing: 1) {
                Text("SAFE TestNet").themeBody()
//                Text(service.isTestNet ? "TestNet" : "MainNet").themeSubhead2()
            }

            Spacer()

            ThemeToggle(
                isOn: Binding(
                    get: { service.isTestNet },
                    set: { service.set(testNet: $0) }
                )
            )
            .disabled(service.isSwitching)
        }
        .padding(.horizontal, .margin16)
        .frame(height: .heightCell56)
        .onChange(of: service.switchError) { error in
            showingSwitchError = error != nil
        }
        .alert("safe4.network.switch.error.title".localized, isPresented: $showingSwitchError) {
            Button("safe4.network.switch.retry".localized) {
                service.set(testNet: service.isTestNet)
            }
            Button("safe4.network.switch.dismiss".localized, role: .cancel) {}
        } message: {
            Text(service.switchError ?? "safe4.network.switch.error.generic".localized)
        }
    }
}
