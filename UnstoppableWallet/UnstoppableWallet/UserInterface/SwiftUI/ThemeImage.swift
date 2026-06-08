import Kingfisher
import SwiftUI

struct ThemeImage: View {
    private let image: ImageType
    private let size: CGSize?
    private let colorStyle: ColorStyle

    init(_ name: CustomStringConvertible, size: CGFloat? = nil, colorStyle: ColorStyle? = nil) {
        self.init(name, size: size.map { CGSize(width: $0, height: $0) }, colorStyle: colorStyle)
    }

    init(_ name: CustomStringConvertible, size: CGSize? = nil, colorStyle: ColorStyle? = nil) {
        if let componentImage = name as? ComponentImage {
            switch componentImage {
            case let .icon(name, localSize, localColorStyle):
                image = .icon(name: name)
                self.size = localSize ?? size
                self.colorStyle = localColorStyle ?? colorStyle ?? .secondary
            case let .image(name, contentMode, localSize):
                image = .image(name: name, contentMode: contentMode)
                self.size = localSize ?? size
                self.colorStyle = .primary
            case let .remote(url, placeholder, localSize):
                image = .remote(url: url, placeholder: placeholder)
                self.size = localSize ?? size
                self.colorStyle = .primary
            }
        } else {
            image = .icon(name: name.description)
            self.size = size ?? .size24
            self.colorStyle = colorStyle ?? .secondary
        }
    }

    var body: some View {
        switch image {
        case let .icon(name):
            Image(name)
                .renderingMode(.template)
                .resizable()
                .foregroundColor(colorStyle.color)
                .applyFrame(size: size ?? .size24)
        case let .image(name: name, contentMode: contentMode):
            if let size {
                Image(name)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .applyFrame(size: size)
            } else {
                Image(name)
            }
        case let .remote(url, placeholder):
            ThemeRemoteImage(url: url, placeholder: placeholder)
                .id(url)
                .applyFrame(size: size)
        }
    }
}

extension ThemeImage {
    enum ImageType {
        case icon(name: String)
        case image(name: String, contentMode: SwiftUICore.ContentMode)
        case remote(url: String, placeholder: String?)
    }
}

extension ThemeImage {
    static let warning = ComponentImage("warning_filled", size: .iconSize72, colorStyle: .yellow)
    static let error = ComponentImage("warning_filled", size: .iconSize72, colorStyle: .red)
    static let info = ComponentImage("warning_filled", size: .iconSize72)
    static let book = ComponentImage("book", size: .iconSize72)
    static let trash = ComponentImage("trash_filled", size: .iconSize72, colorStyle: .red)
    static let shieldOff = ComponentImage("shield_off", size: .iconSize72)
    static let key = ComponentImage("key", size: .iconSize72)
}

private struct ThemeRemoteImage: View {
    let url: String
    let placeholder: String?

    @State private var nftImage: NftImage?
    @State private var shouldTrySvgLoader = false

    private var imageUrl: URL? {
        URL(string: url)
    }

    private var usesSvgLoader: Bool {
        shouldTrySvgLoader || nftImage != nil
    }

    var body: some View {
        Group {
            if usesSvgLoader {
                if let nftImage {
                    ThemeNftImageRepresentable(nftImage: nftImage)
                } else {
                    placeholderView
                        .task(id: url) {
                            await loadSvgIfNeeded()
                        }
                }
            } else if let imageUrl {
                KFImage.url(imageUrl)
                    .resizable()
                    .placeholder {
                        placeholderView
                    }
                    .onFailure { _ in
                        Task {
                            await loadSvgIfNeeded()
                        }
                    }
            } else {
                placeholderView
            }
        }
        .task(id: url) {
            prepareForCurrentUrl()
        }
    }

    @ViewBuilder
    private var placeholderView: some View {
        if let placeholder {
            Image(placeholder)
        } else {
            RoundedRectangle(cornerRadius: .cornerRadius12, style: .continuous)
                .fill(Color.themeBlade)
        }
    }

    private func prepareForCurrentUrl() {
        nftImage = nil
        shouldTrySvgLoader = false

        guard let imageUrl else {
            return
        }

        if NftImageUrlHelper.isLikelySvg(url: imageUrl) {
            shouldTrySvgLoader = true
        }

        guard let cachedSvgImage = NftImageUrlHelper.cachedSvgImage(url: imageUrl) else {
            return
        }

        nftImage = cachedSvgImage
        shouldTrySvgLoader = true
    }

    private func loadSvgIfNeeded() async {
        guard let imageUrl else {
            return
        }

        if let cachedImage = NftImageUrlHelper.cachedSvgImage(url: imageUrl) {
            await MainActor.run {
                nftImage = cachedImage
                shouldTrySvgLoader = true
            }
            return
        }

        let svgImage = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: NftImageUrlHelper.loadSvgImage(url: imageUrl))
            }
        }

        guard let svgImage else {
            return
        }

        await MainActor.run {
            nftImage = svgImage
            shouldTrySvgLoader = true
        }
    }
}

private struct ThemeNftImageRepresentable: UIViewRepresentable {
    let nftImage: NftImage

    func makeUIView(context: Context) -> NftImageView {
        NftImageView()
    }

    func updateUIView(_ uiView: NftImageView, context: Context) {
        uiView.set(nftImage: nftImage)
    }
}
