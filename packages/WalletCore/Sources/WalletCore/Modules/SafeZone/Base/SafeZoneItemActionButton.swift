import SwiftUI

struct SafeZoneItemActionGrid<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 76), spacing: .margin8)],
            alignment: .leading,
            spacing: .margin8
        ) {
            content
        }
    }
}

struct SafeZoneItemActionButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .truncationMode(.tail)
                .multilineTextAlignment(.center)
        }
        .buttonStyle(SafeZoneItemActionButtonStyle())
    }
}

private struct SafeZoneItemActionButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.themeCaptionSB)
            .foregroundStyle(foregroundColor(isPressed: configuration.isPressed))
            .frame(maxWidth: .infinity)
            .frame(height: 32)
            .padding(.horizontal, .margin8)
            .background(backgroundColor(isPressed: configuration.isPressed))
            .clipShape(Capsule(style: .continuous))
            .contentShape(Capsule(style: .continuous))
            .animation(.easeOut(duration: 0.2), value: configuration.isPressed)
    }

    private func foregroundColor(isPressed: Bool) -> Color {
        guard isEnabled else {
            return .themeAndy
        }

        return isPressed ? .themeDark.opacity(0.7) : .themeDark
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        guard isEnabled else {
            return .themeBlade
        }

        return isPressed ? .themeYellow50 : .themeYellow
    }
}
