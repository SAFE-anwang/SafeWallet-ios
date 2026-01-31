import SwiftUI
import SwiftKLine

struct KLinePeriodPicker: View {
    
    @Binding var period: KLinePeriod
    
    private let allPeriods: [(KLinePeriod, String)] = [
        (.thirtyMinutes, "30分"),
        (.fourHours, "4时"),
        (.oneDay, "1天"),
    ]
    
    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(allPeriods, id: \.0.identifier) { (period, title) in
                    Button {
                        self.period = period
                    } label: {
                        let isSelected = period == self.period
                        Text(title)
                            .tint(Color(.label).opacity(0.8))
                            .font(.system(size: 12))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Color(.label).opacity(isSelected ? 0.1 : 0)))
                    }
                }
            }
        }
        .scrollIndicators(.hidden)
    }
}

