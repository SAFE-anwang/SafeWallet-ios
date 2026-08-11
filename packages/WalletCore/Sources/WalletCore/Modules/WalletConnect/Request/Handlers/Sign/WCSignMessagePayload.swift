import Foundation
import SwiftUI
import UIKit
import EvmKit
import WalletConnectSign

class WCSignMessagePayload: WCRequestPayload {
    class var method: String { "" }
    class var name: String { "" }
    override var method: String { Self.method }
    let address: EvmKit.Address?

    override convenience init(dAppName: String, data: Data) {
        self.init(dAppName: dAppName, data: data, address: nil)
    }

    init(dAppName: String, data: Data, address: EvmKit.Address?) {
        self.address = address
        super.init(dAppName: dAppName, data: data)
    }

    public required convenience init(dAppName: String, from anyCodable: AnyCodable) throws {
        let payload = try Self.dataAndAddress(from: anyCodable)
        self.init(dAppName: dAppName, data: payload.data, address: payload.address)
    }

    class func data(from _: AnyCodable) throws -> Data {
        throw ParsingError.badJSONRPCRequest
    }

    class func dataAndAddress(from anyCodable: AnyCodable) throws -> (data: Data, address: EvmKit.Address?) {
        (try data(from: anyCodable), nil)
    }

    class func address(string: String?) -> EvmKit.Address? {
        guard let string else {
            return nil
        }

        return try? EvmKit.Address(hex: string)
    }

    class func messageData(string: String?) -> Data? {
        guard let string else {
            return nil
        }

        return string.hs.hexData ?? string.data(using: .utf8)
    }

    class func module(request: WalletConnectRequest) -> UIViewController? {
        WCSignMessageRequestModule.viewController(request: request).map { ThemeNavigationController(rootViewController: $0) }
    }

    class func view(request: WalletConnectRequest) -> some View {
        WCSignMessageRequestView(request: request)
    }
}

class WCSignPayload: WCSignMessagePayload {
    override class var method: String { "eth_sign" }
    override class var name: String { "Sign Request" }

    override class func data(from anyCodable: AnyCodable) throws -> Data {
        try dataAndAddress(from: anyCodable).data
    }

    override class func dataAndAddress(from anyCodable: AnyCodable) throws -> (data: Data, address: EvmKit.Address?) {
        let strings = try anyCodable.get([String].self)
        if strings.count >= 2,
           let address = address(string: strings[0]),
           let data = strings[1].hs.hexData {
            return (data, address)
        }
        throw ParsingError.badJSONRPCRequest
    }
}

class WCPersonalSignPayload: WCSignMessagePayload {
    override class var method: String { "personal_sign" }
    override class var name: String { "Personal Sign Request" }

    override class func data(from anyCodable: AnyCodable) throws -> Data {
        try dataAndAddress(from: anyCodable).data
    }

    override class func dataAndAddress(from anyCodable: AnyCodable) throws -> (data: Data, address: EvmKit.Address?) {
        let strings = try anyCodable.get([String].self)
        if strings.count >= 2, let address = address(string: strings[1]), let data = messageData(string: strings[0]) {
            return (data, address)
        }
        if strings.count >= 2, let address = address(string: strings[0]), let data = messageData(string: strings[1]) {
            return (data, address)
        }
        if strings.count >= 1, let data = messageData(string: strings[0]) {
            return (data, nil)
        }
        throw ParsingError.badJSONRPCRequest
    }
}

class WCSignTypedDataPayload: WCSignMessagePayload {
    override class var method: String { "eth_signTypedData" }
    override class var name: String { "Typed Sign Request" }

    override class func data(from anyCodable: AnyCodable) throws -> Data {
        try dataAndAddress(from: anyCodable).data
    }

    override class func dataAndAddress(from anyCodable: AnyCodable) throws -> (data: Data, address: EvmKit.Address?) {
        let strings = try anyCodable.get([String].self)
        if strings.count >= 2,
           let address = address(string: strings[0]),
           let data = strings[1].data(using: .utf8) {
            return (data, address)
        }
        throw ParsingError.badJSONRPCRequest
    }
}

class WCSignTypedDataV4Payload: WCSignTypedDataPayload {
    override class var method: String { "eth_signTypedData_v4" }
    override class var name: String { "Typed Sign v4 Request" }
}
