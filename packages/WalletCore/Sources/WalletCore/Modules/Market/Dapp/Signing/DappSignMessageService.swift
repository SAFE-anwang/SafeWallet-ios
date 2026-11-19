import EvmKit
import Foundation

class DappSignMessageService {
    private let request: DappSignRequest
    private let signService: IDappSignService
    private let signer: Signer

    init(request: DappSignRequest, signService: IDappSignService, signer: Signer) {
        self.request = request
        self.signService = signService
        self.signer = signer
    }

    private var domain: String? {
        switch request.payload {
        case let payload as DappSignTypedDataPayload:
            if let eip712TypedData = try? EIP712TypedData.parseFrom(rawJson: payload.data), let domain = eip712TypedData.domain.objectValue, let domainString = domain["name"]?.stringValue {
                return domainString
            }
        default: ()
        }

        return nil
    }

    private var message: String? {
        switch request.payload {
        case let payload as DappSignPayload:
            return String(data: payload.data, encoding: .utf8) ?? payload.data.hs.hexString
        case let payload as DappPersonalSignPayload:
            return String(data: payload.data, encoding: .utf8) ?? payload.data.hs.hexString
        case let payload as DappSignTypedDataPayload:
            do {
                let eip712TypedData = try EIP712TypedData.parseFrom(rawJson: payload.data)
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let data = try encoder.encode(eip712TypedData.sanitizedMessage)

                return String(decoding: data, as: UTF8.self)
            } catch {
                return ""
            }
        default: return ""
        }
    }

    private func sign(message: Data, isLegacy: Bool = false) throws -> Data {
        try signer.signed(message: message, isLegacy: isLegacy)
    }
}

extension DappSignMessageService {
    var sections: [Section] {
        var sections = [Section]()

        if let domain {
            sections.append(Section(header: nil, items: [.domain(domain)]))
        }

        var infoItems: [Item] = [
            .dApp(name: request.payload.dAppName),
        ]
        if let name = request.chain.chainName, let address = request.chain.address {
            infoItems.append(.blockchain(name: name, address: address))
        }
        sections.append(Section(header: nil, items: infoItems))

        if let message {
            sections.append(Section(header: .signMessage, items: [.message(message)]))
        }

        return sections
    }

    func sign() throws {
        let signedMessage: Data

        switch request.payload {
        case let payload as DappSignPayload: // legacy sync use already prefixed data hashed by Kessak-256 with length 32 bytes
            let isLegacy = payload.data.count == 32 && (String(data: payload.data, encoding: .utf8) != nil)
            signedMessage = try sign(message: payload.data, isLegacy: isLegacy)
        case let payload as DappPersonalSignPayload:
            signedMessage = try sign(message: payload.data)
        case let payload as DappSignTypedDataPayload:
            let eip712TypedData = try EIP712TypedData.parseFrom(rawJson: payload.data)
            signedMessage = try signer.sign(eip712TypedData: eip712TypedData)
        default: signedMessage = Data()
        }

        signService.approveRequest(id: request.id, result: signedMessage)
    }

    func reject() {
        signService.rejectRequest(id: request.id)
    }
}

extension DappSignMessageService {
    enum Item {
        case domain(String)
        case dApp(name: String)
        case blockchain(name: String, address: String)
        case message(String)
    }

    enum Header {
        case signMessage
    }

    struct Section {
        let header: Header?
        let items: [Item]
    }
}
