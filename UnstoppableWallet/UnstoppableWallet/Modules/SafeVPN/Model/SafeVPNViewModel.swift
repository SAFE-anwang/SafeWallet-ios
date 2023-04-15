//
//  SafeVPNViewModel.swift
//  SwiftV2Ray
import Foundation
import Alamofire
import Combine
import NetworkExtension

enum ProxyMode: Int {
    case auto = 0
    case global = 1
    case direct = 2
}
/*
class SafeVPNViewModel: NSObject, Codable {
    var serviceOpen: Bool = false
    var subscribeUrl: URL? = nil
    var activingEndpoint: VmessEndpoint? = nil
    var serviceEndPoints: [VmessEndpoint] = []
    var proxyMode: ProxyMode = .auto
    var v2rayConfig: V2RayConfig = V2RayConfig.parse(fromJsonFile: "config")!
    
    enum CodingKeys: String, CodingKey {
        case subscribeUrl
        case activingEndpoint
        case serviceEndPoints
        case proxyMode
    }
    
    override init() {
        super.init()
        self.loadServices()
        self.updateConfig()
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
//        subscribeUrl != nil ? try container.encode(subscribeUrl?.absoluteString, forKey: .subscribeUrl) : nil
//        activingEndpoint != nil ? try container.encode(activingEndpoint, forKey: .activingEndpoint) : nil
        try container.encode(proxyMode.rawValue, forKey: .proxyMode)
//        try container.encode(serviceEndPoints, forKey: .serviceEndPoints)
    }
    
    required init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let string = values.contains(.subscribeUrl) ? try values.decode(String.self, forKey: .subscribeUrl) : nil
//        subscribeUrl = string != nil ? URL.init(string: string!) : nil
//        activingEndpoint = values.contains(.activingEndpoint) ? try values.decode(VmessEndpoint.self, forKey: .activingEndpoint) : nil
        proxyMode = ProxyMode(rawValue: try values.decode(Int.self, forKey: .proxyMode)) ?? .auto
//        serviceEndPoints = try values.decode([VmessEndpoint].self, forKey: .serviceEndPoints)
    }
    
    func openService(completion: ((_ error: Error?)-> Void)?) {
//        guard (self.activingEndpoint != nil) else {
//            completion?(NSError(domain: "ErrorDomain", code: -1, userInfo: ["error" : "没有激活服务节点"]))
//            return
//        }
        
        let configData = try? JSONEncoder().encode(self.v2rayConfig)
        guard configData != nil else {
            completion?(NSError(domain: "ErrorDomain", code: -1, userInfo: ["error" : "配置错误"]))
            return
        }
        
        let serverIP = PacketTunnelMessage.getIPAddress(domainName: (self.v2rayConfig.outbounds?[0].settingVMess?.vnext[0].address)!)
        let packetTunnelMessage = PacketTunnelMessage(configData: configData, serverIP: serverIP)
        VPNHelper.shared.open(with: packetTunnelMessage, completion: {[weak self] (error) in
            guard error != nil else {
                self?.serviceOpen = true
                return
            }
            
            completion?(error)
        })
    }
    
    func closeService(_ completion: (() -> Void)?) {
        VPNHelper.shared.close {[weak self] in
            self?.serviceOpen = false
            completion?()
        }
    }

    func updateConfig() {
//        guard self.activingEndpoint != nil else {
//            return
//        }
        
        var vnext = Outbound.VMess.Item()
        vnext.address = "139.162.75.142"//self.activingEndpoint?.info[VmessEndpoint.InfoKey.address.stringValue] as! String
        vnext.users[0].id = "6407ce3d-9284-44d7-865d-344187454171"//self.activingEndpoint?.info[VmessEndpoint.InfoKey.uuid.stringValue] as! String
        vnext.users[0].alterId = 0//(self.activingEndpoint?.info[VmessEndpoint.InfoKey.aid.stringValue] as! NSString).integerValue
        vnext.port = 58444//(self.activingEndpoint?.info[VmessEndpoint.InfoKey.port.stringValue] as! NSString).integerValue
        self.v2rayConfig.outbounds?[0].settingVMess?.vnext = [vnext]
    }
    
    func requestServices(withUrl requestUrl: URL?, completion: ((_ error: Error?)-> Void)?) {
//        guard let url = requestUrl else {
//            return
//        }
//
//        AirportTool.getSubscribeVmessPoints(url) {[weak self] (serverPoints, error) in
//            guard error == nil else {
//                if completion != nil {
//                    completion!(error)
//                }
//                return
//            }
//
//            self?.serviceEndPoints = serverPoints!
//            if self?.activingEndpoint == nil {
//                self?.activingEndpoint = self?.serviceEndPoints.first
//                self?.updateConfig()
//            }
            
//            if completion != nil {
//                completion!(nil)
//            }
//        }
    }
    
    func storeServices() {
        guard let data = try? PropertyListEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: "VmessService")
        UserDefaults.standard.synchronize()
    }
    
    func loadServices() {
        guard let data = UserDefaults.standard.data(forKey: "VmessService") else { return }
        let viewModel = try? PropertyListDecoder().decode(SafeVPNViewModel.self, from: data)
//        self.serviceEndPoints = viewModel?.serviceEndPoints ?? []
//        self.activingEndpoint = viewModel?.activingEndpoint
        self.proxyMode = viewModel?.proxyMode ?? .auto
//        self.subscribeUrl = viewModel?.subscribeUrl
    }
}
*/

