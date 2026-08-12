import BigInt
import EvmKit
import Foundation
import Web3Core
import web3swift

class SafeDappService {
    private let privateKey: Data
    private let userAddress: SafeDappEthereumAddress
    private let chainId: Int

    init(privateKey: Data, userAddress: String, chainId: Int = Safe4Network.currentChainId) {
        self.privateKey = privateKey
        self.userAddress = SafeDappEthereumAddress(userAddress)!
        self.chainId = chainId
    }

    private static func web3(chainId: Int) async throws -> Web3 {
        let chain = chainId == Chain.SafeFourTestNet.id ? Chain.SafeFourTestNet : Chain.SafeFour
        let urlString = chainId == Chain.SafeFourTestNet.id
            ? ApiKeyManager.rpcEndpoint(network: .safe4_testnet) ?? "https://safe4testnet.anwang.com/rpc"
            : ApiKeyManager.rpcEndpoint(network: .safe4) ?? "https://safe4.anwang.com/rpc"
        let url = URL(string: urlString)!
        return try await Web3.new(url, network: Networks.Custom(networkID: BigUInt(chain.id)))
    }

    private static func dapp(chainId: Int) async throws -> DAppManager {
        let web3 = try await web3(chainId: chainId)
        return web3.safe4.dapp
    }

    private func dapp() async throws -> DAppManager {
        try await Self.dapp(chainId: chainId)
    }
}

extension SafeDappService {
    var account: SafeDappEthereumAddress { userAddress }

    func register(data: SafeDappFormData) async throws -> String {
        let name = data.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let error = SafeDappValidation.validateRequired(name, min: 5, max: 50, title: SafeDappField.name.title) {
            throw SafeDappValidationError(message: error)
        }
        let contractAddr = try SafeDappValidation.ethereumAddress(data.contractAddr, title: SafeDappField.contractAddr.title).get()
        let runUrl = try SafeDappValidation.normalizedUrl(data.runUrl, required: true, title: SafeDappField.runUrl.title, min: 15, max: 200).get()
        let description = data.description.trimmingCharacters(in: .whitespacesAndNewlines)
        if let error = SafeDappValidation.validateRequired(description, min: 10, max: 1024, title: SafeDappField.description.title) {
            throw SafeDappValidationError(message: error)
        }
        let gitUrl = try SafeDappValidation.normalizedUrl(data.gitUrl, required: false, title: SafeDappField.gitUrl.title, min: 0, max: 200).get()
        let officialUrl = try SafeDappValidation.normalizedUrl(data.officialUrl, required: false, title: SafeDappField.officialUrl.title, min: 0, max: 200).get()
        let officialEmail = try SafeDappValidation.optionalEmail(data.officialEmail, title: SafeDappField.officialEmail.title).get()

        return try await dapp().register(
            privateKey: privateKey,
            name: name,
            contractAddr: contractAddr,
            runUrl: runUrl,
            description: description,
            gitUrl: gitUrl,
            officialUrl: officialUrl,
            officialEmail: officialEmail
        )
    }

    func getMineNum() async throws -> BigUInt {
        try await dapp().getMineNum(userAddress)
    }

    func getMineIDs(start: BigUInt, count: BigUInt) async throws -> [BigUInt] {
        try SafeDappValidation.validatePage(start: start, count: count, total: try await getMineNum())
        return try await dapp().getMineIDs(userAddress, start, count)
    }

    func getInfo(id: BigUInt) async throws -> DAppInfo {
        try SafeDappValidation.validateID(id)
        return try await dapp().getInfo(id)
    }

    func getLogo(id: BigUInt) async throws -> Data {
        try SafeDappValidation.validateID(id)
        return try await dapp().getLogo(id)
    }

    func isFrozen(id: BigUInt) async throws -> Bool {
        try SafeDappValidation.validateID(id)
        return try await dapp().isFrozen(id)
    }

    func remove(id: BigUInt) async throws -> String {
        try SafeDappValidation.validateID(id)
        return try await dapp().remove(privateKey: privateKey, id: id)
    }

    func getLogoPayAmount() async throws -> BigUInt {
        try await dapp().getLogoPayAmount()
    }

    func setLogo(id: BigUInt, logo: Data) async throws -> String {
        try SafeDappValidation.validateID(id)
        try SafeDappValidation.validateLogo(logo)
        return try await dapp().setLogo(privateKey: privateKey, id: id, logo: logo)
    }

