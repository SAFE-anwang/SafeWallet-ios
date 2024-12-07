import Foundation
import RxSwift
import HsToolKit
import ObjectMapper
import Alamofire

class DrawSafe4Provider {
    
    private let baseUrl = "https://safe4testnet.anwang.com"
    private let networkManager: NetworkManager

    init(networkManager: NetworkManager) {
        self.networkManager = networkManager
    }
    
    func drawSafe4RequestSingle(address: String) -> Single<DrawSafe4Response> {
 
        let rawString = """
        {
            "address": "\(address)"
        }
        """
        let rawData = Data(rawString.utf8)
        var request = URLRequest(url: URL(string: "\(baseUrl)/5005/get_test_coin")!)
        request.httpMethod = HTTPMethod.post.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = rawData
        let session = Session()
        return session.requestJSON(request: request)
        return networkManager
            .single(url: "\(baseUrl)/5005/get_test_coin", method: .post, parameters: [:], encoding: URLEncoding.httpBody, headers: nil)
    }
}

struct DrawSafe4Response: ImmutableMappable, Decodable {
    var message: String?
    let data: DrawSafe4Info?
    var code: String?

    init(map: Map) throws {
        message = map.JSON["message"] as? String
        data = try? map.value("data")
        code = map.JSON["code"] as? String
    }
    
    var issuccess: Bool {
        code == "0"
    }
}

struct DrawSafe4Info: ImmutableMappable, Decodable {
    let amount: String?
    let transactionHash: String?
    let address: String?
    let dateTimestamp: Int?
    let from: String?
    let nonce: Int?
    
    init(map: Map) throws {
        amount = try? map.value("amount")
        transactionHash = try? map.value("transactionHash")
        address = try? map.value("address")
        dateTimestamp = try? map.value("dateTimestamp")
        from = try? map.value("from")
        nonce = try? map.value("nonce")
    }
    
    var time: String {
        let date = Date(timeIntervalSince1970: Double(dateTimestamp ?? 0) / 1000)
        return DateHelper().safe4Format(date: date)
    }
}

extension Session {
    func requestJSON<T: ImmutableMappable>(request: URLRequest) -> Single<T> {
        return Single.create { single in
            let request = self.request(request)
                .validate()
                .responseJSON { response in
                    switch response.result {
                    case .success(let value):
                        if let json = value as? [String: Any] {
                            do {
                                let result: T = try T(JSONObject: json, context: nil)
                                single(.success(result))
                            }catch{}
                        } else {
                            single(.error(AFError.responseValidationFailed(reason: .dataFileNil)))
                        }
                    case .failure(let error):
                        single(.error(error))
                    }
                }
            
            return Disposables.create {
                request.cancel()
            }
        }
    }
}
