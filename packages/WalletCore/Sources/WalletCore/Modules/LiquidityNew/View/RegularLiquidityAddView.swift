import MarketKit
import SwiftUI

struct RegularLiquidityAddView: View {
    @Environment(\.presentationMode) private var presentationMode

    var token: Token? = nil

    var body: some View {
        ThemeNavigationStack {
            LiquidityAddView(token: token) {
                presentationMode.wrappedValue.dismiss()
            }
            .navigationTitle("liquidity.title.add".localized)
            .toolbar {
                ToolbarItem {
                    Button("button.cancel".localized) {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
        }
    }
}
