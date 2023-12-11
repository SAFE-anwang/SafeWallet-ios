
import Foundation
import BigInt
import Web3Core
import web3swift
import CryptoSwift
/*
class TransactionContractSend {
    private let bscURL = URL(string: "https://bsc-dataseed.binance.org/")!
    let routerAddress = EthereumAddress("0x10ED43C718714eb63d5aA57B78B54704E256024E") // pancake的路由合约地址
    let lpTokenAddress = EthereumAddress("0x0eD7e52944161450477ee417DE9Cd3a859b14fD0") // 流动性代币合约地址
    let pairAddress = EthereumAddress("0x58F876857a02D6762E0101bb5C46A8c1ED44Dc16") // 流动性代币对的地址
    let pairSymbol = "BUSD-BNB" // 流动性代币对的符号
//    let privateKey = //PrivateKey(raw: Data(hex: "0x...")) // 用户的私钥
//    let ownerAddress = privateKey.address() // 用户的地址
    
    func removeLiquidityWithPermit(
        routerAddress: EthereumAddress, // pancake的路由合约地址
        lpTokenAddress: EthereumAddress, // 流动性代币合约地址
        pairAddress: EthereumAddress, // 流动性代币对的地址
        pairSymbol: String, // 流动性代币对的符号
        privateKey: PrivateKey, // 用户的私钥
        ownerAddress: EthereumAddress, // 用户的地址
        amount: EIP712.UInt256, // 移除的流动性代币数量
        minAmountA: EIP712.UInt256, // 最小接收的代币A数量
        minAmountB: EIP712.UInt256, // 最小接收的代币B数量
        deadline: EIP712.UInt256, // 最晚的交易时间
        to: EthereumAddress // 接收地址
    ) async throws {
//        let network = InfuraNetwork(chain: "bsc", apiKey: "...")
//        let web3 = Web3(network: network) // 连接到BSC网络
        let web3 = try await Web3.new(bscURL)
//        let routerContract = Contract(
//            address: routerAddress, // pancake的路由合约地址
    let routerAbiString = "[{\"inputs\":[{\"internalType\":\"address\",\"name\":\"tokenA\",\"type\":\"address\"},{\"internalType\":\"address\",\"name\":\"tokenB\",\"type\":\"address\"},{\"internalType\":\"uint256\",\"name\":\"liquidity\",\"type\":\"uint256\"},{\"internalType\":\"uint256\",\"name\":\"amountAMin\",\"type\":\"uint256\"},{\"internalType\":\"uint256\",\"name\":\"amountBMin\",\"type\":\"uint256\"},{\"internalType\":\"address\",\"name\":\"to\",\"type\":\"address\"},{\"internalType\":\"uint256\",\"name\":\"deadline\",\"type\":\"uint256\"},{\"internalType\":\"bool\",\"name\":\"approveMax\",\"type\":\"bool\"},{\"internalType\":\"uint8\",\"name\":\"v\",\"type\":\"uint8\"},{\"internalType\":\"bytes32\",\"name\":\"r\",\"type\":\"bytes32\"},{\"internalType\":\"bytes32\",\"name\":\"s\",\"type\":\"bytes32\"}],\"name\":\"removeLiquidityWithPermit\",\"outputs\":[{\"internalType\":\"uint256\",\"name\":\"amountA\",\"type\":\"uint256\"},{\"internalType\":\"uint256\",\"name\":\"amountB\",\"type\":\"uint256\"}],\"stateMutability\":\"nonpayable\",\"type\":\"function\"}]" // pancake的路由合约ABI
//        ) // pancake的路由合约
//        let lpTokenContract = Contract(
//            address: lpTokenAddress, // 流动性代币合约地址
//            abi: "[{\"inputs\":[],\"name\":\"DOMAIN_SEPARATOR\",\"outputs\":[{\"internalType\":\"bytes32\",\"name\":\"\",\"type\":\"bytes32\"}],\"stateMutability\":\"view\",\"type\":\"function\"},{\"inputs\":[{\"internalType\":\"address\",\"name\":\"owner\",\"type\":\"address\"}],\"name\":\"nonces\",\"outputs\":[{\"internalType\":\"uint256\",\"name\":\"\",\"type\":\"uint256\"}],\"stateMutability\":\"view\",\"type\":\"function\"}]" // 流动性代币合约ABI
//        ) // 流动性代币合约
        let lpTokenAbiString = "[{\"inputs\":[],\"name\":\"DOMAIN_SEPARATOR\",\"outputs\":[{\"internalType\":\"bytes32\",\"name\":\"\",\"type\":\"bytes32\"}],\"stateMutability\":\"view\",\"type\":\"function\"},{\"inputs\":[{\"internalType\":\"address\",\"name\":\"owner\",\"type\":\"address\"}],\"name\":\"nonces\",\"outputs\":[{\"internalType\":\"uint256\",\"name\":\"\",\"type\":\"uint256\"}],\"stateMutability\":\"view\",\"type\":\"function\"}]" // 流动性代币合约ABI
        var lpTokenContract = web3.contract(lpTokenAbiString, at: lpTokenAddress, abiVersion: 2)!
        
        guard let domainSeparatorResult = try await lpTokenContract.createReadOperation("DOMAIN_SEPARATOR")?.callContractMethod() else {
            
        }//("DOMAIN_SEPARATOR", args: [])[0] as! Data // 获取域分隔符
        
        guard let nonceResult = try await lpTokenContract.createReadOperation("nonces")?.callContractMethod() else {
            
        }//call("nonces", args: [ownerAddress])[0] as! UInt256 // 获取签名计数器
        let domainSeparator = domainSeparatorResult[""] as! Data
        let nonce = nonceResult[""] as! EIP712.UInt256
        
        let permit = getPermit(owner: ownerAddress, spender: routerAddress, value: amount, nonce: nonce, deadline: deadline) // 获取授权信息
        let dataToSign = getPermitData(permit: permit, domainSeparator: domainSeparator) // 获取签名数据
        let (v, r, s) = getPermitSignature(dataToSign: dataToSign, privateKey: privateKey) // 获取签名参数
//        let tx = try! routerContract.send("removeLiquidityWithPermit", args: [pairAddress, amount, minAmountA
    
    func getPermit(owner: EthereumAddress, spender: EthereumAddress, value: EIP712.UInt256, nonce: EIP712.UInt256, deadline: EIP712.UInt256) -> Permit {
        let permit = Permit(
            owner: owner, // 用户地址
            spender: spender, // 接收地址
            value: value, // 代币数量
            nonce: nonce, // 签名计数器
            deadline: deadline // 签名有效期
        )
        return permit // 返回授权信息
    }
    
    func getPermitData(permit: Permit, domainSeparator: Data) -> Data {
        let PERMIT_TYPEHASH = Data(hex: "0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9") // 签名类型哈希
        let x19 = Data(hex: "0x1901") // 签名版本
        let permitData = PERMIT_TYPEHASH + // 签名类型哈希
            permit.owner.addressData + // 用户地址序列化
            permit.spender.addressData + // 接收地址序列化
            permit.value.serialize() + // 代币数量序列化
            permit.nonce.serialize() + // 签名计数器序列化
            permit.deadline.serialize() // 签名有效期序列化
        let permitHash = permitData.sha3(.keccak256)//.toHexString().addHexPrefix()//.keccak256() // 授权数据哈希
        let dataToSign = x19 + domainSeparator + permitHash // 签名数据
        return dataToSign // 返回签名数据
    }
    
        func getPermitSignature(web3: Web3, dataToSign: Data) -> (UInt8, Data, Data) {
        
        let signature = try await web3.personal.signPersonalMessage(message: dataToSign, from: expectedAddress, password: "")

//        let signature = try! privateKey.sign(message: dataToSign) // 签名
        let v = signature[64] // 恢复字节
        let r = Data(signature[0..<32]) // 前32字节
        let s = Data(signature[32..<64]) // 后32字节
        return (v, r, s) // 返回签名参数
    }

    
//    // 定义一个函数，用来计算v, r, s三个值
//    func calculateVRS(
//        lpToken: EthereumAddress, // LP代币合约的地址
//        owner: EthereumAddress, // 持有者的地址
//        value: BigUInt, // 授权的数量
//        deadline: BigUInt // 授权的截止时间
//    ) async throws -> (UInt8, Data, Data)? {
//        // 获取web3实例，连接到BSC网络
//        let web3 = try await Web3.new(bscURL)
//
//        // 获取LP代币合约的实例
//        let lpTokenContract = web3.contract(Web3.Utils.erc20ABI, at: lpToken, abiVersion: 2)!
//        let xx = try await lpTokenContract.createReadOperation("DOMAIN_SEPARATOR")?.callContractMethod()
////        // 获取DOMAIN_SEPARATOR的值
////        guard let domainSeparator = try? lpTokenContract.read("DOMAIN_SEPARATOR").call() else {
////            print("Failed to get DOMAIN_SEPARATOR")
////            return nil
////        }
////
////        // 获取nonce的值
////        guard let nonce = try? lpTokenContract.read("nonces", parameters: [owner] as [AnyObject]).call() else {
////            print("Failed to get nonce")
////            return nil
////        }
//        let  router = EthereumAddress(Constants.DEX.PANCAKE_V2_ROUTER_ADDRESS)!
//        // 对PERMIT_TYPEHASH, owner, ROUTER_ADDRESS, value, nonce, deadline进行ABI编码，得到x
//        let x = Web3.Utils.keccak256(Web3.Utils.encode([
//            Constants.PERMIT_TYPEHASH,
//            owner.addressData,
//            router.addressData,
//            value,
//            27,
//            deadline
//        ]))
//
//        // 对x19, domainSeparator, x进行ABI编码，得到y
//        let y = web3.utils.keccak256(Web3.Utils.encode([
//            X19,
//            domainSeparator[0] as! Data,
//            x
//        ]))
//
//        // 使用私钥对y进行签名，得到z
//        guard let privateKey = try? EthereumPrivateKey(hexPrivateKey: "YOUR_PRIVATE_KEY") else {
//            print("Failed to create private key")
//            return nil
//        }
//        guard let z = try? web3.wallet.signPersonalMessage(y, keystore: privateKey) else {
//            print("Failed to sign message")
//            return nil
//        }
//
//        // 分割z，得到v, r, s
//        let v = z[64]
//        let r = z[0..<32]
//        let s = z[32..<64]
//
//        // 返回v, r, s
//        return (v, r, s)
//    }

}

struct Domain {
    var name: String // 合约名称
    var version: String // 合约版本
    var chainId: EIP712.UInt256 // 链ID
    var verifyingContract: EthereumAddress // 合约地址
}

struct Permit {
    var owner: EthereumAddress // 用户地址
    var spender: EthereumAddress // 接收地址
    var value: EIP712.UInt256 // 代币数量
    var nonce: EIP712.UInt256 // 签名计数器
    var deadline: EIP712.UInt256 // 签名有效期
}

struct RemoveLiquidityParams {
    var tokenA: EthereumAddress // 代币A的地址
    var tokenB: EthereumAddress // 代币B的地址
    var liquidity: EIP712.UInt256 // 流动性代币数量
    var amountAMin: EIP712.UInt256 // 代币A的最小数量
    var amountBMin: EIP712.UInt256 // 代币B的最小数量
    var to: EthereumAddress // 接收地址
    var deadline: EIP712.UInt256 // 交易有效期
}

*/
class TransactionContractSend {
//
    
