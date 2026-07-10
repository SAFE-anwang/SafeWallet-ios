import SwiftUI

struct LiquidityAddTermsView: View {
    @Binding var isPresented: Bool
    let onAccept: () -> Void

    var body: some View {
        ThemeView(style: .list) {
            VStack(spacing: 0) {
                BSTitleView(showGrabber: true, title: "liquidity.terms.title".localized, isPresented: $isPresented)

                ScrollView {
                    VStack(spacing: .margin16) {
                        Text("liquidity.terms.description".localized)
                            .themeSubhead2()
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, .margin32)
                            .padding(.top, .margin12)

                        termsList()
                    }
                    .padding(.horizontal, .margin16)
                }

                VStack(spacing: .margin12) {
                    Button(action: {
                        onAccept()
                        isPresented = false
                    }) {
                        Text("liquidity.terms.accept".localized)
                    }
                    .buttonStyle(PrimaryButtonStyle(style: .yellow))

                    Button(action: {
                        isPresented = false
                    }) {
                        Text("button.cancel".localized)
                    }
                    .buttonStyle(PrimaryButtonStyle(style: .gray))
                }
                .padding(EdgeInsets(top: .margin24, leading: .margin24, bottom: .margin16, trailing: .margin24))
            }
        }
    }

    @ViewBuilder private func termsList() -> some View {
        ListSection {
            termRow(
                icon: "shield_check_24",
                title: "liquidity.terms.decentralized".localized,
                description: "liquidity.terms.decentralized.description".localized
            )

            termRow(
                icon: "globe_24",
                title: "liquidity.terms.cross_chain".localized,
                description: "liquidity.terms.cross_chain.description".localized
            )

            termRow(
                icon: "dialpad_24",
                title: "liquidity.terms.non_custodial".localized,
                description: "liquidity.terms.non_custodial.description".localized
            )

            termRow(
                icon: "warning_2_24",
                title: "liquidity.terms.risks".localized,
                description: "liquidity.terms.risks.description".localized
            )
        }
        .themeListStyle(.bordered)
    }

    @ViewBuilder private func termRow(icon: String, title: String, description: String) -> some View {
        VStack(spacing: .margin8) {
            HStack(spacing: .margin12) {
                Image(icon).themeIcon(color: .themeJacob)
                Text(title).themeSubhead1()
                Spacer()
            }

            Text(description)
                .themeCaption()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, .iconSize24 + .margin12)
        }
        .padding(.margin16)
    }
}
