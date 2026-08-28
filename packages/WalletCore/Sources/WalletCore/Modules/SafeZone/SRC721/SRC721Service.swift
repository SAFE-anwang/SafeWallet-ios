import BigInt
import EvmKit
import Foundation
import Web3Core
import web3swift

final class SRC721Service {
    private static let erc721InterfaceId = "0x80ac58cd"
    private static let receiptPollInterval: UInt64 = 1_000_000_000
    private static let receiptTimeout: TimeInterval = 180
    private static let erc165ABI = """
    [{"inputs":[{"internalType":"bytes4","name":"interfaceId","type":"bytes4"}],"name":"supportsInterface","outputs":[{"internalType":"bool","name":"","type":"bool"}],"stateMutability":"view","type":"function"}]
    """

    enum ReceiptStatus: Equatable {
        case pending
        case confirmed(success: Bool, contractAddress: String?)
    }

    let userAddress: String
    let chainId: Int
    private let privateKey: Data
    private let contractAddress: String?

    init(privateKey: Data, userAddress: String, chainId: Int, contractAddress: String? = nil) {
        self.privateKey = privateKey
        self.userAddress = userAddress
        self.chainId = chainId
        self.contractAddress = contractAddress
    }

    var canSign: Bool { !privateKey.isEmpty }

    private func ensureSigner() throws {
        guard canSign else { throw SRC721ValidationError.missingSigner }
    }

    func binding(contractAddress: String) -> SRC721Service {
        SRC721Service(privateKey: privateKey, userAddress: userAddress, chainId: chainId, contractAddress: contractAddress)
    }

    func predictedDeploymentAddress() async throws -> String {
        try ensureSigner()
        let from = try address()
        let nonce = try await web3().eth.getTransactionCount(for: from, onBlock: .pending)
        return Utilities.calculateContractAddress(sender: from, nonce: nonce)
    }

    private func web3() async throws -> Web3 {
        let context = try Safe4Network.supportedContext(chainId: chainId)
        return try await Web3.new(context.rpcUrl, network: Networks.Custom(networkID: BigUInt(context.chainId)))
    }

    private func address() throws -> Web3Core.EthereumAddress {
        guard let address = Web3Core.EthereumAddress(userAddress) else { throw SRC721ValidationError.invalidAddress("safe_zone.src721.field.wallet".localized) }
        return address
    }

    private func contractAddressValue() throws -> String {
        guard let contractAddress, Web3Core.EthereumAddress(contractAddress) != nil else { throw SRC721ValidationError.invalidAddress("safe_zone.src721.field.contract".localized) }
        return contractAddress
    }

    private func standard() async throws -> SRC721 {
        try await SRC721(web3: web3(), contractAddr: contractAddressValue())
    }

    private func burnable() async throws -> SRC721Burnable {
        try await SRC721Burnable(web3: web3(), contractAddr: contractAddressValue())
    }

    func deploy(type: SRC721ContractType, name: String, symbol: String, baseURI: String, maxSupply: BigUInt, mintPrice: BigUInt, onSubmitted: ((String) -> Void)? = nil) async throws -> (contractAddress: String, transactionHash: String) {
        try ensureSigner()
        let name = try SRC721Validation.required(name, field: "safe_zone.src721.field.name".localized, maxLength: SRC721Validation.nameMaxUTF8Length)
        let symbol = try SRC721Validation.required(symbol, field: "safe_zone.src721.field.symbol".localized, maxLength: SRC721Validation.symbolMaxUTF8Length)
        let baseURI = try SRC721Validation.optionalBaseURI(baseURI)
        guard maxSupply <= SRC721Validation.uint256Max, maxSupply > 0 else {
            throw SRC721ValidationError.invalidAmount("safe_zone.src721.field.max_supply".localized)
        }
        guard mintPrice <= SRC721Validation.uint256Max else {
            throw SRC721ValidationError.invalidAmount("safe_zone.src721.field.mint_price".localized)
        }
        let result: [String]
        switch type {
        case .standard:
            result = try await SRC721(web3: web3()).deploy(privateKey: privateKey, name: name, symbol: symbol, baseURI: baseURI, maxSupply: maxSupply, mintPrice: mintPrice)
        case .burnable:
            result = try await SRC721Burnable(web3: web3()).deploy(privateKey: privateKey, name: name, symbol: symbol, baseURI: baseURI, maxSupply: maxSupply, mintPrice: mintPrice)
        case .unknown:
            throw SRC721ValidationError.invalidAddress("safe_zone.src721.type.unknown".localized)
        }
        guard result.count >= 2,
              !result[0].isEmpty,
              !result[1].isEmpty,
              Data.fromHex(result[1])?.count == 32 else {
            throw Web3Error.processingError(desc: "Invalid SRC721 deployment response")
        }
        onSubmitted?(result[1])
        return (result[0], result[1])
    }

