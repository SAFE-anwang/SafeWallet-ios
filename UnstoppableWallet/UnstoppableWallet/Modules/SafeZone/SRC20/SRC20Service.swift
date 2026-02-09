import Foundation
import web3swift
import Web3Core
import BigInt
import EvmKit

class SRC20Service {

    let contract: String
    private let privateKey: Data
    private let lockAddress: String

    private func src20() async throws -> SRC20 {
        return try await SRC20(web3: web3(), contractAddr: contract)
    }
    
    private func src20Burnable() async throws -> SRC20Burnable {
        return try await SRC20Burnable(web3: web3(), contractAddr: contract)
    }
    
    private func src20Mintble() async throws -> SRC20Mintable {
        return try await SRC20Mintable(web3: web3(), contractAddr: contract)
    }
    
    private func src20LockFactory() async throws -> SRC20LockFactory {
        return try await SRC20LockFactory(web3: web3(), contractAddr: scr20TimeLockAddress)
    }
    
    init(token: Safe4CustomTokenRecord? = nil, privateKey: Data, lockAddress: String) {
        self.contract = token?.address ?? ""
        self.privateKey = privateKey
        self.lockAddress = lockAddress
    }
    
    private func web3() async throws -> Web3 {
        let chain = Chain.safeFourChain()
        let url = RpcSource.safeFourRpcHttp().url
        return try await Web3.new( url, network: Networks.Custom(networkID: BigUInt(chain.id)))
    }
        
    func deploy(type: DeployType, name: String, symbol: String, totalSupply: BigUInt) async throws -> [String] {
        switch type {
        case .SRC20:
            try await src20().deploy(privateKey: privateKey, name: name, symbol: symbol, totalSupply: totalSupply)
        case .SRC20Mintable:
            try await src20Mintble().deploy(privateKey: privateKey, name: name, symbol: symbol, totalSupply: totalSupply)
        case .SRC20Burnable:
            try await src20Burnable().deploy(privateKey: privateKey, name: name, symbol: symbol, totalSupply: totalSupply)
        }
    }
    
    func mint(type: DeployType, to: Web3Core.EthereumAddress, amount: BigUInt) async throws -> String {
        switch type {
        case .SRC20Mintable:
            try await src20Mintble().mint(privateKey: privateKey, to: to, amount: amount)
        case .SRC20Burnable:
            try await src20Burnable().mint(privateKey: privateKey, to: to, amount: amount)
        case .SRC20:
            throw SRC20ServiceError.unsupportedDeployType
        }
    }
    
    func burn(amount: BigUInt) async throws -> String {
        try await src20Burnable().burn(privateKey: privateKey, amount: amount)
    }
    
    func getLogoPayAmount(type: DeployType) async throws -> BigUInt {
        switch type {
        case .SRC20:
            try await src20().getLogoPayAmount()
        case .SRC20Mintable:
            try await src20Mintble().getLogoPayAmount()
        case .SRC20Burnable:
            try await src20Burnable().getLogoPayAmount()
        }
    }
    
    func setLogoPayAmount(type: DeployType, logo: Data) async throws -> String {
        switch type {
        case .SRC20:
            try await src20().setLogo(privateKey: privateKey, logo: logo)
        case .SRC20Mintable:
            try await src20Mintble().setLogo(privateKey: privateKey, logo: logo)
        case .SRC20Burnable:
            try await src20Burnable().setLogo(privateKey: privateKey, logo: logo)
        }
    }
    
    func orgName(type: DeployType) async throws -> String {
        switch type {
        case .SRC20:
            try await src20().orgName()
        case .SRC20Mintable:
            try await src20Mintble().orgName()
        case .SRC20Burnable:
            try await src20Burnable().orgName()
        }
    }
    
    func setOrgName(type: DeployType, orgName: String) async throws -> String {
        switch type {
        case .SRC20:
            try await src20().setOrgName(privateKey: privateKey, orgName: orgName)
        case .SRC20Mintable:
            try await src20Mintble().setOrgName(privateKey: privateKey, orgName: orgName)
        case .SRC20Burnable:
            try await src20Burnable().setOrgName(privateKey: privateKey, orgName: orgName)
        }
    }
    
    func description(type: DeployType) async throws -> String {
        switch type {
        case .SRC20:
            try await src20().description()
        case .SRC20Mintable:
            try await src20Mintble().description()
        case .SRC20Burnable:
            try await src20Burnable().description()
        }
    }
    