class SafeVPNViewModel: NSObject, Codable {
    var serviceOpen: Bool = false
    var subscribeUrl: URL? = nil
    var activingEndpoint: VmessEndpoint? = nil
    var serviceEndPoints: [VmessEndpoint] = []
    var proxyMode: ProxyMode = .auto
    var v2rayConfig: V2RayConfig = V2RayConfig.parse(fromJsonFile: "config")!
    
    enum CodingKeys: String, CodingKey {
        case subscribeUrl
        case activingEndpoint
        case serviceEndPoints
        case proxyMode
    }
    
    override init() {
        super.init()
        let array = ["vmess://eyJhZGQiOiJnYW1lc3BlZWQtdXMxLm51LW1hc3Rlci5jb20iLCJhaWQiOiIwIiwiaG9zdCI6IiIsImlkIjoiZTUxNDg1M2EtNGI3YS00MTYwLTk4N2EtNzEzYmIyNTc3N2I0IiwibmV0IjoidGNwIiwicGF0aCI6Ii8iLCJwb3J0IjoiMTE4NzIiLCJwcyI6IumBiuaIsuWKoOmAn1VTMSIsInRscyI6IiIsInR5cGUiOiJub25lIiwidiI6IjIifQ==", "vmess://eyJhZGQiOiJnYW1lc3BlZWQtc2cxLm51LW1hc3Rlci5jb20iLCJhaWQiOiIwIiwiaG9zdCI6ImdhbWVzcGVlZC1zZzEubnUtbWFzdGVyLmNvbSIsImlkIjoiZTUxNDg1M2EtNGI3YS00MTYwLTk4N2EtNzEzYmIyNTc3N2I0IiwibmV0IjoidGNwIiwicGF0aCI6Ii8iLCJwb3J0IjoiMTE4NzIiLCJwcyI6IumBiuaIsuWKoOmAn1NHIiwidGxzIjoiIiwidHlwZSI6Im5vbmUiLCJ2IjoiMiJ9"]
        self.serviceEndPoints = VmessEndpoint.generatePoints(with: array)
        if self.activingEndpoint == nil {
            self.activingEndpoint = self.serviceEndPoints.first
        }
        self.loadServices()
        self.updateConfig()
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        subscribeUrl != nil ? try container.encode(subscribeUrl?.absoluteString, forKey: .subscribeUrl) : nil
        activingEndpoint != nil ? try container.encode(activingEndpoint, forKey: .activingEndpoint) : nil
        try container.encode(proxyMode.rawValue, forKey: .proxyMode)
        try container.encode(serviceEndPoints, forKey: .serviceEndPoints)
    }
    
