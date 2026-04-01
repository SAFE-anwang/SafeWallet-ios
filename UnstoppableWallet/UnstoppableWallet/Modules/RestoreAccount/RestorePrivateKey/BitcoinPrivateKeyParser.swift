import BitcoinCore
import CryptoSwift
import Foundation
import HsCryptoKit
import Scrypt

enum BitcoinPrivateKeyFormat {
    case hex
    case wifMainNet
    case wifCompressedMainNet
    case wifTestNet
    case wifCompressedTestNet
    case bip38Encrypted
    case miniKey
    case brainWalletSingle
    case brainWalletDouble

    var displayName: String {
        switch self {
        case .hex: return "Hex Private Key"
        case .wifMainNet: return "WIF (Uncompressed MainNet)"
        case .wifCompressedMainNet: return "WIF (Compressed MainNet)"
        case .wifTestNet: return "WIF (TestNet)"
        case .wifCompressedTestNet: return "WIF (Compressed TestNet)"
        case .bip38Encrypted: return "BIP38 Encrypted"
        case .miniKey: return "Mini Private Key"
        case .brainWalletSingle: return "Brain Wallet (SHA256)"
        case .brainWalletDouble: return "Brain Wallet (Double SHA256)"
        }
    }
}

enum BitcoinKeyError: Error, LocalizedError {
    case invalidFormat
    case invalidHexLength
    case invalidWifChecksum
    case invalidWifPrefix
    case invalidMiniKeyLength
    case invalidMiniKeyChecksum
    case invalidBip38Format
    case invalidBip38Checksum
    case invalidBip38Key
    case invalidBrainWalletPassword
    case unsupportedFormat
    case decryptionFailed
    case invalidPrivateKey
    case addressGenerationFailed

    var errorDescription: String? {
        switch self {
        case .invalidFormat: return "Invalid private key format"
        case .invalidHexLength: return "Invalid hex private key length (expected 64 characters)"
        case .invalidWifChecksum: return "Invalid WIF checksum"
        case .invalidWifPrefix: return "Invalid WIF prefix"
        case .invalidMiniKeyLength: return "Invalid mini key length (must be 22, 26 or 30 characters)"
        case .invalidMiniKeyChecksum: return "Invalid mini key checksum"
        case .invalidBip38Format: return "Invalid BIP38 format"
        case .invalidBip38Checksum: return "Invalid BIP38 checksum"
        case .invalidBip38Key: return "Invalid BIP38 encrypted key"
        case .invalidBrainWalletPassword: return "Invalid brain wallet password"
        case .unsupportedFormat: return "Unsupported private key format"
        case .decryptionFailed: return "Decryption failed - invalid password"
        case .invalidPrivateKey: return "Invalid private key"
        case .addressGenerationFailed: return "Failed to generate address from private key"
        }
    }
}

struct BitcoinParsedPrivateKey {
    let privateKey: Data
    let format: BitcoinPrivateKeyFormat
    let isCompressed: Bool
    let isTestNet: Bool
}

class BitcoinPrivateKeyParser {
    private static let wifMainNetPrefix: UInt8 = 0x80
    private static let wifTestNetPrefix: UInt8 = 0xEF
    private static let compressedFlag: UInt8 = 0x01

    private static let bip38Prefix: UInt8 = 0x01
    private static let bip38NonEcMode: UInt8 = 0x42
    private static let bip38EcMode: UInt8 = 0x43

    private static let base58Alphabet = CharacterSet(charactersIn: "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz")
    private static let secp256k1Order = Data(hexString: "FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141")!
    private static let miniKeyAllowedLengths: Set<Int> = [22, 26, 30]