    static func testWithSignEIP712(message: Data, pairAddress: String, receiveAddress: String, privateKey: Data, permitMessage: PermitMessage) async throws -> Data { //(v: UInt8, r: Data, s: Data) {
        let providerURL = URL(string: "https://bsc-dataseed.binance.org/")!
        let web3 = try await Web3.new(providerURL)
        let password  = ""
        let keystore = try! EthereumKeystoreV3(privateKey: privateKey, password: password)!
        let manager = KeystoreManager([keystore])
        web3.addKeystoreManager(manager)
        
        let verifyingContract = EthereumAddress(pairAddress)!
        let account = keystore.addresses?[0]
        let domainSeparator: EIP712Hashable = EIP712Domain(name: "PancakeSwap", version: "1", chainId: EIP712.UInt256(56), verifyingContract: verifyingContract)
        let hash = try eip712encode(domainSeparator: domainSeparator, message: permitMessage)
        print("eip712encode: \(hash.toHexString())")
        guard let signature = try Web3Signer.signPersonalMessage(hash,
                                                                 keystore: keystore,
                                                                 account: account!,
                                                                 password: password)
        else {
            throw Web3Error.dataError
        }
        return signature
    }
}

struct EIP712Domain: EIP712Hashable {
    let name: String
    let version: String
    let chainId: EIP712.UInt256
    let verifyingContract: EIP712.Address
}

struct PermitMessage: EIP712Hashable {
    let owner: EIP712.Address
    let spender: EIP712.Address
    let value: EIP712.UInt256
    let nonce: EIP712.UInt256
    let deadline: EIP712.UInt256
}