    required init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let string = values.contains(.subscribeUrl) ? try values.decode(String.self, forKey: .subscribeUrl) : nil
        subscribeUrl = string != nil ? URL.init(string: string!) : nil
        activingEndpoint = values.contains(.activingEndpoint) ? try values.decode(VmessEndpoint.self, forKey: .activingEndpoint) : nil
        proxyMode = ProxyMode(rawValue: try values.decode(Int.self, forKey: .proxyMode)) ?? .auto
        serviceEndPoints = try values.decode([VmessEndpoint].self, forKey: .serviceEndPoints)
    }
    
    func openService(completion: ((_ error: Error?)-> Void)?) {
        
        guard (self.activingEndpoint != nil) else {
            completion?(NSError(domain: "ErrorDomain", code: -1, userInfo: ["error" : "没有激活服务节点"]))
            return
        }
        
        let configData = try? JSONEncoder().encode(self.v2rayConfig)
        guard configData != nil else {
            completion?(NSError(domain: "ErrorDomain", code: -1, userInfo: ["error" : "配置错误"]))
            return
        }
        
        let serverIP = PacketTunnelMessage.getIPAddress(domainName: (self.v2rayConfig.outbounds?[0].settingVMess?.vnext[0].address)!)
        let packetTunnelMessage = PacketTunnelMessage(configData: configData, serverIP: serverIP)
        VPNHelper.shared.open(with: packetTunnelMessage, completion: {[weak self] (error) in
            guard error != nil else {
                self?.serviceOpen = true
                completion?(nil)
                return
            }
            
            completion?(error)
        })
    }
    
    func closeService(_ completion: (() -> Void)?) {
        VPNHelper.shared.close {[weak self] in
            self?.serviceOpen = false
            completion?()
        }
    }
    
    func updateConfig() {
        guard self.activingEndpoint != nil else {
            return
        }
        var vnext = Outbound.VMess.Item()
        vnext.address = self.activingEndpoint?.info[VmessEndpoint.InfoKey.address.stringValue] as! String
        vnext.users[0].id = self.activingEndpoint?.info[VmessEndpoint.InfoKey.uuid.stringValue] as! String
        vnext.users[0].alterId = (self.activingEndpoint?.info[VmessEndpoint.InfoKey.aid.stringValue] as? NSString)?.integerValue ?? 0
        vnext.port = (self.activingEndpoint?.info[VmessEndpoint.InfoKey.port.stringValue] as? NSString)?.integerValue ?? 0
        self.v2rayConfig.outbounds?[0].settingVMess?.vnext = [vnext]
    }
    
    func requestServices(withUrl requestUrl: URL?, completion: ((_ error: Error?)-> Void)?) {
//        guard let url = requestUrl else {
//            return
//        }

//        AirportTool.getSubscribeVmessPoints(url) {[weak self] (serverPoints, error) in
//            guard error == nil else {
//                if completion != nil {
//                    completion!(error)
//                }
//                return
//            }
//
//            self?.serviceEndPoints = serverPoints!
//            if self?.activingEndpoint == nil {
//                self?.activingEndpoint = self?.serviceEndPoints.first
//                self?.updateConfig()
//            }
//
//            if completion != nil {
//                completion!(nil)
//            }
//        }
        
    }
    
    func storeServices() {
        guard let data = try? PropertyListEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: "VmessService")
        UserDefaults.standard.synchronize()
    }
    
    func loadServices() {
        guard let data = UserDefaults.standard.data(forKey: "VmessService") else { return }
        let viewModel = try? PropertyListDecoder().decode(SafeVPNViewModel.self, from: data)
        self.serviceEndPoints = viewModel?.serviceEndPoints ?? []
        self.activingEndpoint = viewModel?.activingEndpoint
        self.proxyMode = viewModel?.proxyMode ?? .auto
        self.subscribeUrl = viewModel?.subscribeUrl
    }
    
}