    func setDescription(type: DeployType, description: String) async throws -> String {
        switch type {
        case .SRC20:
            try await src20().setDescription(privateKey: privateKey, description: description)
        case .SRC20Mintable:
            try await src20Mintble().setDescription(privateKey: privateKey, description: description)
        case .SRC20Burnable:
            try await src20Burnable().setDescription(privateKey: privateKey, description: description)
        }
    }
    
    func officialUrl(type: DeployType) async throws -> String {
        switch type {
        case .SRC20:
            try await src20().officialUrl()
        case .SRC20Mintable:
            try await src20Mintble().officialUrl()
        case .SRC20Burnable:
            try await src20Burnable().officialUrl()
        }
    }
    
    func setOfficialUrl(type: DeployType, officialUrl: String) async throws -> String {
        switch type {
        case .SRC20:
            try await src20().setOfficialUrl(privateKey: privateKey, officialUrl: officialUrl)
        case .SRC20Mintable:
            try await src20Mintble().setOfficialUrl(privateKey: privateKey, officialUrl: officialUrl)
        case .SRC20Burnable:
            try await src20Burnable().setOfficialUrl(privateKey: privateKey, officialUrl: officialUrl)
        }
    }
    
    func whitePaperUrl(type: DeployType) async throws -> String {
        switch type {
        case .SRC20:
            try await src20().whitePaperUrl()
        case .SRC20Mintable:
            try await src20Mintble().whitePaperUrl()
        case .SRC20Burnable:
            try await src20Burnable().whitePaperUrl()
        }
    }
    
    func setWhitePaperUrl(type: DeployType, whitePaperUrl: String) async throws -> String {
        switch type {
        case .SRC20:
            try await src20().setWhitePaperUrl(privateKey: privateKey, whitePaperUrl: whitePaperUrl)
        case .SRC20Mintable:
            try await src20Mintble().setWhitePaperUrl(privateKey: privateKey, whitePaperUrl: whitePaperUrl)
        case .SRC20Burnable:
            try await src20Burnable().setWhitePaperUrl(privateKey: privateKey, whitePaperUrl: whitePaperUrl)
        }
    }
    
    func version(chainId: Int, contract: String) async throws -> String {
        let url = RpcSource.safeFourRpcHttp().url
        let web3 = try await Web3.new( url, network: Networks.Custom(networkID: BigUInt(chainId)))
        let src20 = SRC20(web3: web3, contractAddr: contract)
        return try await src20.version()
    }

    func totalSupply(type: DeployType) async throws -> BigUInt {
        switch type {
        case .SRC20:
            try await src20().totalSupply()
        case .SRC20Mintable:
            try await src20Mintble().totalSupply()
        case .SRC20Burnable:
            try await src20Burnable().totalSupply()
        }
    }

    func balance(type: DeployType, account: Web3Core.EthereumAddress) async throws -> BigUInt {
        switch type {
        case .SRC20:
            try await src20().balanceOf(account: account)
        case .SRC20Mintable:
            try await src20Mintble().balanceOf(account: account)
        case .SRC20Burnable:
            try await src20Burnable().balanceOf(account: account)
        }
    }
}

// locked
extension SRC20Service {
    
    var scr20TimeLockAddress: String {
        if AppConfig.isSafe4TestNet {
            "0x4f203092FB68732D8484c099a72dDc5a195f26f9"
        } else {
            "0x6A6dFAF83cc1741FE08A9EFDea596dEad68f7420"
        }
    }

//    func getLock() async throws -> Web3Core.EthereumAddress {
//        let token = Web3Core.EthereumAddress(from: contract)!
//        return try await src20LockFactory().getLock(token)
//    }
    
    func getLockedIDNum() async throws -> BigUInt {
        let token = Web3Core.EthereumAddress(from: contract)!
        let address = Web3Core.EthereumAddress(from: lockAddress)!
        return try await src20LockFactory().getLockedIDNum(token, address)
    }

    func getLockedIDs(start: BigUInt, count: BigUInt) async throws -> [BigUInt] {
        let token = Web3Core.EthereumAddress(from: contract)!
        let address = Web3Core.EthereumAddress(from: lockAddress)!
        return try await src20LockFactory().getLockedIDs(token, address, start, count)
    }

    func getRecordByID(id: BigUInt) async throws -> LockRecord {
        let token = Web3Core.EthereumAddress(from: contract)!
        return try await src20LockFactory().getRecordByID(token, id)
    }
}

extension SRC20Service {
    enum SRC20ServiceError: Error {
        case unsupportedDeployType
    }
}
