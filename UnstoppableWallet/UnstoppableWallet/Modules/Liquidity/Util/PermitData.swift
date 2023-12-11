import Foundation
import BigInt
import EvmKit

struct PermitData: Codable {
    var types: Types
    var primaryType: String
    var domain: Domain
    var message: Message

    func encode() throws -> Data {
        let encoder = JSONEncoder()
        return try encoder.encode(self)
    }
}

struct Domain: Codable {
    let name: String
    let version: String
    let chainId: Int
    let verifyingContract: String
}

struct Message: Codable {
    let owner: String
    let spender: String
    let value: Decimal
    let nonce: Int
    let deadline: UInt64

}

struct Types: Codable {
    var EIP712Domain: [TypeDefine] = [
        TypeDefine(name: "name", type: "string"),
        TypeDefine(name: "version", type: "string"),
        TypeDefine(name: "chainId", type: "uint256"),
        TypeDefine(name: "verifyingContract", type: "address"),
    ]

    var Permit: [TypeDefine] = [
        TypeDefine(name: "owner", type: "address"),
        TypeDefine(name: "spender", type: "address"),
        TypeDefine(name: "value", type: "uint256"),
        TypeDefine(name: "nonce", type: "uint256"),
        TypeDefine(name: "deadline", type: "uint256"),
    ]

    func encode() throws -> Data {
        let encoder = JSONEncoder()
        return try encoder.encode(self)
    }
}

struct TypeDefine: Codable {
    let name: String
    let type: String
}

