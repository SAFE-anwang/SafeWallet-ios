import SwiftUI

struct Safe4NetworkToggleRow: View {
    @StateObject private var service = Safe4NetworkSwitchService.live()

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
    }
}
