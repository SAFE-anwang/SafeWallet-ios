import SnapKit
import UIKit

public class TransparentIconButtonView: UIView, ISizeAwareView {
    public let button = UIButton()

    public var onTap: (() -> Void)?

    override public init(frame: CGRect) {
        super.init(frame: frame)

        addSubview(button)
        button.snp.makeConstraints { maker in
            maker.edges.equalToSuperview()
        }

        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.contentEdgeInsets = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        button.addTarget(self, action: #selector(_onTap), for: .touchUpInside)
    }

    @available(*, unavailable)
    public required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func _onTap() {
        onTap?()
    }

    public func set(image: UIImage?) {
        button.setImage(image?.withTintColor(.themeGray), for: .normal)
    }

    func width(containerWidth _: CGFloat) -> CGFloat {
        20
    }
}
