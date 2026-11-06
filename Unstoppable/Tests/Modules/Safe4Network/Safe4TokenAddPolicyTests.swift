import Testing
@testable import WalletCore

struct Safe4TokenAddPolicyTests {
    private let owner = "0x1111111111111111111111111111111111111111"
    private let otherCreator = "0x2222222222222222222222222222222222222222"

    @Test func allowsUnpromotedTokenFromAnotherCreator() {
        #expect(Safe4TokenAddPolicy.canAddUnpromotedToken(
            isPromoted: false,
            creator: otherCreator,
            ownerAddress: owner
        ))
    }

    @Test func rejectsPromotedTokensAndTokensCreatedByCurrentWallet() {
        #expect(!Safe4TokenAddPolicy.canAddUnpromotedToken(
            isPromoted: true,
            creator: otherCreator,
            ownerAddress: owner
        ))
        #expect(!Safe4TokenAddPolicy.canAddUnpromotedToken(
            isPromoted: false,
            creator: owner.uppercased(),
            ownerAddress: owner
        ))
    }

    @Test func rejectsWhenCurrentWalletAddressIsUnavailable() {
        #expect(!Safe4TokenAddPolicy.canAddUnpromotedToken(
            isPromoted: false,
            creator: otherCreator,
            ownerAddress: nil
        ))
    }
}