    static func detectFormat(_ input: String) -> BitcoinPrivateKeyFormat? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)

        if let explicit = detectExplicitFormat(trimmed) {
            return explicit
        }

        if isBrainWalletCandidate(trimmed) {
            return .brainWalletSingle
        }

        return nil
    }

    static func isBrainWalletCandidate(_ input: String) -> Bool {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)

        guard trimmed.count >= 16 else { return false }
        guard trimmed.rangeOfCharacter(from: .whitespacesAndNewlines) != nil else { return false }
        return detectExplicitFormat(trimmed) == nil
    }

    static func parsePrivateKey(_ input: String, format: BitcoinPrivateKeyFormat? = nil, bip38Password: String? = nil) throws -> Data {
        try parsePrivateKeyInfo(input, format: format, bip38Password: bip38Password).privateKey
    }

    static func parsePrivateKeyInfo(_ input: String, format: BitcoinPrivateKeyFormat? = nil, bip38Password: String? = nil) throws -> BitcoinParsedPrivateKey {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)

        let detectedFormat = format ?? detectFormat(trimmed)

        guard let keyFormat = detectedFormat else {
            throw BitcoinKeyError.invalidFormat
        }

        switch keyFormat {
        case .hex:
            let privateKey = try parseHexPrivateKey(trimmed)
            return BitcoinParsedPrivateKey(privateKey: privateKey, format: .hex, isCompressed: true, isTestNet: false)

        case .wifMainNet, .wifCompressedMainNet, .wifTestNet, .wifCompressedTestNet:
            return try decodeWif(trimmed)

        case .miniKey:
            let privateKey = try parseMiniKey(trimmed)
            return BitcoinParsedPrivateKey(privateKey: privateKey, format: .miniKey, isCompressed: false, isTestNet: false)

        case .bip38Encrypted:
            guard let bip38Password, !bip38Password.isEmpty else {
                throw BitcoinKeyError.decryptionFailed
            }
            return try decryptBip38PrivateKey(trimmed, password: bip38Password)

        case .brainWalletSingle, .brainWalletDouble:
            let privateKey = try parseBrainWallet(trimmed, doubleHash: keyFormat == .brainWalletDouble)
            return BitcoinParsedPrivateKey(privateKey: privateKey, format: keyFormat, isCompressed: false, isTestNet: false)
        }
    }

    static func generateBitcoinAddress(
        from privateKeyData: Data,
        compressed: Bool = true,
        testNet: Bool = false,
        scriptType: ScriptType = .p2pkh
    ) throws -> String {
        guard isValidPrivateKeyData(privateKeyData) else {
            throw BitcoinKeyError.invalidPrivateKey
        }

        let useCompressedPublicKey: Bool
        switch scriptType {
        case .p2pkh:
            useCompressedPublicKey = compressed
        case .p2wpkhSh, .p2wpkh, .p2tr:
            // SegWit/Taproot addresses are based on compressed public keys.
            useCompressedPublicKey = true
        default:
            throw BitcoinKeyError.addressGenerationFailed
        }

        let rawPublicKey = HsCryptoKit.Crypto.publicKey(privateKey: privateKeyData, compressed: useCompressedPublicKey)
        guard !rawPublicKey.isEmpty else {
            throw BitcoinKeyError.addressGenerationFailed
        }

        let publicKey = try PublicKey(withAccount: 0, index: 0, external: true, hdPublicKeyData: rawPublicKey)
        let addressString: String

        switch scriptType {
        case .p2pkh, .p2wpkhSh:
            let converter = Base58AddressConverter(
                addressVersion: testNet ? 0x6F : 0x00,
                addressScriptVersion: testNet ? 0xC4 : 0x05
            )
            addressString = try converter.convert(publicKey: publicKey, type: scriptType).stringValue
        case .p2wpkh, .p2tr:
            let converter = SegWitBech32AddressConverter(
                prefix: testNet ? "tb" : "bc",
                scriptConverter: ScriptConverter()
            )
            addressString = try converter.convert(publicKey: publicKey, type: scriptType).stringValue
        default:
            throw BitcoinKeyError.addressGenerationFailed
        }

        return addressString
    }

    static func decodeWif(_ input: String) throws -> BitcoinParsedPrivateKey {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let decoded = base58Decode(trimmed) else {
            throw BitcoinKeyError.invalidFormat
        }

        guard decoded.count == 37 || decoded.count == 38 else {
            throw BitcoinKeyError.invalidFormat
        }

        let payload = decoded.dropLast(4)
        let checksum = decoded.suffix(4)
        let expectedChecksum = HsCryptoKit.Crypto.doubleSha256(payload).prefix(4)

        guard checksum == expectedChecksum else {
            throw BitcoinKeyError.invalidWifChecksum
        }

        guard payload.count == 33 || payload.count == 34 else {
            throw BitcoinKeyError.invalidFormat
        }

        let prefix = payload[0]
        let isTestNet: Bool

        switch prefix {
        case wifMainNetPrefix:
            isTestNet = false
        case wifTestNetPrefix:
            isTestNet = true
        default:
            throw BitcoinKeyError.invalidWifPrefix
        }

        let privateKey = Data(payload[1 ..< 33])
        let isCompressed: Bool

        if payload.count == 34 {
            guard payload[33] == compressedFlag else {
                throw BitcoinKeyError.invalidFormat
            }
            isCompressed = true
        } else {
            isCompressed = false
        }

        guard isValidPrivateKeyData(privateKey) else {
            throw BitcoinKeyError.invalidPrivateKey
        }

        let format: BitcoinPrivateKeyFormat
        switch (isTestNet, isCompressed) {
        case (false, false): format = .wifMainNet
        case (false, true): format = .wifCompressedMainNet
        case (true, false): format = .wifTestNet
        case (true, true): format = .wifCompressedTestNet
        }

        return BitcoinParsedPrivateKey(privateKey: privateKey, format: format, isCompressed: isCompressed, isTestNet: isTestNet)
    }

    static func encodeToWif(_ privateKey: Data, compressed: Bool = false, testNet: Bool = false) -> String {
        guard privateKey.count == 32, isValidPrivateKeyData(privateKey) else { return "" }

        var payload = Data([testNet ? wifTestNetPrefix : wifMainNetPrefix])
        payload.append(privateKey)

        if compressed {
            payload.append(compressedFlag)
        }

        let checksum = HsCryptoKit.Crypto.doubleSha256(payload).prefix(4)
        payload.append(checksum)

        return Base58.encode(payload)
    }

    private static func detectExplicitFormat(_ input: String) -> BitcoinPrivateKeyFormat? {
        if isValidHexPrivateKey(input) {
            return .hex
        }

        if let parsed = try? decodeWif(input) {
            return parsed.format
        }

        if isValidMiniKey(input) {
            return .miniKey
        }

        if isValidBip38Key(input) {
            return .bip38Encrypted
        }

        return nil
    }

    private static func isValidHexPrivateKey(_ input: String) -> Bool {
        let normalized = normalizeHexPrivateKey(input)
        let hexChars = CharacterSet(charactersIn: "0123456789abcdefABCDEF")
        guard normalized.count == 64, normalized.unicodeScalars.allSatisfy({ hexChars.contains($0) }) else {
            return false
        }

        guard let data = Data(hexString: normalized) else { return false }
        return isValidPrivateKeyData(data)
    }

    private static func parseHexPrivateKey(_ input: String) throws -> Data {
        let normalized = normalizeHexPrivateKey(input)

        guard normalized.count == 64 else {
            throw BitcoinKeyError.invalidHexLength
        }

        guard let data = Data(hexString: normalized), isValidPrivateKeyData(data) else {
            throw BitcoinKeyError.invalidPrivateKey
        }

        return data
    }

    private static func normalizeHexPrivateKey(_ input: String) -> String {
        if input.hasPrefix("0x") || input.hasPrefix("0X") {
            return String(input.dropFirst(2))
        }
        return input
    }

    private static func isValidMiniKey(_ input: String) -> Bool {
        let miniKey = normalizedMiniKey(input)

        guard miniKey.first == "S" else { return false }
        guard miniKeyAllowedLengths.contains(miniKey.count) else { return false }
        guard miniKey.unicodeScalars.allSatisfy({ base58Alphabet.contains($0) }) else { return false }

        return validateMiniKeyChecksum(miniKey)
    }

    private static func normalizedMiniKey(_ input: String) -> String {
        input.hasSuffix("?") ? String(input.dropLast()) : input
    }

    private static func validateMiniKeyChecksum(_ miniKey: String) -> Bool {
        guard let checksumData = "\(miniKey)?".data(using: .utf8) else { return false }
        let checksumHash = HsCryptoKit.Crypto.sha256(checksumData)
        return checksumHash.first == 0x00
    }

    private static func parseMiniKey(_ input: String) throws -> Data {
        let miniKey = normalizedMiniKey(input)

        guard miniKeyAllowedLengths.contains(miniKey.count) else {
            throw BitcoinKeyError.invalidMiniKeyLength
        }

        guard validateMiniKeyChecksum(miniKey) else {
            throw BitcoinKeyError.invalidMiniKeyChecksum
        }

        guard let keyData = miniKey.data(using: .utf8) else {
            throw BitcoinKeyError.invalidFormat
        }

        let privateKey = HsCryptoKit.Crypto.sha256(keyData)

        guard isValidPrivateKeyData(privateKey) else {
            throw BitcoinKeyError.invalidPrivateKey
        }

        return privateKey
    }

    private static func isValidBip38Key(_ input: String) -> Bool {
        (try? bip38Payload(input)) != nil
    }

    private static func bip38Payload(_ key: String) throws -> Data {
        guard let decoded = base58Decode(key) else {
            throw BitcoinKeyError.invalidBip38Format
        }

        guard decoded.count == 43 else {
            throw BitcoinKeyError.invalidBip38Format
        }

        let payload = decoded.prefix(39)
        let checksum = decoded.suffix(4)
        let expectedChecksum = HsCryptoKit.Crypto.doubleSha256(payload).prefix(4)

        guard checksum == expectedChecksum else {
            throw BitcoinKeyError.invalidBip38Checksum
        }

        guard payload[0] == bip38Prefix, (payload[1] == bip38NonEcMode || payload[1] == bip38EcMode) else {
            throw BitcoinKeyError.invalidBip38Format
        }

        return Data(payload)
    }

    private static func decryptBip38PrivateKey(_ key: String, password: String) throws -> BitcoinParsedPrivateKey {
        let payload = try bip38Payload(key)

        // 0x01 0x42 -> non-EC multiplied (most common BIP38 form)
        guard payload[1] == bip38NonEcMode else {
            throw BitcoinKeyError.invalidBip38Key
        }

        let flag = payload[2]
        guard flag == 0xC0 || flag == 0xE0 else {
            throw BitcoinKeyError.invalidBip38Format
        }

        let isCompressed = (flag & 0x20) != 0
        let addressHash = Data(payload[3 ..< 7])
        let encryptedHalf1 = Data(payload[7 ..< 23])
        let encryptedHalf2 = Data(payload[23 ..< 39])

        let normalizedPassword = password.precomposedStringWithCanonicalMapping
        guard let passwordData = normalizedPassword.data(using: .utf8) else {
            throw BitcoinKeyError.invalidBip38Key
        }

        do {
            let derived = try scrypt(password: passwordData, salt: addressHash, dkLen: 64, N: 16384, r: 8, p: 8)
            let derivedHalf1 = Data(derived[0 ..< 32])
            let derivedHalf2 = Data(derived[32 ..< 64])

            let decryptedHalf1 = try aes256EcbDecrypt(encryptedHalf1, key: derivedHalf2)
            let decryptedHalf2 = try aes256EcbDecrypt(encryptedHalf2, key: derivedHalf2)

            let privateHalf1 = xor(decryptedHalf1, Data(derivedHalf1[0 ..< 16]))
            let privateHalf2 = xor(decryptedHalf2, Data(derivedHalf1[16 ..< 32]))
            let privateKey = privateHalf1 + privateHalf2

            guard isValidPrivateKeyData(privateKey) else {
                throw BitcoinKeyError.decryptionFailed
            }

            let address = try generateBitcoinAddress(from: privateKey, compressed: isCompressed, testNet: false)
            let actualAddressHash = HsCryptoKit.Crypto.doubleSha256(Data(address.utf8)).prefix(4)

            guard actualAddressHash == addressHash else {
                throw BitcoinKeyError.decryptionFailed
            }

            return BitcoinParsedPrivateKey(privateKey: privateKey, format: .bip38Encrypted, isCompressed: isCompressed, isTestNet: false)
        } catch let error as BitcoinKeyError {
            throw error
        } catch {
            throw BitcoinKeyError.decryptionFailed
        }
    }

    private static func parseBrainWallet(_ password: String, doubleHash: Bool) throws -> Data {
        guard let passwordData = password.data(using: .utf8), !passwordData.isEmpty else {
            throw BitcoinKeyError.invalidBrainWalletPassword
        }

        var hash = HsCryptoKit.Crypto.sha256(passwordData)

        if doubleHash {
            hash = HsCryptoKit.Crypto.sha256(hash)
        }

        guard isValidPrivateKeyData(hash) else {
            throw BitcoinKeyError.invalidPrivateKey
        }

        return hash
    }

    private static func base58Decode(_ input: String) -> Data? {
        guard !input.isEmpty else { return nil }
        guard input.unicodeScalars.allSatisfy({ base58Alphabet.contains($0) }) else { return nil }

        let decoded = Base58.decode(input)
        return decoded.isEmpty ? nil : decoded
    }

    private static func scrypt(password: Data, salt: Data, dkLen: Int, N: Int, r: Int, p: Int) throws -> Data {
        let params = try Scrypt(password: password.bytes, salt: salt.bytes, dkLen: dkLen, N: N, r: r, p: p)
        return Data(try params.calculate())
    }

    private static func aes256EcbDecrypt(_ data: Data, key: Data) throws -> Data {
        guard key.count == 32, data.count % AES.blockSize == 0 else {
            throw BitcoinKeyError.invalidBip38Key
        }

        let aes = try AES(key: key.bytes, blockMode: ECB(), padding: .noPadding)
        return Data(try aes.decrypt(data.bytes))
    }

    private static func xor(_ lhs: Data, _ rhs: Data) -> Data {
        Data(zip(lhs, rhs).map { $0 ^ $1 })
    }

    private static func isValidPrivateKeyData(_ privateKey: Data) -> Bool {
        guard privateKey.count == 32 else { return false }
        guard privateKey.contains(where: { $0 != 0 }) else { return false }

        for (lhs, rhs) in zip(privateKey, secp256k1Order) {
            if lhs < rhs { return true }
            if lhs > rhs { return false }
        }

        return false
    }
}

extension Data {
    init?(hexString: String) {
        let len = hexString.count / 2
        var data = Data(capacity: len)
        var index = hexString.startIndex

        for _ in 0 ..< len {
            let nextIndex = hexString.index(index, offsetBy: 2)
            guard let byte = UInt8(hexString[index ..< nextIndex], radix: 16) else { return nil }
            data.append(byte)
            index = nextIndex
        }

        self = data
    }

    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
