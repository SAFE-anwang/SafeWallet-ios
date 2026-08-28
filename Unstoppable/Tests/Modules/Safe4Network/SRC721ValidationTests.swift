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
}
