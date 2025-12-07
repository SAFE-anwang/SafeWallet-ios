import SwiftUI

struct SafeLineLockRecoardView: View {
    @StateObject var viewModel: SafeLineLockRecoardViewModel
    init(viewModel: SafeLineLockRecoardViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        ScrollableThemeView {
            VStack(spacing: .margin8) {
                Text("safe_lock.recoard.title".localized(viewModel.totalLockedSafe.safe4FomattedAmount))
                    .themeSubhead1(color: .themeLeah)
                    .padding(EdgeInsets(top: .margin16, leading: 0, bottom: 0, trailing: 0))
                LazyVStack {
                    ForEach(viewModel.viewItems, id: \.id) { item in
                        ClickableRow(action: {}) {
                            ItemView(isLocked: true, amount: item.lockedSafe, month: "\(item.month)", address: item.address)
                        }
                    }
                }
                .modifier(ThemeListStyleModifier(themeListStyle: .lawrence, selected: false))
            }
            .padding(EdgeInsets(top: .margin12, leading: .margin16, bottom: .margin32, trailing: .margin16))
        }
        .navigationBarTitle("safe_zone.row.linear".localized)
        .navigationBarTitleDisplayMode(.inline)
    }
    
    struct ItemView: View {
        let isLocked: Bool
        let amount: String
        let month: String
        let address: String
        
        var body: some View {
            VStack(spacing: .margin8) {
                HStack(spacing: .margin8) {
                    Image(isLocked ? "lock_24" : "unlock_24")
                    Text("\(amount) SAFE")
                        .themeSubhead1(color: .themeLeah)
                    Text("safe_lock.amount.locked".localized(month))
                        .themeSubhead1(color: .yellow, alignment: .trailing)
                }
                Text(address)
                    .themeSubhead1(color: .themeLeah)
            }
        }
    }
}

