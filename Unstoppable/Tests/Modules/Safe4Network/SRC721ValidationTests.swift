import BigInt
import XCTest
@testable import WalletCore

final class SRC721ValidationTests: XCTestCase {
    func testReceiptStatusTreatsNullResultAsPending() throws {
        let data = Data(#"{"jsonrpc":"2.0","id":1,"result":null}"#.utf8)

        XCTAssertEqual(try SRC721Service.decodeReceiptStatus(data), .pending)
    }

    func testReceiptStatusRejectsResponseWithoutResult() {
        let data = Data(#"{"jsonrpc":"2.0","id":1}"#.utf8)

        XCTAssertThrowsError(try SRC721Service.decodeReceiptStatus(data))
    }

    func testReceiptStatusParsesSuccessfulDeployment() throws {
        let address = "0x0000000000000000000000000000000000000010"
        let data = Data((#"{"jsonrpc":"2.0","id":1,"result":{"status":"0x1","contractAddress":""# + address + #""}}"#).utf8)

        XCTAssertEqual(
            try SRC721Service.decodeReceiptStatus(data),
            .confirmed(success: true, contractAddress: address)
        )
    }

    func testReceiptStatusParsesFailedTransaction() throws {
        let data = Data(#"{"jsonrpc":"2.0","id":1,"result":{"status":"0x0","contractAddress":null}}"#.utf8)

        XCTAssertEqual(
            try SRC721Service.decodeReceiptStatus(data),
            .confirmed(success: false, contractAddress: nil)
        )
    }

    func testReceiptStatusSurfacesNodeError() {
        let data = Data(#"{"jsonrpc":"2.0","id":1,"error":{"code":-32000,"message":"transaction not found"}}"#.utf8)

        XCTAssertThrowsError(try SRC721Service.decodeReceiptStatus(data)) { error in
            XCTAssertEqual(error.localizedDescription, "transaction not found")
        }
    }

    func testAmountKeepsLargeIntegerPrecision() throws {
        let amount = try SRC721Validation.amount("100000000000000000000000000000000000", field: "amount")
        let expected = BigUInt("100000000000000000000000000000000000")
        XCTAssertEqual(amount, expected)
    }

    func testAmountRejectsZeroUnlessExplicitlyAllowed() {
        XCTAssertThrowsError(try SRC721Validation.amount("0", field: "amount"))
        do {
            XCTAssertEqual(try SRC721Validation.amount("0", field: "amount", allowZero: true), BigUInt.zero)
        } catch {
            XCTFail("Zero should be accepted when explicitly allowed")
        }
    }

    func testAmountRejectsNonDecimalAndUint256Overflow() {
        XCTAssertThrowsError(try SRC721Validation.amount("1e3", field: "amount"))
        XCTAssertThrowsError(try SRC721Validation.amount("01", field: "amount"))
        XCTAssertThrowsError(try SRC721Validation.amount(((BigUInt(1) << 256)).description, field: "amount"))
        XCTAssertNoThrow(try SRC721Validation.amount(SRC721Validation.uint256Max.description, field: "amount"))
    }

    func testRequiredUsesUTF8ByteLength() {
        XCTAssertNoThrow(try SRC721Validation.required(String(repeating: "中", count: 21), field: "name", maxLength: 64))
        XCTAssertThrowsError(try SRC721Validation.required(String(repeating: "中", count: 22), field: "name", maxLength: 64))
    }

    func testRequiredAndAmountExposeDifferentInputErrors() {
        XCTAssertThrowsError(try SRC721Validation.required("", field: "name", maxLength: 64)) { error in
            guard case SRC721ValidationError.emptyField("name") = error else {
                return XCTFail("An empty text field should use the required-field error")
            }
        }
        XCTAssertThrowsError(try SRC721Validation.required(String(repeating: "a", count: 65), field: "name", maxLength: 64)) { error in
            guard case SRC721ValidationError.textTooLong("name") = error else {
                return XCTFail("An oversized text field should use the length error")
            }
        }
        XCTAssertThrowsError(try SRC721Validation.amount("", field: "amount")) { error in
            guard case SRC721ValidationError.emptyField("amount") = error else {
                return XCTFail("An empty amount should use the required-field error")
            }
        }
    }

    func testInputTransformsRespectFieldRules() {
        XCTAssertEqual(SRC721Validation.decimalInput("1a2.3", maxDigits: 3), "123")
        XCTAssertEqual(SRC721Validation.textInput(String(repeating: "中", count: 30), maxUTF8Length: 16).utf8.count, 15)
        XCTAssertEqual(SRC721Validation.validDecimalInput("00012"), "12")
        XCTAssertEqual(SRC721Validation.validDecimalInput("000"), "0")
        XCTAssertEqual(SRC721Validation.validDecimalInput(""), "")
        XCTAssertNil(SRC721Validation.validDecimalInput((SRC721Validation.uint256Max + 1).description))
        XCTAssertNil(SRC721Validation.validDecimalInput("1" + String(repeating: "0", count: 78)))
        XCTAssertEqual(SRC721Validation.validDecimalInput(SRC721Validation.uint256Max.description), SRC721Validation.uint256Max.description)
        XCTAssertEqual(
            SRC721Validation.allowListAddressesInput("0x0000000000000000000000000000000000000001, 中文"),
            "0x0000000000000000000000000000000000000001, "
        )
        XCTAssertEqual(SRC721Validation.allowListAmountsInput("00012, 003"), "12, 3")
    }

    func testAddressRejectsZeroAddress() {
        XCTAssertThrowsError(try SRC721Validation.address(SRC721Validation.zeroAddress, field: "address"))
        XCTAssertNoThrow(try SRC721Validation.address("0x0000000000000000000000000000000000000001", field: "address"))
    }

    func testBaseURIAllowsHTTPSAndIPFSButRejectsOtherSchemes() {
        XCTAssertNoThrow(try SRC721Validation.baseURI("https://example.com/nft/"))
        XCTAssertNoThrow(try SRC721Validation.baseURI("ipfs://bafybeigdyrzt/"))
        XCTAssertThrowsError(try SRC721Validation.baseURI("http://example.com/nft/"))
        XCTAssertThrowsError(try SRC721Validation.baseURI("ftp://example.com/nft/"))
    }

    func testAllowListRequiresParallelEntries() throws {
        let list = try SRC721Validation.allowList(
            addresses: "0x0000000000000000000000000000000000000001,\n0x0000000000000000000000000000000000000002",
            amounts: "2 3"
        )
        XCTAssertEqual(list.0.count, 2)
        XCTAssertEqual(list.1, [BigUInt(2), BigUInt(3)])
        XCTAssertThrowsError(try SRC721Validation.allowList(
            addresses: "0x0000000000000000000000000000000000000001",
            amounts: "1 2"
        ))
    }

    func testOwnedTokenPagingRejectsAnEmptyNonTerminalPage() {
        XCTAssertThrowsError(
            try SRC721OwnedTokenPaging.nextOffset(offset: 0, total: 2, returnedCount: 0, limit: 20)
        )
    }

    func testOwnedTokenPagingAdvancesByActualReturnedCountOnLastPage() throws {
        XCTAssertEqual(
            try SRC721OwnedTokenPaging.nextOffset(offset: 20, total: 23, returnedCount: 3, limit: 20),
            23
        )
        XCTAssertEqual(
            try SRC721OwnedTokenPaging.nextOffset(offset: 23, total: 23, returnedCount: 0, limit: 20),
            23
        )
    }

    func testOwnedTokenPagingRejectsProviderOverrun() {
        XCTAssertThrowsError(
            try SRC721OwnedTokenPaging.nextOffset(offset: 20, total: 21, returnedCount: 2, limit: 20)
        )
    }

    func testWalletCollectionsGroupAssetsByContractAndSortTokens() {
        let contractA = testContract(name: "Alpha", address: "0x0000000000000000000000000000000000000010")
        let contractB = testContract(name: "Beta", address: "0x0000000000000000000000000000000000000020")
        let owner = "0x0000000000000000000000000000000000000001"
        let assets = [
            SRC721WalletAsset(contract: contractB, token: SRC721OwnedToken(tokenId: 5, ownerAddress: owner, tokenURI: nil, source: .onChain)),
            SRC721WalletAsset(contract: contractA, token: SRC721OwnedToken(tokenId: 2, ownerAddress: owner, tokenURI: nil, source: .onChain)),
            SRC721WalletAsset(contract: contractB, token: SRC721OwnedToken(tokenId: 1, ownerAddress: owner, tokenURI: nil, source: .onChain))
        ]

        let collections = SRC721WalletCollection.grouped(assets: assets)

        XCTAssertEqual(collections.map(\.displayName), ["Alpha", "Beta"])
        XCTAssertEqual(collections[1].assets.map(\.token.tokenId), [BigUInt(1), BigUInt(5)])
    }

    func testPublicMintValidationChecksEligibilityAllowanceAndSupply() throws {
        var state = testContractState(canPublicMint: true, allowance: 3, remainSupply: 5)
        XCTAssertEqual(state.publicMintAvailableAmount, 3)
        XCTAssertNoThrow(try SRC721Validation.validatePublicMint(state: state, amount: 3))

        state = testContractState(canPublicMint: false, allowance: 3, remainSupply: 5)
        XCTAssertEqual(state.publicMintAvailableAmount, 0)
        XCTAssertThrowsError(try SRC721Validation.validatePublicMint(state: state, amount: 1)) { error in
            guard case SRC721ValidationError.publicMintUnavailable = error else {
                return XCTFail("Expected public mint eligibility error")
            }
        }

        state = testContractState(canPublicMint: true, allowance: 2, remainSupply: 5)
        XCTAssertThrowsError(try SRC721Validation.validatePublicMint(state: state, amount: 3)) { error in
            guard case SRC721ValidationError.publicMintAllowanceInsufficient = error else {
                return XCTFail("Expected public mint allowance error")
            }
        }

        state = testContractState(canPublicMint: true, allowance: 5, remainSupply: 2)
        XCTAssertEqual(state.publicMintAvailableAmount, 2)
        XCTAssertThrowsError(try SRC721Validation.validatePublicMint(state: state, amount: 3)) { error in
            guard case SRC721ValidationError.supplyInsufficient = error else {
                return XCTFail("Expected remaining supply error")
            }
        }
    }

    func testAllowListEntryStorageUpsertsAndFiltersByContract() {
        guard let defaults = UserDefaults(suiteName: "SRC721ValidationTests.allowList") else {
            return XCTFail("Unable to create isolated defaults")
        }
        defaults.removePersistentDomain(forName: "SRC721ValidationTests.allowList")
        let storage = SRC721Storage(defaults: defaults)
        let contract = testContract(name: "Collection", address: "0x0000000000000000000000000000000000000010")
        let entry = SRC721AllowListEntry(
            accountId: contract.accountId, chainId: contract.chainId, walletAddress: contract.walletAddress,
            contractAddress: contract.contractAddress, address: "0x0000000000000000000000000000000000000002",
            amount: "1", transactionHash: "0x01", updatedAt: Date(timeIntervalSince1970: 1)
        )
        storage.save(allowListEntry: entry)
        storage.save(allowListEntry: SRC721AllowListEntry(
            accountId: contract.accountId, chainId: contract.chainId, walletAddress: contract.walletAddress,
            contractAddress: contract.contractAddress, address: entry.address.uppercased(),
            amount: "2", transactionHash: "0x02", updatedAt: Date(timeIntervalSince1970: 2)
        ))

        XCTAssertEqual(storage.allowListEntries(for: contract).map(\.amount), ["2"])
        XCTAssertTrue(storage.allowListEntries(for: testContract(name: "Other", address: "0x0000000000000000000000000000000000000020")).isEmpty)

        let otherAccountContract = testContract(
            name: "Collection",
            address: contract.contractAddress,
            accountId: "account-b",
            walletAddress: "0x0000000000000000000000000000000000000003"
        )
        storage.save(allowListEntry: SRC721AllowListEntry(
            accountId: otherAccountContract.accountId, chainId: otherAccountContract.chainId,
            walletAddress: otherAccountContract.walletAddress, contractAddress: otherAccountContract.contractAddress,
            address: entry.address, amount: "3", transactionHash: "0x03", updatedAt: Date(timeIntervalSince1970: 3)
        ))

        XCTAssertEqual(storage.allowListEntries(for: contract).map(\.amount), ["2"])
        XCTAssertEqual(storage.allowListEntries(for: otherAccountContract).map(\.amount), ["3"])
    }

    func testStorageFiltersByAccountChainAndWallet() throws {
        guard let defaults = UserDefaults(suiteName: "SRC721ValidationTests") else {
            XCTFail("Unable to create isolated defaults")
            return
        }
        defaults.removePersistentDomain(forName: "SRC721ValidationTests")
        let storage = SRC721Storage(defaults: defaults)
        let record = SRC721ContractRecord(
            accountId: "account-a", chainId: 100, walletAddress: "0x0000000000000000000000000000000000000001",
            contractAddress: "0x0000000000000000000000000000000000000010", predictedContractAddress: nil,
            creatorAddress: "0x0000000000000000000000000000000000000001", currentOwnerAddress: nil,
            contractType: .standard, name: "Collection", symbol: "COL", baseURI: "https://example.com/",
            maxSupply: "10", mintPrice: "0", deployTransactionHash: nil, transactionStatus: .confirmed,
            validationStatus: "manual", createdAt: Date()
        )
        storage.save(contract: record)
        XCTAssertEqual(storage.contracts(accountId: "account-a", chainId: 100, walletAddress: record.walletAddress).count, 1)
        XCTAssertTrue(storage.contracts(accountId: "account-b", chainId: 100, walletAddress: record.walletAddress).isEmpty)
        XCTAssertTrue(storage.contracts(accountId: "account-a", chainId: 101, walletAddress: record.walletAddress).isEmpty)
        XCTAssertTrue(storage.contracts(accountId: "account-a", chainId: 100, walletAddress: "0x0000000000000000000000000000000000000002").isEmpty)

        var receiptResolvedRecord = record
        receiptResolvedRecord.contractAddress = "0x0000000000000000000000000000000000000020"
        receiptResolvedRecord.deployTransactionHash = "0xdeploy"
        storage.save(contract: receiptResolvedRecord)
        XCTAssertEqual(storage.contracts(accountId: "account-a", chainId: 100, walletAddress: record.walletAddress).count, 2)

        var replacedReceiptResolvedRecord = receiptResolvedRecord
        replacedReceiptResolvedRecord.contractAddress = "0x0000000000000000000000000000000000000030"
        storage.save(contract: replacedReceiptResolvedRecord)
        let records = storage.contracts(accountId: "account-a", chainId: 100, walletAddress: record.walletAddress)
        XCTAssertEqual(records.count, 2)
        XCTAssertTrue(records.contains { $0.contractAddress == replacedReceiptResolvedRecord.contractAddress })
    }

    func testStorageFiltersPendingTransactionsByAccountChainAndWallet() {
        guard let defaults = UserDefaults(suiteName: "SRC721ValidationTests.transactions") else {
            XCTFail("Unable to create isolated defaults")
            return
        }
        defaults.removePersistentDomain(forName: "SRC721ValidationTests.transactions")
        let storage = SRC721Storage(defaults: defaults)
        let transaction = SRC721TransactionRecord(
            id: UUID(), accountId: "account-a", chainId: 100,
            walletAddress: "0x0000000000000000000000000000000000000001",
            contractAddress: "0x0000000000000000000000000000000000000010",
            operation: "SRC721", tokenId: nil, transactionHash: "0x01", status: .pending,
            errorMessage: nil, createdAt: Date()
        )
        storage.save(transaction: transaction)

        XCTAssertEqual(storage.transactions(accountId: "account-a", chainId: 100, walletAddress: transaction.walletAddress), [transaction])
        XCTAssertTrue(storage.transactions(accountId: "account-b", chainId: 100, walletAddress: transaction.walletAddress).isEmpty)
        XCTAssertTrue(storage.transactions(accountId: "account-a", chainId: 101, walletAddress: transaction.walletAddress).isEmpty)
    }

    private func testContract(
        name: String,
        address: String,
        accountId: String = "account-a",
        walletAddress: String = "0x0000000000000000000000000000000000000001"
    ) -> SRC721ContractRecord {
        SRC721ContractRecord(
            accountId: accountId, chainId: 100, walletAddress: walletAddress,
            contractAddress: address, predictedContractAddress: nil,
            creatorAddress: "0x0000000000000000000000000000000000000001", currentOwnerAddress: nil,
            contractType: .standard, name: name, symbol: "NFT", baseURI: "https://example.com/",
            maxSupply: "10", mintPrice: "0", deployTransactionHash: nil, transactionStatus: .confirmed,
            validationStatus: "manual", createdAt: Date()
        )
    }

    private func testContractState(canPublicMint: Bool, allowance: BigUInt, remainSupply: BigUInt) -> SRC721ContractState {
        SRC721ContractState(
            name: "Collection", symbol: "NFT", ownerAddress: "0x0000000000000000000000000000000000000001",
            baseURI: "https://example.com/", maxSupply: 10, totalSupply: 5, remainSupply: remainSupply,
            mintPrice: 0, walletBalance: 0, publicMintAllowance: allowance, canPublicMint: canPublicMint,
            safeBalance: 0, orgName: "", description: "", officialURL: "", whitePaperURL: "", logo: Data()
        )
    }
}
