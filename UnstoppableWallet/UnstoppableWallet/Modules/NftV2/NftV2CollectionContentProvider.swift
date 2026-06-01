import Foundation

enum NftV2CollectionContentProvider {
    static func collectionDescription(collectionName: String) -> String? {
        let normalized = collectionName.lowercased()

        if normalized.contains("pancake bunnies") {
            return "nft_v2.collection.description.pancake_bunnies".localized
        }

        return nil
    }
}
