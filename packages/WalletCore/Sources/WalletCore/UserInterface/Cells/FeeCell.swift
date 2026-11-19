import RxCocoa
import RxSwift
import SwiftUI
import UIKit

protocol IFeeViewModel {
    var valueDriver: Driver<FeeCell.Value?> { get }
    var spinnerVisibleDriver: Driver<Bool> { get }
}

class FeeCell: BaseThemeCell {
    private let disposeBag = DisposeBag()

    private let viewModel: IFeeViewModel
    private let title: String
    private let showInfoIcon: Bool
    private var value: FeeCell.Value?
    private var spinnerVisible = false
    private var hostedContentView: UIView?

    var onOpenInfo: (() -> Void)?

    init(viewModel: IFeeViewModel, title: String, showInfoIcon: Bool = true, isFirst: Bool = true, isLast: Bool = true) {
        self.viewModel = viewModel
        self.title = title
        self.showInfoIcon = showInfoIcon

        super.init(style: .default, reuseIdentifier: nil)

        backgroundColor = .clear
        clipsToBounds = true
        set(backgroundStyle: .lawrence, isFirst: isFirst, isLast: isLast)
        installContentView()
        sync()

        subscribe(disposeBag, viewModel.valueDriver) { [weak self] value in
            self?.value = value
            self?.sync()
        }
        subscribe(disposeBag, viewModel.spinnerVisibleDriver) { [weak self] visible in
            self?.spinnerVisible = visible
            self?.sync()
        }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func installContentView() {
        let contentView = UIHostingConfiguration {
            FeeCellRow(
                title: title,
                showInfoIcon: showInfoIcon,
                value: value,
                spinnerVisible: spinnerVisible,
                onOpenInfo: { [weak self] in self?.onOpenInfo?() }
            )
        }
        .margins(.all, 0)
        .makeContentView()

        hostedContentView = contentView
        wrapperView.insertSubview(contentView, belowSubview: topSeparatorView)
        contentView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
    }

    private func sync() {
        guard let contentView = hostedContentView as? UIContentView else {
            return
        }

        contentView.configuration = UIHostingConfiguration {
            FeeCellRow(
                title: title,
                showInfoIcon: showInfoIcon,
                value: value,
                spinnerVisible: spinnerVisible,
                onOpenInfo: { [weak self] in self?.onOpenInfo?() }
            )
        }
        .margins(.all, 0)
    }
}

private struct FeeCellRow: View {
    let title: String
    let showInfoIcon: Bool
    let value: FeeCell.Value?
    let spinnerVisible: Bool
    let onOpenInfo: () -> Void

    var body: some View {
        Cell(style: .secondary, middle: {
            if showInfoIcon {
                Button(action: onOpenInfo) {
                    HStack(spacing: .margin8) {
                        ThemeText(title, style: .subheadR, colorStyle: .secondary)
                        ThemeImage("circle_information_20", size: .iconSize20, colorStyle: .primary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                ThemeText(title, style: .subheadR, colorStyle: .secondary)
            }
        }, right: {
            HStack(spacing: .margin8) {
                valueView
                if spinnerVisible {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.themeGray)
                        .frame(width: .iconSize20, height: .iconSize20)
                }
            }
        })
        .frame(maxWidth: .infinity, minHeight: .heightDoubleLineCell)
    }

    @ViewBuilder private var valueView: some View {
        switch value {
        case let .regular(text, secondaryText):
            VStack(alignment: .trailing, spacing: 1) {
                ThemeText(text, style: .subhead, colorStyle: .primary)
                    .multilineTextAlignment(.trailing)
                ThemeText(secondaryText ?? "---", style: .caption, colorStyle: .secondary)
                    .multilineTextAlignment(.trailing)
            }
        case let .error(text):
            ThemeText(text, style: .subhead, colorStyle: .red)
                .multilineTextAlignment(.trailing)
        case let .disabled(text):
            ThemeText(text, style: .subhead, colorStyle: .secondary)
                .multilineTextAlignment(.trailing)
        case nil:
            EmptyView()
        }
    }
}

extension FeeCell {
    enum Value: Equatable {
        case disabled(text: String)
        case regular(text: String, secondaryText: String?)
        case error(text: String)
    }
}
