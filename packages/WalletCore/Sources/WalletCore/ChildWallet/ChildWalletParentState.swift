import Foundation

struct ChildWalletParentState: Codable, Equatable, Sendable {
    let parentAccountId: String
    var highestAllocatedIndex: Int
    var legacyHighestDetectedIndex: Int
    var legacyAutoSeededEnabledWalletsCleaned: Bool
    var createdAt: TimeInterval
    var updatedAt: TimeInterval

    var highestKnownIndex: Int {
        max(highestAllocatedIndex, legacyHighestDetectedIndex)
    }

    private enum CodingKeys: String, CodingKey {
        case parentAccountId
        case highestAllocatedIndex
        case legacyHighestDetectedIndex = "highestDetectedIndex"
        case legacyAutoSeededEnabledWalletsCleaned
        case createdAt
        case updatedAt
    }

    init(
        parentAccountId: String,
        highestAllocatedIndex: Int,
        legacyHighestDetectedIndex: Int,
        legacyAutoSeededEnabledWalletsCleaned: Bool = false,
        createdAt: TimeInterval,
        updatedAt: TimeInterval
    ) {
        self.parentAccountId = parentAccountId
        self.highestAllocatedIndex = highestAllocatedIndex
        self.legacyHighestDetectedIndex = legacyHighestDetectedIndex
        self.legacyAutoSeededEnabledWalletsCleaned = legacyAutoSeededEnabledWalletsCleaned
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        parentAccountId = try container.decode(String.self, forKey: .parentAccountId)
        highestAllocatedIndex = try container.decode(Int.self, forKey: .highestAllocatedIndex)
        legacyHighestDetectedIndex = try container.decode(Int.self, forKey: .legacyHighestDetectedIndex)
        legacyAutoSeededEnabledWalletsCleaned = try container.decodeIfPresent(Bool.self, forKey: .legacyAutoSeededEnabledWalletsCleaned) ?? false
        createdAt = try container.decode(TimeInterval.self, forKey: .createdAt)
        updatedAt = try container.decode(TimeInterval.self, forKey: .updatedAt)
    }

    static func fresh(parentAccountId: String) -> ChildWalletParentState {
        let now = Date().timeIntervalSince1970

        return ChildWalletParentState(
            parentAccountId: parentAccountId,
            highestAllocatedIndex: 0,
            legacyHighestDetectedIndex: 0,
            legacyAutoSeededEnabledWalletsCleaned: false,
            createdAt: now,
            updatedAt: now
        )
    }

    mutating func recordAllocated(index: Int) {
        highestAllocatedIndex = max(highestAllocatedIndex, index)
        updatedAt = Date().timeIntervalSince1970
    }

    mutating func recordLegacyAutoSeededEnabledWalletsCleaned() {
        legacyAutoSeededEnabledWalletsCleaned = true
        updatedAt = Date().timeIntervalSince1970
    }
}