    func waitForTransaction(_ hash: String) async throws -> Bool {
        guard let hashData = Self.transactionHashData(hash) else {
            throw Web3Error.processingError(desc: "Invalid SRC721 transaction hash")
        }
        let deadline = Date().addingTimeInterval(Self.receiptTimeout)

        while Date() < deadline {
            switch try await receiptStatus(hashData: hashData) {
            case .confirmed(let success, _):
                return success
            case .pending:
                try await Task.sleep(nanoseconds: Self.receiptPollInterval)
            }
        }

        throw SRC721ValidationError.transactionTimeout
    }

    func deployedContractAddress(for hash: String) async throws -> String? {
        guard let hashData = Self.transactionHashData(hash) else {
            throw Web3Error.processingError(desc: "Invalid SRC721 transaction hash")
        }
        guard case let .confirmed(_, contractAddress) = try await receiptStatus(hashData: hashData) else {
            return nil
        }
        return contractAddress
    }

    private static func transactionHashData(_ hash: String) -> Data? {
        guard let data = Data.fromHex(hash), data.count == 32 else { return nil }
        return data
    }

    private func receiptStatus(hashData: Data) async throws -> ReceiptStatus {
        let web3 = try await web3()
        var request = URLRequest(url: web3.provider.url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "jsonrpc": "2.0",
            "id": 1,
            "method": "eth_getTransactionReceipt",
            "params": [hashData.toHexString().addHexPrefix()]
        ])

        let (data, response) = try await web3.provider.session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              200..<400 ~= httpResponse.statusCode else {
            throw Web3Error.nodeError(desc: "Unable to read the SRC721 transaction status")
        }

