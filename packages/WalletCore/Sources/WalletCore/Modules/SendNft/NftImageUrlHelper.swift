import Foundation
import Kingfisher
import UIKit

enum NftImageUrlHelper {
    static func isLikelySvg(url: URL) -> Bool {
        let lowercasedAbsoluteString = url.absoluteString.lowercased()
        if lowercasedAbsoluteString.hasPrefix("data:image/svg+xml") {
            return true
        }

        if url.pathExtension.lowercased() == "svg" {
            return true
        }

        return lowercasedAbsoluteString.contains(".svg?") || lowercasedAbsoluteString.contains(".svg#")
    }

    static func cachedSvgImage(url: URL) -> NftImage? {
        guard let data = try? ImageCache.default.diskStorage.value(forKey: url.absoluteString),
              let svgString = svgString(data: data)
        else {
            return nil
        }

        return .svg(string: svgString)
    }

    static func cachedNftImage(url: URL) -> NftImage? {
        if let svgImage = cachedSvgImage(url: url) {
            return svgImage
        }

        guard let data = try? ImageCache.default.diskStorage.value(forKey: url.absoluteString) else {
            return nil
        }

        if let image = UIImage(data: data) {
            return .image(image: image)
        }

        return nil
    }

    static func loadSvgString(url: URL) -> String? {
        guard let data = try? Data(contentsOf: url),
              let svgString = svgString(data: data)
        else {
            return nil
        }

        try? ImageCache.default.diskStorage.store(value: data, forKey: url.absoluteString)
        return svgString
    }

    static func loadSvgImage(url: URL) -> NftImage? {
        if let cachedSvgImage = cachedSvgImage(url: url) {
            return cachedSvgImage
        }

        guard let svgString = loadSvgString(url: url) else {
            return nil
        }

        return .svg(string: svgString)
    }

    static func svgString(data: Data) -> String? {
        guard let string = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !string.isEmpty
        else {
            return nil
        }

        if looksLikeSvg(string: string) {
            return string
        }

        return decodedSvgString(dataUrl: string)
    }

    private static func looksLikeSvg(string: String) -> Bool {
        let lowercasedString = string.lowercased()
        return lowercasedString.contains("<svg") || lowercasedString.hasPrefix("<?xml")
    }

    private static func decodedSvgString(dataUrl: String) -> String? {
        let lowercasedString = dataUrl.lowercased()
        guard lowercasedString.hasPrefix("data:image/svg+xml") else {
            return nil
        }

        guard let separatorIndex = dataUrl.firstIndex(of: ",") else {
            return nil
        }

        let header = String(dataUrl[..<separatorIndex]).lowercased()
        let payloadStartIndex = dataUrl.index(after: separatorIndex)
        let payload = String(dataUrl[payloadStartIndex...])

        if header.contains(";base64") {
            guard let data = Data(base64Encoded: payload) else {
                return nil
            }

            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let decodedPayload = payload.removingPercentEncoding ?? payload
        return decodedPayload.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
