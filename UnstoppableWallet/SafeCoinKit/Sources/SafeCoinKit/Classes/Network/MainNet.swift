import Foundation
import BitcoinCore
import HsExtensions
import Checkpoints

public class MainNet: INetwork {
    public let protocolVersion: Int32 = 70210

    public let bundleName = "Safe"

    public let maxBlockSize: UInt32 = 2_000_000_000
    public let pubKeyHash: UInt8 = 0x4c
    public let privateKey: UInt8 = 0x80
    public let scriptHash: UInt8 = 0x10
    public let bech32PrefixPattern: String = "bc"
    public let xPubKey: UInt32 = 0x0488b21e
    public let xPrivKey: UInt32 = 0x0488ade4
    public let magic: UInt32 = 0x62696ecc
    public let port = 5555
    public let coinType: UInt32 = 5
    public let sigHash: SigHashType = .bitcoinAll
    public var syncableFromApi: Bool = true
    public let dnsSeeds = //["114.215.31.37"]
    ["39.104.90.76","47.89.208.160","120.78.227.96","47.96.254.235","106.14.66.206","47.88.247.232","114.215.31.37","47.75.17.223","47.52.9.168","47.74.13.245","39.104.200.133","192.53.112.232","172.105.209.98","139.162.10.148","172.104.64.127","172.104.175.215","139.162.19.251","139.162.108.93","194.195.213.226","192.46.217.199","23.239.22.221","172.105.112.33","172.104.110.221","139.162.24.250","172.104.28.167","172.105.235.94","172.105.6.192","172.105.24.28","139.162.196.118","212.111.40.32","139.162.142.45","192.46.232.91","45.79.122.221","192.46.213.88","194.195.120.218","45.79.239.211","172.105.194.112","172.104.40.33","172.105.216.132","139.162.98.168","172.104.50.182","139.162.20.107","172.104.41.183","172.104.53.213","172.105.112.125","172.105.196.229","139.162.123.100","139.162.103.9","172.105.201.79","172.104.85.174"]

    public let dustRelayTxFee = 1000
    
    public var bip44Checkpoint: Checkpoint {
        try! getCheckpoint(bundleName: bundleName, network: .main, blockType: .bip44)
    }

    public var lastCheckpoint: Checkpoint {
        try! getCheckpoint(bundleName: bundleName, network: .main, blockType: .last)
    }

    public init() {}

    // 参考 CheckpointData init 方法实现
    private func getCheckpoint(bundleName: String, network: CheckpointData.Network, blockType: CheckpointData.BlockType) throws -> Checkpoint {
        var checkpoint: String?
        switch blockType {
        case .bip44:
            checkpoint =  "00000020825bf0aeb3b45ee3f1888ae2c4c64da19b332d7281d8a0b3f4ecf248b2699ea399e9e696fe774676381894ee6483c0b057aad8630822b370cd84ede5d50d88f576aa625af0ff0f1ea9e40600ae500c00e920f497c5492aba1c5fa8badbccff0ebd04a1db0903d20b1c57c5e968060000"
        case .last:
            checkpoint =  "00000020366538f586d460d4339b7172c863dbd92648891d1e0523b79c0cfef937f25c47fd79850f1ebf2e8dd2aa2a746e5b473a6ebee600218c725dc0f819c209cbdd52183bd96300000000160c50068de845000c55c274d2942e417d792abe9054088db4dfc75d39f1a14bd6ff64262d12a69f"
        }
        
        guard let  string = checkpoint else {
            throw CheckpointData.ParseError.invalidUrl
        }
        var lines = string.components(separatedBy: .newlines).filter { !$0.isEmpty }
        guard !lines.isEmpty else {
            throw CheckpointData.ParseError.invalidFile
        }

        guard let block = lines.removeFirst().hs.hexData else {
            throw CheckpointData.ParseError.invalidFile
        }

        var additionalBlocks = [Data]()
        for line in lines {
            guard let additionalData = line.hs.hexData else {
                throw CheckpointData.ParseError.invalidFile
            }
            additionalBlocks.append(additionalData)
        }
        
        let pBlock = try readBlock(data: block)
        let pAdditionalBlocks = try additionalBlocks.map { try readBlock(data: $0) }
        
        return Checkpoint(block: pBlock, additionalBlocks: pAdditionalBlocks)
    }
    
    ///照搬 Checkpoint类中同名方法
    private func readBlock(data: Data) throws -> Block {
        let byteStream = ByteStream(data)

        let version = Int(byteStream.read(Int32.self))
        let previousBlockHeaderHash = byteStream.read(Data.self, count: 32)
        let merkleRoot = byteStream.read(Data.self, count: 32)
        let timestamp = Int(byteStream.read(UInt32.self))
        let bits = Int(byteStream.read(UInt32.self))
        let nonce = Int(byteStream.read(UInt32.self))
        let height = Int(byteStream.read(UInt32.self))
        let headerHash = byteStream.read(Data.self, count: 32)

        let header = BlockHeader(
                version: version,
                headerHash: headerHash,
                previousBlockHeaderHash: previousBlockHeaderHash,
                merkleRoot: merkleRoot,
                timestamp: timestamp,
                bits: bits,
                nonce: nonce
        )
        return Block(withHeader: header, height: height)
    }
}