        return try Self.decodeReceiptStatus(data)
    }

    static func decodeReceiptStatus(_ data: Data) throws -> ReceiptStatus {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw Web3Error.nodeError(desc: "Unable to read the SRC721 transaction status")
        }
        if let error = root["error"] as? [String: Any], let message = error["message"] as? String {
            throw Web3Error.nodeError(desc: message)
        }

        // Safe4 returns result: null until the transaction is included in a block.
        guard let result = root["result"] else {
            throw Web3Error.nodeError(desc: "Unable to read the SRC721 transaction status")
        }
        if result is NSNull {
            return .pending
        }
        guard let receipt = result as? [String: Any] else {
            throw Web3Error.nodeError(desc: "Unable to read the SRC721 transaction status")
        }

        let success: Bool
        switch (receipt["status"] as? String)?.lowercased() {
        case "0x1", "0x01": success = true
        case "0x0", "0x00": success = false
        default:
            throw Web3Error.nodeError(desc: "Unable to read the SRC721 transaction status")
        }

        let contractAddress = (receipt["contractAddress"] as? String).flatMap { address in
            Web3Core.EthereumAddress(address)?.address
        }
        return .confirmed(success: success, contractAddress: contractAddress)
    }

    func validateContract(type: SRC721ContractType) async throws -> SRC721ContractState {
        let address = try SRC721Validation.address(contractAddressValue(), field: "safe_zone.src721.field.contract".localized)
        let web3 = try await web3()
        let code = try await web3.eth.code(for: address)
        guard !code.isEmpty, code.lowercased() != "0x" else { throw SRC721ValidationError.invalidContract }

        guard let contract = web3.contract(Self.erc165ABI, at: address),
              let operation = contract.createReadOperation("supportsInterface", parameters: [Self.erc721InterfaceId]) else {
            throw SRC721ValidationError.invalidContract
        }
        let response = try await operation.callContractMethod()
        guard response["0"] as? Bool == true else { throw SRC721ValidationError.invalidContract }

        return try await state(type: type)
    }

    func state(type: SRC721ContractType) async throws -> SRC721ContractState {
        let account = try address()
        let contractAddress = try SRC721Validation.address(contractAddressValue(), field: "safe_zone.src721.field.contract".localized)
        let web3 = try await web3()
        let safeBalance = try await web3.eth.getBalance(for: contractAddress)
        switch type {
        case .standard:
            let contract = SRC721(web3: web3, contractAddr: contractAddress.address)
            return try await readState(contract: contract, account: account, safeBalance: safeBalance)
        case .burnable:
            let contract = SRC721Burnable(web3: web3, contractAddr: contractAddress.address)
            return try await readState(contract: contract, account: account, safeBalance: safeBalance)
        case .unknown:
            throw SRC721ValidationError.invalidAddress("safe_zone.src721.type.unknown".localized)
        }
    }

    private func makeContractState(
        name: String, symbol: String, owner: Web3Core.EthereumAddress, baseURI: String, maxSupply: BigUInt,
        totalSupply: BigUInt, remainSupply: BigUInt, mintPrice: BigUInt, walletBalance: BigUInt, safeBalance: BigUInt,
        orgName: String, description: String, officialURL: String, whitePaperURL: String, logo: Data
    ) -> SRC721ContractState {
        SRC721ContractState(
            name: name, symbol: symbol, ownerAddress: owner.address, baseURI: baseURI,
            maxSupply: maxSupply, totalSupply: totalSupply, remainSupply: remainSupply,
            mintPrice: mintPrice, walletBalance: walletBalance, safeBalance: safeBalance, orgName: orgName,
            description: description, officialURL: officialURL, whitePaperURL: whitePaperURL, logo: logo
        )
    }

    private func readState(contract: SRC721, account: Web3Core.EthereumAddress, safeBalance: BigUInt) async throws -> SRC721ContractState {
        let name = try await contract.name()
        let symbol = try await contract.symbol()
        let owner = try await contract.owner()
        let baseURI = try await contract.baseURI()
        let maxSupply = try await contract.maxSupply()
        let totalSupply = try await contract.totalSupply()
        let remainSupply = try await contract.remainSupply()
        let mintPrice = try await contract.mintPrice()
        let walletBalance = try await contract.balanceOf(addr: account)
        let orgName = try await contract.orgName()
        let description = try await contract.description()
        let officialURL = try await contract.officialUrl()
        let whitePaperURL = try await contract.whitePaperUrl()
        let logo = try await contract.logo()
        return makeContractState(name: name, symbol: symbol, owner: owner, baseURI: baseURI, maxSupply: maxSupply, totalSupply: totalSupply, remainSupply: remainSupply, mintPrice: mintPrice, walletBalance: walletBalance, safeBalance: safeBalance, orgName: orgName, description: description, officialURL: officialURL, whitePaperURL: whitePaperURL, logo: logo)
    }

    private func readState(contract: SRC721Burnable, account: Web3Core.EthereumAddress, safeBalance: BigUInt) async throws -> SRC721ContractState {
        let name = try await contract.name()
        let symbol = try await contract.symbol()
        let owner = try await contract.owner()
        let baseURI = try await contract.baseURI()
        let maxSupply = try await contract.maxSupply()
        let totalSupply = try await contract.totalSupply()
        let remainSupply = try await contract.remainSupply()
        let mintPrice = try await contract.mintPrice()
        let walletBalance = try await contract.balanceOf(addr: account)
        let orgName = try await contract.orgName()
        let description = try await contract.description()
        let officialURL = try await contract.officialUrl()
        let whitePaperURL = try await contract.whitePaperUrl()
        let logo = try await contract.logo()
        return makeContractState(name: name, symbol: symbol, owner: owner, baseURI: baseURI, maxSupply: maxSupply, totalSupply: totalSupply, remainSupply: remainSupply, mintPrice: mintPrice, walletBalance: walletBalance, safeBalance: safeBalance, orgName: orgName, description: description, officialURL: officialURL, whitePaperURL: whitePaperURL, logo: logo)
    }

    func mint(type: SRC721ContractType, to: Web3Core.EthereumAddress, amount: BigUInt, mintPrice: BigUInt) async throws -> String {
        try ensureSigner()
        let value = mintPrice * amount
        switch type {
        case .standard: return try await standard().mint(privateKey: privateKey, value: value, to: to, amount: amount)
        case .burnable: return try await burnable().mint(privateKey: privateKey, value: value, to: to, amount: amount)
        case .unknown: throw SRC721ValidationError.invalidAddress("safe_zone.src721.type.unknown".localized)
        }
    }

    func adminMint(type: SRC721ContractType, to: Web3Core.EthereumAddress, amount: BigUInt) async throws -> String {
        try ensureSigner()
        switch type {
        case .standard: return try await standard().adminMint(privateKey: privateKey, to: to, amount: amount)
        case .burnable: return try await burnable().adminMint(privateKey: privateKey, to: to, amount: amount)
        case .unknown: throw SRC721ValidationError.invalidAddress("safe_zone.src721.type.unknown".localized)
        }
    }

    func setBaseURI(type: SRC721ContractType, value: String) async throws -> String {
        try ensureSigner()
        switch type {
        case .standard: return try await standard().setBaseURI(privateKey: privateKey, baseURI: value)
        case .burnable: return try await burnable().setBaseURI(privateKey: privateKey, baseURI: value)
        case .unknown: throw SRC721ValidationError.invalidAddress("safe_zone.src721.type.unknown".localized)
        }
    }

    func setMintPrice(type: SRC721ContractType, value: BigUInt) async throws -> String {
        try ensureSigner()
        switch type {
        case .standard: return try await standard().setMintPrice(privateKey: privateKey, mintPrice: value)
        case .burnable: return try await burnable().setMintPrice(privateKey: privateKey, mintPrice: value)
        case .unknown: throw SRC721ValidationError.invalidAddress("safe_zone.src721.type.unknown".localized)
        }
    }

    func setMaxSupply(type: SRC721ContractType, value: BigUInt) async throws -> String {
        try ensureSigner()
        switch type {
        case .standard: return try await standard().setMaxSupply(privateKey: privateKey, maxSupply: value)
        case .burnable: return try await burnable().setMaxSupply(privateKey: privateKey, maxSupply: value)
        case .unknown: throw SRC721ValidationError.invalidAddress("safe_zone.src721.type.unknown".localized)
        }
    }

    func updateParameters(type: SRC721ContractType, baseURI: String?, maxSupply: BigUInt?, mintPrice: BigUInt?) async throws -> [String] {
        var hashes: [String] = []
        do {
            if let baseURI {
                hashes.append(try await setBaseURI(type: type, value: baseURI))
            }
            if let maxSupply {
                hashes.append(try await setMaxSupply(type: type, value: maxSupply))
            }
            if let mintPrice {
                hashes.append(try await setMintPrice(type: type, value: mintPrice))
            }
        } catch {
            throw SRC721BatchOperationError(submittedHashes: hashes, underlying: error)
        }
        guard !hashes.isEmpty else { throw SRC721ValidationError.emptyField("safe_zone.src721.field.value".localized) }
        return hashes
    }

    func setAllowList(type: SRC721ContractType, addresses: [Web3Core.EthereumAddress], amounts: [BigUInt]) async throws -> String {
        try ensureSigner()
        switch type {
        case .standard: return try await standard().setAllowList(privateKey: privateKey, addresses: addresses, amounts: amounts)
        case .burnable: return try await burnable().setAllowList(privateKey: privateKey, addresses: addresses, amounts: amounts)
        case .unknown: throw SRC721ValidationError.invalidAddress("safe_zone.src721.type.unknown".localized)
        }
    }

    func updateMetadata(type: SRC721ContractType, orgName: String?, description: String?, officialURL: String?, whitePaperURL: String?, logo: Data?) async throws -> [String] {
        try ensureSigner()
        var hashes: [String] = []
        do {
            switch type {
            case .standard:
                let contract = try await standard()
                if let orgName { hashes.append(try await contract.setOrgName(privateKey: self.privateKey, orgName: orgName)) }
                if let description { hashes.append(try await contract.setDescription(privateKey: self.privateKey, description: description)) }
                if let officialURL { hashes.append(try await contract.setOfficialUrl(privateKey: self.privateKey, officialUrl: officialURL)) }
                if let whitePaperURL { hashes.append(try await contract.setWhitePaperUrl(privateKey: self.privateKey, whitePaperUrl: whitePaperURL)) }
                if let logo { hashes.append(try await contract.setLogo(privateKey: self.privateKey, logo: logo)) }
            case .burnable:
                let contract = try await burnable()
                if let orgName { hashes.append(try await contract.setOrgName(privateKey: self.privateKey, orgName: orgName)) }
                if let description { hashes.append(try await contract.setDescription(privateKey: self.privateKey, description: description)) }
                if let officialURL { hashes.append(try await contract.setOfficialUrl(privateKey: self.privateKey, officialUrl: officialURL)) }
                if let whitePaperURL { hashes.append(try await contract.setWhitePaperUrl(privateKey: self.privateKey, whitePaperUrl: whitePaperURL)) }
                if let logo { hashes.append(try await contract.setLogo(privateKey: self.privateKey, logo: logo)) }
            case .unknown:
                throw SRC721ValidationError.invalidAddress("safe_zone.src721.type.unknown".localized)
            }
        } catch {
            throw SRC721BatchOperationError(submittedHashes: hashes, underlying: error)
        }
        return hashes
    }

    func updateAll(
        type: SRC721ContractType,
        baseURI: String?,
        maxSupply: BigUInt?,
        mintPrice: BigUInt?,
        allowList: ([Web3Core.EthereumAddress], [BigUInt])?,
        orgName: String?,
        description: String?,
        officialURL: String?,
        whitePaperURL: String?,
        logo: Data?
    ) async throws -> [String] {
        try ensureSigner()
        var hashes: [String] = []

        do {
            if baseURI != nil || maxSupply != nil || mintPrice != nil {
                do {
                    hashes.append(contentsOf: try await updateParameters(type: type, baseURI: baseURI, maxSupply: maxSupply, mintPrice: mintPrice))
                } catch let error as SRC721BatchOperationError {
                    hashes.append(contentsOf: error.submittedHashes)
                    throw error.underlying
                }
            }
            if let allowList {
                hashes.append(try await setAllowList(type: type, addresses: allowList.0, amounts: allowList.1))
            }
            do {
                hashes.append(contentsOf: try await updateMetadata(type: type, orgName: orgName, description: description, officialURL: officialURL, whitePaperURL: whitePaperURL, logo: logo))
            } catch let error as SRC721BatchOperationError {
                hashes.append(contentsOf: error.submittedHashes)
                throw error.underlying
            }
        } catch {
            throw SRC721BatchOperationError(submittedHashes: hashes, underlying: error)
        }

        guard !hashes.isEmpty else {
            throw SRC721ValidationError.emptyField("safe_zone.src721.field.value".localized)
        }
        return hashes
    }

    func withdraw(type: SRC721ContractType) async throws -> String {
        try ensureSigner()
        switch type {
        case .standard: return try await standard().withdraw(privateKey: privateKey)
        case .burnable: return try await burnable().withdraw(privateKey: privateKey)
        case .unknown: throw SRC721ValidationError.invalidAddress("safe_zone.src721.type.unknown".localized)
        }
    }

    func tokenState(type: SRC721ContractType, tokenId: BigUInt) async throws -> SRC721TokenState {
        switch type {
        case .standard:
            let contract = try await standard()
            let owner = try await contract.ownerOf(tokenId: tokenId)
            let approved = try await contract.getApproved(tokenId: tokenId)
            let uri = try await contract.tokenURI(tokenId: tokenId)
            return .init(tokenId: tokenId, ownerAddress: owner.address, approvedAddress: approved.address, tokenURI: uri)
        case .burnable:
            let contract = try await burnable()
            let owner = try await contract.ownerOf(tokenId: tokenId)
            let approved = try await contract.getApproved(tokenId: tokenId)
            let uri = try await contract.tokenURI(tokenId: tokenId)
            return .init(tokenId: tokenId, ownerAddress: owner.address, approvedAddress: approved.address, tokenURI: uri)
        case .unknown:
            throw SRC721ValidationError.invalidAddress("safe_zone.src721.type.unknown".localized)
        }
    }

    func approve(type: SRC721ContractType, to: Web3Core.EthereumAddress, tokenId: BigUInt) async throws -> String {
        try ensureSigner()
        switch type {
        case .standard: return try await standard().approve(privateKey: privateKey, to: to, tokenId: tokenId)
        case .burnable: return try await burnable().approve(privateKey: privateKey, to: to, tokenId: tokenId)
        case .unknown: throw SRC721ValidationError.invalidAddress("safe_zone.src721.type.unknown".localized)
        }
    }

    func transfer(type: SRC721ContractType, from: Web3Core.EthereumAddress, to: Web3Core.EthereumAddress, tokenId: BigUInt) async throws -> String {
        try ensureSigner()
        switch type {
        case .standard: return try await standard().safeTransferFrom(privateKey: privateKey, from: from, to: to, tokenId: tokenId)
        case .burnable: return try await burnable().safeTransferFrom(privateKey: privateKey, from: from, to: to, tokenId: tokenId)
        case .unknown: throw SRC721ValidationError.invalidAddress("safe_zone.src721.type.unknown".localized)
        }
    }

    func burn(type: SRC721ContractType, tokenId: BigUInt) async throws -> String {
        try ensureSigner()
        guard type == .burnable else { throw SRC721ValidationError.invalidAddress("safe_zone.src721.type.burnable".localized) }
        return try await burnable().burn(privateKey: privateKey, tokenId: tokenId)
    }
}