    func update(field: SafeDappField, id: BigUInt, value: String) async throws -> String {
        try SafeDappValidation.validateID(id)
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        switch field {
        case .name:
            if let error = SafeDappValidation.validateRequired(trimmed, min: 5, max: 50, title: field.title) {
                throw SafeDappValidationError(message: error)
            }
            return try await dapp().setName(privateKey: privateKey, id: id, name: trimmed)
        case .contractAddr:
            let address = try SafeDappValidation.ethereumAddress(trimmed, title: field.title).get()
            return try await dapp().setContractAddr(privateKey: privateKey, id: id, contractAddr: address)
        case .runUrl:
            let url = try SafeDappValidation.normalizedUrl(trimmed, required: true, title: field.title, min: 15, max: 200).get()
            return try await dapp().setRunUrl(privateKey: privateKey, id: id, runUrl: url)
        case .gitUrl:
            let url = try SafeDappValidation.normalizedUrl(trimmed, required: true, title: field.title, min: 20, max: 200).get()
            return try await dapp().setGitUrl(privateKey: privateKey, id: id, gitUrl: url)
        case .officialUrl:
            let url = try SafeDappValidation.normalizedUrl(trimmed, required: true, title: field.title, min: 15, max: 200).get()
            return try await dapp().setOfficialUrl(privateKey: privateKey, id: id, officialUrl: url)
        case .officialEmail:
            let email = try SafeDappValidation.requiredEmail(trimmed, title: field.title).get()
            return try await dapp().setOfficialEmail(privateKey: privateKey, id: id, officialEmail: email)
        case .officialAccount:
            let address = try SafeDappValidation.ethereumAddress(trimmed, title: field.title).get()
            return try await dapp().setOfficialAccount(privateKey: privateKey, id: id, account: address)
        case .description:
            if let error = SafeDappValidation.validateRequired(trimmed, min: 10, max: 1024, title: field.title) {
                throw SafeDappValidationError(message: error)
            }
            return try await dapp().setDescription(privateKey: privateKey, id: id, description: trimmed)
        case .keyword:
            if let error = SafeDappValidation.validateOptional(trimmed, min: 0, max: 200, title: field.title) {
                throw SafeDappValidationError(message: error)
            }
            return try await dapp().setKeyword(privateKey: privateKey, id: id, keyword: trimmed)
        }
    }

    func exists(field: SafeDappField, value: String) async throws -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        switch field {
        case .name:
            return try await dapp().existName(trimmed)
        case .contractAddr:
            let address = try SafeDappValidation.ethereumAddress(trimmed, title: field.title).get()
            return try await dapp().existContractAddr(address)
        case .runUrl:
            let url = try SafeDappValidation.normalizedUrl(trimmed, required: true, title: field.title, min: 15, max: 200).get()
            return try await dapp().existRunUrl(url)
        default:
            return false
        }
    }

    static func publishedDapps(chainId: Int = Safe4Network.currentChainId) async throws -> [DAppInfo] {
        let items = try await publishedDappItems(chainId: chainId)
        return items.map(\.info)
    }

    static func isFrozen(id: BigUInt, chainId: Int = Safe4Network.currentChainId) async throws -> Bool {
        try SafeDappValidation.validateID(id)
        return try await dapp(chainId: chainId).isFrozen(id)
    }

    static func publishedDappItems(chainId: Int = Safe4Network.currentChainId) async throws -> [SafeDappPublishedItem] {
        let dapp = try await dapp(chainId: chainId)
        let total = try await dapp.getNum()
        var ids: [BigUInt] = []
        var start = BigUInt.zero
        let pageSize = BigUInt(100)

        while start < total {
            let count = min(pageSize, total - start)
            try SafeDappValidation.validatePage(start: start, count: count, total: total)
            ids.append(contentsOf: try await dapp.getIDs(start, count))
            start += count
        }

        var items: [SafeDappPublishedItem] = []
        for id in ids {
            let info = try await dapp.getInfo(id)
            guard !info.isFrozen else { continue }
            guard
                let logoData = try? await dapp.getLogo(id),
                !logoData.isEmpty
            else {
                continue
            }
            items.append(SafeDappPublishedItem(info: info, logoData: logoData))
        }
        return items
    }
}
