import SnapKit

import UIKit

class MnemonicInputCell: TextInputCell {
    var onChangeMnemonicText: ((String, Int) -> Void)?
    var onChangeEntering: (() -> Void)?

    private(set) var entering = false {
        didSet {
            onChangeEntering?()
        }
    }

    override func textViewDidChange(_ textView: UITextView) {
        super.textViewDidChange(textView)

        guard let selectedTextRange = textView.selectedTextRange else {
            return
        }

        let cursorOffset = textView.offset(from: textView.beginningOfDocument, to: selectedTextRange.start)
        onChangeMnemonicText?(textView.text, cursorOffset)
    }

    override func textViewDidBeginEditing(_ textView: UITextView) {
        super.textViewDidBeginEditing(textView)

        entering = true
    }

    override func textViewDidEndEditing(_ textView: UITextView) {
        super.textViewDidEndEditing(textView)

        entering = false
    }

    override func set(text: String) {
        set(text: text, notifyMnemonicChange: true)
    }

    func set(text: String, notifyMnemonicChange: Bool) {
        super.set(text: text)
        textView.selectedRange = NSRange(location: text.utf16.count, length: 0)

        if notifyMnemonicChange {
            onChangeMnemonicText?(text, text.utf16.count)
        }
    }
}

extension MnemonicInputCell {
    func set(invalidRanges: [NSRange]) {
        let attributedString = NSMutableAttributedString(string: textView.text, attributes: [
            .foregroundColor: textViewTextColor,
            .font: textViewFont,
        ])

        let textRange = NSRange(location: 0, length: (textView.text as NSString).length)
        for range in invalidRanges {
            let validRange = NSIntersectionRange(range, textRange)
            guard validRange.length > 0 else { continue }
            attributedString.addAttribute(.foregroundColor, value: UIColor.themeLucian, range: validRange)
        }

        let range = textView.selectedRange
        textView.attributedText = attributedString
        textView.selectedRange = range
    }

    func replaceWord(range: NSRange, word: String) {
        var text: String = textView.text

        guard let textRange = Range(range, in: text) else {
            return
        }

        let replaceWord = word + " "
        text.replaceSubrange(textRange, with: replaceWord)

        super.set(text: text)

        let cursorOffset = range.lowerBound + (replaceWord as NSString).length
        if let newPosition = textView.position(from: textView.beginningOfDocument, offset: cursorOffset) {
            textView.selectedTextRange = textView.textRange(from: newPosition, to: newPosition)
        }

        onChangeMnemonicText?(text, cursorOffset)
    }
}
