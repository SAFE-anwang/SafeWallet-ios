import Foundation
import EvmKit
import BigInt

class Safe4LineLockMethod: ContractMethod {
    override var methodSignature: String {
        "batchDeposit4One(address,uint256,uint256,uint256)"
    }
    
    let address: EvmKit.Address
    let times: BigUInt
    let spaceDay: BigUInt
    let startDay: BigUInt

    init(address: EvmKit.Address, times: BigUInt, spaceDay: BigUInt, startDay: BigUInt) {
        self.address = address
        self.times = times
        self.spaceDay = spaceDay
        self.startDay = startDay
    }
        
    override var arguments: [Any] {[address, times, spaceDay, startDay]}
}

extension Safe4LineLockMethod {
    static func createMethod(inputArguments: Data) throws -> ContractMethod {
        let parsedArguments = ContractMethodHelper.decodeABI(inputArguments: inputArguments, argumentTypes: [EvmKit.Address.self, BigUInt.self, BigUInt.self, BigUInt.self])
        guard let address = parsedArguments[0] as? EvmKit.Address,
              let times = parsedArguments[1] as? BigUInt,
              let spaceDay = parsedArguments[2] as? BigUInt,
              let startDay = parsedArguments[3] as? BigUInt else {
            throw ContractMethodFactories.DecodeError.invalidABI
        }
        return Safe4LineLockMethod(address: address, times: times, spaceDay: spaceDay, startDay: startDay)
    }
}
