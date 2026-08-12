import Foundation
import BigInt
import RxSwift
import HsToolKit
import ObjectMapper
import Alamofire


class MarketDappProvider {

    private let baseUrl = "https://safewallet.anwang.com/api"
    private let headers = HTTPHeaders([
        HTTPHeader(name: "x-auth", value: "KLFD&*jk42klO)dskdak#@")
    ])
    private let networkManager: NetworkManager

    init(networkManager: NetworkManager) {
        self.networkManager = networkManager
    }


    func dappAllRequestSingle() -> Single<[MarktDapp]> {
         let ur = URL(string: "\(baseUrl)/walletcontent/getAll")!
        let request = networkManager.session.request(ur, headers: headers)
        return networkManager.single(request: request)
    }

    func dappTypeRequestSingle(type: String) -> Single<[MarktDapp]> {
        let parameters: Parameters = [
            "type": type,
        ]
        return networkManager
                .single(url: "\(baseUrl)/walletcontent/byType", method: .get, parameters: parameters, headers: nil)
    }

    func dappSubTypeRequestSingle(subType: String) -> Single<[MarktDapp]> {
        let parameters: Parameters = [
            "subType": subType,
        ]

        return networkManager
                .single(url: "\(baseUrl)/walletcontent/bySubType", method: .get, parameters: parameters, headers: nil)

    }

    func dappByNameRequestSingle(name: String) -> Single<[MarktDapp]> {
        let parameters: Parameters = [
            "name": name,
        ]
        return networkManager
                .single(url: "\(baseUrl)/walletcontent/byName", method: .get, parameters: parameters, headers: nil)

    }

}

struct MarktDapp: ImmutableMappable {

    let type: String
    let subType: String
    let name: String
    let desc: String
    let descEN: String
    var icon: String
    let dlink: String
    var md5Code: String
    let safeDappId: BigUInt?
    let safeDappContractAddr: String?
    let safeDappKeyword: String?
    let safeDappFraudNum: BigUInt?
    let safeDappIsFrozen: Bool?
    let safeDappLogoData: Data?

    init(type: String, subType: String, name: String, desc: String, descEN: String, icon: String, dlink: String, md5Code: String, safeDappId: BigUInt? = nil, safeDappContractAddr: String? = nil, safeDappKeyword: String? = nil, safeDappFraudNum: BigUInt? = nil, safeDappIsFrozen: Bool? = nil, safeDappLogoData: Data? = nil) {
        self.type = type
        self.subType = subType
        self.name = name
        self.desc = desc
        self.descEN = descEN
        self.icon = icon
        self.dlink = dlink
        self.md5Code = md5Code
        self.safeDappId = safeDappId
        self.safeDappContractAddr = safeDappContractAddr
        self.safeDappKeyword = safeDappKeyword
        self.safeDappFraudNum = safeDappFraudNum
        self.safeDappIsFrozen = safeDappIsFrozen
        self.safeDappLogoData = safeDappLogoData
    }

    init(map: Map) throws {
        type = try map.value("type", default: "")
        subType = try map.value("subType", default: "")
        name = try map.value("name", default: "")
        desc = try map.value("desc", default: "")
        descEN = try map.value("descEN", default: "")
        icon = try map.value("icon", default: "")
        dlink = try map.value("dlink")
        md5Code = try map.value("md5Code", default: "")
        safeDappId = nil
        safeDappContractAddr = nil
        safeDappKeyword = nil
        safeDappFraudNum = nil
        safeDappIsFrozen = nil
        safeDappLogoData = nil
    }
}
