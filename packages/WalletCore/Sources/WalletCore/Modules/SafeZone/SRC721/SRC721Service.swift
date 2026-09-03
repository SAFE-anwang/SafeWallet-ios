import BigInt
import EvmKit
import Foundation
import Web3Core
import web3swift

final class SRC721Service: SRC721OwnedAssetProvider {
    private static let erc721InterfaceId = "0x80ac58cd"
    private static let erc721EnumerableInterfaceId = "0x780e9d63"
    private static let receiptPollInterval: UInt64 = 1_000_000_000
    private static let receiptTimeout: TimeInterval = 180
    private static let erc165ABI = """
    [{"inputs":[{"internalType":"bytes4","name":"interfaceId","type":"bytes4"}],"name":"supportsInterface","outputs":[{"internalType":"bool","name":"","type":"bool"}],"stateMutability":"view","type":"function"}]
    """
    private static let approvalABI = """
    [{"inputs":[{"internalType":"address","name":"operator","type":"address"},{"internalType":"bool","name":"approved","type":"bool"}],"name":"setApprovalForAll","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"address","name":"owner","type":"address"},{"internalType":"address","name":"operator","type":"address"}],"name":"isApprovedForAll","outputs":[{"internalType":"bool","name":"","type":"bool"}],"stateMutability":"view","type":"function"}]
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
        guard let address = Web3Core.EthereumAddress(userAddress),
              address.address.lowercased() != SRC721Validation.zeroAddress else {
            throw SRC721ValidationError.invalidAddress("safe_zone.src721.field.wallet".localized)
        }
        return address
    }

    private func contractAddressValue() throws -> String {
        guard let contractAddress,
              let address = Web3Core.EthereumAddress(contractAddress),
              address.address.lowercased() != SRC721Validation.zeroAddress else {
            throw SRC721ValidationError.invalidAddress("safe_zone.src721.field.contract".localized)
        }
        return address.address
    }

    private func validatedContractAddress() throws -> Web3Core.EthereumAddress {
        guard let value = contractAddress,
              let address = Web3Core.EthereumAddress(value),
              address.address.lowercased() != SRC721Validation.zeroAddress else {
            throw SRC721ValidationError.invalidAddress("safe_zone.src721.field.contract".localized)
        }
        return address
    }

    private func standard() async throws -> SRC721 {
        try await SRC721(web3: web3(), contractAddr: contractAddressValue())
    }

    private func burnable() async throws -> SRC721Burnable {
        try await SRC721Burnable(web3: web3(), contractAddr: contractAddressValue())
    }

    private func contractOwner(type: SRC721ContractType) async throws -> Web3Core.EthereumAddress {
        switch type {
        case .standard: return try await standard().owner()
        case .burnable: return try await burnable().owner()
        case .unknown: throw SRC721ValidationError.invalidAddress("safe_zone.src721.type.unknown".localized)
        }
    }

    private func ensureContractOwner(type: SRC721ContractType) async throws {
        try ensureSigner()
        let owner = try await contractOwner(type: type)
        guard owner.address.lowercased() == userAddress.lowercased() else {
            throw SRC721ValidationError.ownerRequired
        }
    }

    private func validateAmount(_ amount: BigUInt, field: String, allowZero: Bool = false) throws {
        guard amount <= SRC721Validation.uint256Max, allowZero || amount > 0 else {
            throw SRC721ValidationError.invalidAmount(field)
        }
    }

    private func validateAddress(_ value: Web3Core.EthereumAddress, field: String, allowZero: Bool = false) throws -> Web3Core.EthereumAddress {
        guard allowZero || value.address.lowercased() != SRC721Validation.zeroAddress else {
            throw SRC721ValidationError.invalidAddress(field)
        }
        return value
    }

    private func validateTokenId(_ tokenId: BigUInt) throws {
        try validateAmount(tokenId, field: "safe_zone.src721.field.token_id".localized, allowZero: true)
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

        guard try await supportsInterface(web3: web3, address: address, interfaceId: Self.erc721InterfaceId) else {
            throw SRC721ValidationError.invalidContract
        }

        return try await state(type: type)
    }

    private func supportsInterface(web3: Web3, address: Web3Core.EthereumAddress, interfaceId: String) async throws -> Bool {
        guard let contract = web3.contract(Self.erc165ABI, at: address),
              let operation = contract.createReadOperation("supportsInterface", parameters: [interfaceId]) else {
            throw SRC721ValidationError.invalidContract
        }
        let response = try await operation.callContractMethod()
        guard let result = response["0"] as? Bool else { throw SRC721ValidationError.invalidContract }
        return result
    }

    func ownedTokenPage(type: SRC721ContractType, offset: Int, limit: Int) async throws -> SRC721OwnedTokenPage {
        guard offset >= 0, (1...50).contains(limit), offset <= Int.max - limit else {
            throw SRC721ValidationError.enumerationUnavailable
        }

        let owner = try address()
        let web3 = try await web3()
        let contractAddress = try validatedContractAddress()
        guard try await supportsInterface(web3: web3, address: contractAddress, interfaceId: Self.erc721EnumerableInterfaceId) else {
            throw SRC721ValidationError.enumerationUnavailable
        }

        let total: BigUInt
        let tokens: [SRC721OwnedToken]
        switch type {
        case .standard:
            let contract = SRC721(web3: web3, contractAddr: contractAddress.address)
            total = try await contract.balanceOf(addr: owner)
            tokens = try await ownedTokens(contract: contract, owner: owner, total: total, offset: offset, limit: limit)
        case .burnable:
            let contract = SRC721Burnable(web3: web3, contractAddr: contractAddress.address)
            total = try await contract.balanceOf(addr: owner)
            tokens = try await ownedTokens(contract: contract, owner: owner, total: total, offset: offset, limit: limit)
        case .unknown:
            throw SRC721ValidationError.invalidAddress("safe_zone.src721.type.unknown".localized)
        }
        return SRC721OwnedTokenPage(total: total, tokens: tokens, supportsEnumeration: true)
    }

    private func ownedTokens(contract: SRC721, owner: Web3Core.EthereumAddress, total: BigUInt, offset: Int, limit: Int) async throws -> [SRC721OwnedToken] {
        try await ownedTokens(
            owner: owner,
            total: total,
            offset: offset,
            limit: limit,
            tokenAt: { index in try await contract.tokenOfOwnerByIndex(owner: owner, index: index) },
            uriFor: { tokenId in try await contract.tokenURI(tokenId: tokenId) }
        )
    }

    private func ownedTokens(contract: SRC721Burnable, owner: Web3Core.EthereumAddress, total: BigUInt, offset: Int, limit: Int) async throws -> [SRC721OwnedToken] {
        try await ownedTokens(
            owner: owner,
            total: total,
            offset: offset,
            limit: limit,
            tokenAt: { index in try await contract.tokenOfOwnerByIndex(owner: owner, index: index) },
            uriFor: { tokenId in try await contract.tokenURI(tokenId: tokenId) }
        )
    }

    private func ownedTokens(
        owner: Web3Core.EthereumAddress,
        total: BigUInt,
        offset: Int,
        limit: Int,
        tokenAt: (BigUInt) async throws -> BigUInt,
        uriFor: (BigUInt) async throws -> String
    ) async throws -> [SRC721OwnedToken] {
        var tokens: [SRC721OwnedToken] = []
        for pageIndex in 0..<limit {
            let index = BigUInt(offset + pageIndex)
            guard index < total else { break }
            let tokenId = try await tokenAt(index)
            let tokenURI = try? await uriFor(tokenId)
            tokens.append(SRC721OwnedToken(tokenId: tokenId, ownerAddress: owner.address, tokenURI: tokenURI, source: .onChain))
        }
        return tokens
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
        totalSupply: BigUInt, remainSupply: BigUInt, mintPrice: BigUInt, walletBalance: BigUInt,
        publicMintAllowance: BigUInt, canPublicMint: Bool, safeBalance: BigUInt,
        orgName: String, description: String, officialURL: String, whitePaperURL: String, logo: Data
    ) -> SRC721ContractState {
        SRC721ContractState(
            name: name, symbol: symbol, ownerAddress: owner.address, baseURI: baseURI,
            maxSupply: maxSupply, totalSupply: totalSupply, remainSupply: remainSupply,
            mintPrice: mintPrice, walletBalance: walletBalance, publicMintAllowance: publicMintAllowance,
            canPublicMint: canPublicMint, safeBalance: safeBalance, orgName: orgName,
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
        let publicMintAllowance = (try? await contract.amountAllowToMint(addr: account)) ?? 0
        let canPublicMint = (try? await contract.canMint(addr: account)) ?? false
        let orgName = try await contract.orgName()
        let description = try await contract.description()
        let officialURL = try await contract.officialUrl()
        let whitePaperURL = try await contract.whitePaperUrl()
        let logo = try await contract.logo()
        return makeContractState(name: name, symbol: symbol, owner: owner, baseURI: baseURI, maxSupply: maxSupply, totalSupply: totalSupply, remainSupply: remainSupply, mintPrice: mintPrice, walletBalance: walletBalance, publicMintAllowance: publicMintAllowance, canPublicMint: canPublicMint, safeBalance: safeBalance, orgName: orgName, description: description, officialURL: officialURL, whitePaperURL: whitePaperURL, logo: logo)
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
        let publicMintAllowance = (try? await contract.amountAllowToMint(addr: account)) ?? 0
        let canPublicMint = (try? await contract.canMint(addr: account)) ?? false
        let orgName = try await contract.orgName()
        let description = try await contract.description()
        let officialURL = try await contract.officialUrl()
        let whitePaperURL = try await contract.whitePaperUrl()
        let logo = try await contract.logo()
        return makeContractState(name: name, symbol: symbol, owner: owner, baseURI: baseURI, maxSupply: maxSupply, totalSupply: totalSupply, remainSupply: remainSupply, mintPrice: mintPrice, walletBalance: walletBalance, publicMintAllowance: publicMintAllowance, canPublicMint: canPublicMint, safeBalance: safeBalance, orgName: orgName, description: description, officialURL: officialURL, whitePaperURL: whitePaperURL, logo: logo)
    }

    private func publicMintPrice(type: SRC721ContractType, amount: BigUInt) async throws -> BigUInt {
        try validateAmount(amount, field: "safe_zone.src721.field.amount".localized)
        let account = try address()
        switch type {
        case .standard:
            let contract = try await standard()
            guard try await contract.canMint(addr: account) else { throw SRC721ValidationError.publicMintUnavailable }
            guard try await contract.amountAllowToMint(addr: account) >= amount else { throw SRC721ValidationError.publicMintAllowanceInsufficient }
            guard try await contract.remainSupply() >= amount else { throw SRC721ValidationError.supplyInsufficient }
            return try await contract.mintPrice()
        case .burnable:
            let contract = try await burnable()
            guard try await contract.canMint(addr: account) else { throw SRC721ValidationError.publicMintUnavailable }
            guard try await contract.amountAllowToMint(addr: account) >= amount else { throw SRC721ValidationError.publicMintAllowanceInsufficient }
            guard try await contract.remainSupply() >= amount else { throw SRC721ValidationError.supplyInsufficient }
            return try await contract.mintPrice()
        case .unknown:
            throw SRC721ValidationError.invalidAddress("safe_zone.src721.type.unknown".localized)
        }
    }

    func mint(type: SRC721ContractType, to: Web3Core.EthereumAddress, amount: BigUInt) async throws -> String {
        try ensureSigner()
        let to = try validateAddress(to, field: "safe_zone.src721.field.recipient".localized)
        let mintPrice = try await publicMintPrice(type: type, amount: amount)
        guard mintPrice == 0 || amount <= SRC721Validation.uint256Max / mintPrice else {
            throw SRC721ValidationError.invalidAmount("safe_zone.src721.field.amount".localized)
        }
        let value = mintPrice * amount
        switch type {
        case .standard: return try await standard().mint(privateKey: privateKey, value: value, to: to, amount: amount)
        case .burnable: return try await burnable().mint(privateKey: privateKey, value: value, to: to, amount: amount)
        case .unknown: throw SRC721ValidationError.invalidAddress("safe_zone.src721.type.unknown".localized)
        }
    }

    func adminMint(type: SRC721ContractType, to: Web3Core.EthereumAddress, amount: BigUInt) async throws -> String {
        try await ensureContractOwner(type: type)
        let to = try validateAddress(to, field: "safe_zone.src721.field.recipient".localized)
        try validateAmount(amount, field: "safe_zone.src721.field.amount".localized)
        switch type {
        case .standard: return try await standard().adminMint(privateKey: privateKey, to: to, amount: amount)
        case .burnable: return try await burnable().adminMint(privateKey: privateKey, to: to, amount: amount)
        case .unknown: throw SRC721ValidationError.invalidAddress("safe_zone.src721.type.unknown".localized)
        }
    }

    func setBaseURI(type: SRC721ContractType, value: String) async throws -> String {
        try await ensureContractOwner(type: type)
        let value = try SRC721Validation.optionalBaseURI(value)
        switch type {
        case .standard: return try await standard().setBaseURI(privateKey: privateKey, baseURI: value)
        case .burnable: return try await burnable().setBaseURI(privateKey: privateKey, baseURI: value)
        case .unknown: throw SRC721ValidationError.invalidAddress("safe_zone.src721.type.unknown".localized)
        }
    }

    func setMintPrice(type: SRC721ContractType, value: BigUInt) async throws -> String {
        try await ensureContractOwner(type: type)
        try validateAmount(value, field: "safe_zone.src721.field.mint_price".localized, allowZero: true)
        switch type {
        case .standard: return try await standard().setMintPrice(privateKey: privateKey, mintPrice: value)
        case .burnable: return try await burnable().setMintPrice(privateKey: privateKey, mintPrice: value)
        case .unknown: throw SRC721ValidationError.invalidAddress("safe_zone.src721.type.unknown".localized)
        }
    }

    func setMaxSupply(type: SRC721ContractType, value: BigUInt) async throws -> String {
        try await ensureContractOwner(type: type)
        try validateAmount(value, field: "safe_zone.src721.field.max_supply".localized)
        let currentSupply: BigUInt
        switch type {
        case .standard: currentSupply = try await standard().totalSupply()
        case .burnable: currentSupply = try await burnable().totalSupply()
        case .unknown: throw SRC721ValidationError.invalidAddress("safe_zone.src721.type.unknown".localized)
        }
        guard value >= currentSupply else {
            throw SRC721ValidationError.invalidAmount("safe_zone.src721.field.max_supply".localized)
        }
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
        try await ensureContractOwner(type: type)
        guard !addresses.isEmpty, addresses.count == amounts.count,
              addresses.allSatisfy({ $0.address.lowercased() != SRC721Validation.zeroAddress }),
              amounts.allSatisfy({ $0 <= SRC721Validation.uint256Max }) else {
            throw SRC721ValidationError.invalidAllowList
        }
        switch type {
        case .standard: return try await standard().setAllowList(privateKey: privateKey, addresses: addresses, amounts: amounts)
        case .burnable: return try await burnable().setAllowList(privateKey: privateKey, addresses: addresses, amounts: amounts)
        case .unknown: throw SRC721ValidationError.invalidAddress("safe_zone.src721.type.unknown".localized)
        }
    }

    func updateMetadata(type: SRC721ContractType, orgName: String?, description: String?, officialURL: String?, whitePaperURL: String?, logo: Data?) async throws -> [String] {
        try await ensureContractOwner(type: type)
        if let logo { _ = try SRC721Validation.logo(logo) }
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
        try await ensureContractOwner(type: type)
        if let baseURI { _ = try SRC721Validation.optionalBaseURI(baseURI) }
        if let maxSupply {
            try validateAmount(maxSupply, field: "safe_zone.src721.field.max_supply".localized)
            let currentSupply: BigUInt
            switch type {
            case .standard: currentSupply = try await standard().totalSupply()
            case .burnable: currentSupply = try await burnable().totalSupply()
            case .unknown: throw SRC721ValidationError.invalidAddress("safe_zone.src721.type.unknown".localized)
            }
            guard maxSupply >= currentSupply else {
                throw SRC721ValidationError.invalidAmount("safe_zone.src721.field.max_supply".localized)
            }
        }
        if let mintPrice {
            try validateAmount(mintPrice, field: "safe_zone.src721.field.mint_price".localized, allowZero: true)
        }
        if let allowList {
            guard !allowList.0.isEmpty, allowList.0.count == allowList.1.count,
                  allowList.0.allSatisfy({ $0.address.lowercased() != SRC721Validation.zeroAddress }),
                  allowList.1.allSatisfy({ $0 <= SRC721Validation.uint256Max }) else {
                throw SRC721ValidationError.invalidAllowList
            }
        }
        if let logo { _ = try SRC721Validation.logo(logo) }
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
            if orgName != nil || description != nil || officialURL != nil || whitePaperURL != nil || logo != nil {
                do {
                    hashes.append(contentsOf: try await updateMetadata(type: type, orgName: orgName, description: description, officialURL: officialURL, whitePaperURL: whitePaperURL, logo: logo))
                } catch let error as SRC721BatchOperationError {
                    hashes.append(contentsOf: error.submittedHashes)
                    throw error.underlying
                }
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
        try await ensureContractOwner(type: type)
        switch type {
        case .standard: return try await standard().withdraw(privateKey: privateKey)
        case .burnable: return try await burnable().withdraw(privateKey: privateKey)
        case .unknown: throw SRC721ValidationError.invalidAddress("safe_zone.src721.type.unknown".localized)
        }
    }

    func tokenAuthorization(type: SRC721ContractType, tokenId: BigUInt, account: Web3Core.EthereumAddress? = nil) async throws -> SRC721TokenAuthorization {
        try validateTokenId(tokenId)
        let requestedAccount = try account ?? address()
        let account = try validateAddress(requestedAccount, field: "safe_zone.src721.field.wallet".localized)
        switch type {
        case .standard:
            let contract = try await standard()
            let owner = try await contract.ownerOf(tokenId: tokenId)
            let approved = try await contract.getApproved(tokenId: tokenId)
            let isApprovedForAll = try await isApprovedForAll(owner: owner, operatorAddress: account)
            return .init(tokenId: tokenId, ownerAddress: owner.address, approvedAddress: approved.address, isApprovedForAll: isApprovedForAll)
        case .burnable:
            let contract = try await burnable()
            let owner = try await contract.ownerOf(tokenId: tokenId)
            let approved = try await contract.getApproved(tokenId: tokenId)
            let isApprovedForAll = try await isApprovedForAll(owner: owner, operatorAddress: account)
            return .init(tokenId: tokenId, ownerAddress: owner.address, approvedAddress: approved.address, isApprovedForAll: isApprovedForAll)
        case .unknown:
            throw SRC721ValidationError.invalidAddress("safe_zone.src721.type.unknown".localized)
        }
    }

    func tokenState(type: SRC721ContractType, tokenId: BigUInt, account: Web3Core.EthereumAddress? = nil) async throws -> SRC721TokenState {
        let authorization = try await tokenAuthorization(type: type, tokenId: tokenId, account: account)
        let tokenURI: String?
        switch type {
        case .standard: tokenURI = try? await standard().tokenURI(tokenId: tokenId)
        case .burnable: tokenURI = try? await burnable().tokenURI(tokenId: tokenId)
        case .unknown: throw SRC721ValidationError.invalidAddress("safe_zone.src721.type.unknown".localized)
        }
        return SRC721TokenState(tokenId: authorization.tokenId, ownerAddress: authorization.ownerAddress, approvedAddress: authorization.approvedAddress, isApprovedForAll: authorization.isApprovedForAll, tokenURI: tokenURI)
    }

    private func ensureTokenPermission(_ authorization: SRC721TokenAuthorization) throws {
        let wallet = userAddress.lowercased()
        guard authorization.ownerAddress.lowercased() == wallet ||
                authorization.approvedAddress.lowercased() == wallet ||
                authorization.isApprovedForAll else {
            throw SRC721ValidationError.tokenOperationUnavailable
        }
    }

    private func ensureApprovalPermission(_ authorization: SRC721TokenAuthorization) throws {
        let wallet = userAddress.lowercased()
        guard authorization.ownerAddress.lowercased() == wallet || authorization.isApprovedForAll else {
            throw SRC721ValidationError.tokenOperationUnavailable
        }
    }

    func isApprovedForAll(owner: Web3Core.EthereumAddress, operatorAddress: Web3Core.EthereumAddress) async throws -> Bool {
        let owner = try validateAddress(owner, field: "safe_zone.src721.field.owner".localized)
        let operatorAddress = try validateAddress(operatorAddress, field: "safe_zone.src721.field.operator".localized)
        let web3 = try await web3()
        let contractAddress = try validatedContractAddress()
        guard let contract = web3.contract(Self.approvalABI, at: contractAddress),
              let operation = contract.createReadOperation("isApprovedForAll", parameters: [owner, operatorAddress]) else {
            throw SRC721ValidationError.invalidContract
        }
        let response = try await operation.callContractMethod()
        guard let result = response["0"] as? Bool else { throw SRC721ValidationError.invalidContract }
        return result
    }

    func setApprovalForAll(operatorAddress: Web3Core.EthereumAddress, approved: Bool) async throws -> String {
        try ensureSigner()
        let owner = try address()
        let operatorAddress = try validateAddress(operatorAddress, field: "safe_zone.src721.field.operator".localized)
        guard operatorAddress.address.lowercased() != owner.address.lowercased() else {
            throw SRC721ValidationError.invalidAddress("safe_zone.src721.field.operator".localized)
        }
        let web3 = try await web3()
        let contractAddress = try validatedContractAddress()
        guard let contract = web3.contract(Self.approvalABI, at: contractAddress),
              let operation = contract.createWriteOperation("setApprovalForAll", parameters: [operatorAddress, approved]) else {
            throw SRC721ValidationError.invalidContract
        }
        let from = try address()
        var transaction = operation.transaction
        transaction.from = from
        transaction.nonce = try await web3.eth.getTransactionCount(for: from, onBlock: .pending)
        transaction.gasPrice = try await web3.eth.gasPrice()
        transaction.gasLimit = try await web3.eth.estimateGas(for: transaction, onBlock: .pending) * 6 / 5
        try transaction.sign(privateKey: privateKey)
        guard let encodedTransaction = transaction.encode(for: .transaction) else {
            throw Web3Error.processingError(desc: "Unable to encode the SRC721 authorization transaction")
        }
        let result = try await web3.eth.send(raw: encodedTransaction)
        return result.hash
    }

    func approve(type: SRC721ContractType, to: Web3Core.EthereumAddress, tokenId: BigUInt) async throws -> String {
        try ensureSigner()
        let to = try validateAddress(to, field: "safe_zone.src721.field.recipient".localized, allowZero: true)
        try validateTokenId(tokenId)
        try ensureApprovalPermission(try await tokenAuthorization(type: type, tokenId: tokenId))
        switch type {
        case .standard: return try await standard().approve(privateKey: privateKey, to: to, tokenId: tokenId)
        case .burnable: return try await burnable().approve(privateKey: privateKey, to: to, tokenId: tokenId)
        case .unknown: throw SRC721ValidationError.invalidAddress("safe_zone.src721.type.unknown".localized)
        }
    }

    func transfer(type: SRC721ContractType, from requestedFrom: Web3Core.EthereumAddress, to: Web3Core.EthereumAddress, tokenId: BigUInt) async throws -> String {
        try ensureSigner()
        let to = try validateAddress(to, field: "safe_zone.src721.field.recipient".localized)
        try validateTokenId(tokenId)
        let authorization = try await tokenAuthorization(type: type, tokenId: tokenId)
        try ensureTokenPermission(authorization)
        let from = try SRC721Validation.address(authorization.ownerAddress, field: "safe_zone.src721.field.owner".localized)
        guard requestedFrom.address.lowercased() == from.address.lowercased() else {
            throw SRC721ValidationError.tokenOperationUnavailable
        }
        switch type {
        case .standard: return try await standard().safeTransferFrom(privateKey: privateKey, from: from, to: to, tokenId: tokenId)
        case .burnable: return try await burnable().safeTransferFrom(privateKey: privateKey, from: from, to: to, tokenId: tokenId)
        case .unknown: throw SRC721ValidationError.invalidAddress("safe_zone.src721.type.unknown".localized)
        }
    }

    func burn(type: SRC721ContractType, tokenId: BigUInt) async throws -> String {
        try ensureSigner()
        guard type == .burnable else { throw SRC721ValidationError.invalidAddress("safe_zone.src721.type.burnable".localized) }
        try validateTokenId(tokenId)
        try ensureTokenPermission(try await tokenAuthorization(type: type, tokenId: tokenId))
        return try await burnable().burn(privateKey: privateKey, tokenId: tokenId)
    }
}
