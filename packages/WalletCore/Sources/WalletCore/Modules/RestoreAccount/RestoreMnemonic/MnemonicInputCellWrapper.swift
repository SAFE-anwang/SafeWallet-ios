import Combine
import SwiftUI

struct MnemonicInputCellWrapper: UIViewRepresentable {
    private static let appearDuration: TimeInterval = 0.5

    let statPage: StatPage
    let placeholder: String
    @Binding var text: String
    @Binding var invalidRanges: [NSRange]
    let cautionType: CautionType?
    let replaceWordPublisher: AnyPublisher<(NSRange, String), Never>
    @Binding var heightTrigger: Bool
    @Binding var isFocused: Bool
    let onChangeMnemonicText: (String, Int) -> Void
    let onChangeEntering: (Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> MnemonicInputCell {
        let coordinator = context.coordinator
        let binding = $heightTrigger
        let cell = MnemonicInputCell(statPage: statPage, statEntity: .recoveryPhrase)
        cell.contentView.backgroundColor = .clear
        cell.set(placeholderText: placeholder)
        if !text.isEmpty {
            cell.set(text: text, notifyMnemonicChange: false)
        }

        cell.onChangeMnemonicText = { text, cursorOffset in
            DispatchQueue.main.async { onChangeMnemonicText(text, cursorOffset) }
        }
        cell.onChangeEntering = { [weak cell] in
            guard let cell else { return }
            onChangeEntering(cell.entering)
        }
        cell.onChangeHeight = {
            DispatchQueue.main.async { binding.wrappedValue.toggle() }
        }
        cell.onOpenViewController = { [weak cell] vc in
            cell?.parentViewController?.present(vc, animated: true)
        }

        coordinator.cancellable = replaceWordPublisher.sink { [weak cell] range, word in
            DispatchQueue.main.async { cell?.replaceWord(range: range, word: word) }
        }
        return cell
    }

    func updateUIView(_ uiView: MnemonicInputCell, context: Context) {
        if uiView.textView.text != text {
            uiView.set(text: text, notifyMnemonicChange: false)
        }
        uiView.set(invalidRanges: invalidRanges)
        uiView.set(cautionType: cautionType)

        let coordinator = context.coordinator
        if !isFocused {
            coordinator.focusWorkItem?.cancel()
            coordinator.focusWorkItem = nil
            coordinator.focusGeneration &+= 1
        }
        guard isFocused != coordinator.lastIsFocused else { return }
        coordinator.lastIsFocused = isFocused

        if isFocused {
            let delay: TimeInterval = coordinator.didFirstFocus ? 0 : Self.appearDuration
            coordinator.didFirstFocus = true
            coordinator.focusGeneration &+= 1
            let generation = coordinator.focusGeneration
            let workItem = DispatchWorkItem { [weak uiView, weak coordinator] in
                guard let coordinator,
                      coordinator.lastIsFocused,
                      coordinator.focusGeneration == generation else { return }
                _ = uiView?.becomeFirstResponder()
                coordinator.focusWorkItem = nil
            }
            coordinator.focusWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
        } else {
            uiView.endEditing(true)
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: MnemonicInputCell, context _: Context) -> CGSize? {
        let _ = heightTrigger
        let width = proposal.width ?? UIScreen.main.bounds.width
        return CGSize(width: width, height: uiView.cellHeight(containerWidth: width))
    }

    final class Coordinator {
        var cancellable: AnyCancellable?
        var didFirstFocus = false
        var lastIsFocused = false
        var focusGeneration = 0
        var focusWorkItem: DispatchWorkItem?
    }
}

private extension UIView {
    var parentViewController: UIViewController? {
        var responder: UIResponder? = self
        while let currentResponder = responder {
            if let viewController = currentResponder as? UIViewController { return viewController }
            responder = currentResponder.next
        }
        return nil
    }
}
