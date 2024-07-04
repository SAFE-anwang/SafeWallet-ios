import Foundation
import EvmKit
import BigInt

class GetNameMethod: ContractMethod {
    override var methodSignature: String { "name()" }
    override var arguments: [Any] { [] }
}

class GetNoncesMethod: ContractMethod {
    override var methodSignature: String { "nonces(address)" }
    let address: EvmKit.Address
    
    init(address: EvmKit.Address) {
        self.address = address
        super.init()
    }
    
    override var arguments: [Any] {
        [address]
    }
}

class GetReservesMethod: ContractMethod {
    override var methodSignature: String { "getReserves()" }
    override var arguments: [Any] { [] }
}

class GetBalanceOfMethod: ContractMethod {
    override var methodSignature: String { "balanceOf(address)" }
    let address: EvmKit.Address
    
    init(address: EvmKit.Address) {
        self.address = address
        super.init()
    }
    
    override var arguments: [Any] {
        [address]
    }
}

class GetTotalSupplyMethod: ContractMethod {
    override var methodSignature: String { "totalSupply()" }
    override var arguments: [Any] { [] }
}

class DomainSeparatorMethod: ContractMethod {
    override var methodSignature: String { "DOMAIN_SEPARATOR()" }
    override var arguments: [Any] { [] }
}

class PermitTypeHashMethod: ContractMethod {
    override var methodSignature: String { "PERMIT_TYPEHASH()" }
    override var arguments: [Any] { [] }
}

class RemoveLiquidityMethod: ContractMethod {
    static let methodSignature = "removeLiquidity(address,address,uint256,uint256,uint256,address,uint256)"

    let tokenA: EvmKit.Address
    let tokenB: EvmKit.Address
    let liquidity: BigUInt
    let amountAMin: BigUInt
    let amountBMin: BigUInt
    let to: EvmKit.Address
    let deadline: BigUInt
    
    init(tokenA: EvmKit.Address, tokenB: EvmKit.Address, liquidity: BigUInt, amountAMin: BigUInt, amountBMin: BigUInt, to: EvmKit.Address, deadline: BigUInt) {
        self.tokenA = tokenA
        self.tokenB = tokenB
        self.liquidity = liquidity
        self.amountAMin = amountAMin
        self.amountBMin = amountBMin
        self.to = to
        self.deadline = deadline
        super.init()
    }

    override var methodSignature: String { RemoveLiquidityMethod.methodSignature }

    override var arguments: [Any] {
        [tokenA, tokenB, liquidity, amountAMin, amountBMin, to, deadline]
    }
}

class RemoveLiquidityWithPermitMethod: ContractMethod {
    static let methodSignature = "removeLiquidityWithPermit(address,address,uint256,uint256,uint256,address,uint256,bool,uint8,bytes32,bytes32)"

    let tokenA: EvmKit.Address
    let tokenB: EvmKit.Address
    let liquidity: BigUInt
    let amountAMin: BigUInt
    let amountBMin: BigUInt
    let to: EvmKit.Address
    let deadline: BigUInt
    let approveMax: String
    let v: BigUInt
    let r: BigUInt
    let s: BigUInt
    
    init(tokenA: EvmKit.Address, tokenB: EvmKit.Address, liquidity: BigUInt, amountAMin: BigUInt, amountBMin: BigUInt, to: EvmKit.Address, deadline: BigUInt, approveMax: Bool, v: BigUInt, r: BigUInt, s: BigUInt) {
        self.tokenA = tokenA
        self.tokenB = tokenB
        self.liquidity = liquidity
        self.amountAMin = amountAMin
        self.amountBMin = amountBMin
        self.to = to
        self.deadline = deadline
        self.approveMax = approveMax ? "1" : "0"
        self.v = v
        self.r = r
        self.s = s
        super.init()
    }

    override var methodSignature: String { RemoveLiquidityWithPermitMethod.methodSignature }

    override var arguments: [Any] {
        [tokenA, tokenB, liquidity, amountAMin, amountBMin, to, deadline, approveMax, v, r, s]
    }

}

class ApproveMethod: ContractMethod {
    private let to: EvmKit.Address
    private let tokenId: BigUInt
    
    init(to: EvmKit.Address, tokenId: BigUInt) {
        self.to = to
        self.tokenId = tokenId
    }

    override var methodSignature: String {
        "approve(address,uint256)"
    }

    override var arguments: [Any] {
        [to, tokenId]
    }
}

class GetApprovedMethod: ContractMethod {
    private let tokenId: BigUInt
    
    init(tokenId: BigUInt) {
        self.tokenId = tokenId
    }

    override var methodSignature: String {
        "getApproved(uint256)"
    }

    override var arguments: [Any] {
        [tokenId]
    }
}

class ApprovalForAllMethod: ContractMethod {
    private let `operator`: EvmKit.Address
    private let approved: BigUInt
    
    init(operator: EvmKit.Address, approved: BigUInt) {
        self.operator = `operator`
        self.approved = approved
    }

    override var methodSignature: String {
        "setApprovalForAll(address,bool)"
    }

    override var arguments: [Any] {
        [`operator`, approved]
    }
}

class IsApprovalForAllMethod: ContractMethod {
    private let owner: EvmKit.Address
    private let `operator`: EvmKit.Address
    
    init(owner: EvmKit.Address, operator: EvmKit.Address) {
        self.owner = owner
        self.operator = `operator`
    }

    override var methodSignature: String {
        "isApprovedForAll(address,address)"
    }

    override var arguments: [Any] {
        [owner,`operator`]
    }
}

class AllowanceMethod: ContractMethod {
    private let owner: EvmKit.Address
    private let spender: EvmKit.Address
    
    init(owner: EvmKit.Address, spender: EvmKit.Address) {
        self.owner = owner
        self.spender = spender
    }

    override var methodSignature: String {
        "allowance(address,address)"
    }

    override var arguments: [Any] {
        [owner, spender]
    }
}

class OwnerOfMethod: ContractMethod {
    private let tokenId: BigUInt
    
    init(tokenId: BigUInt) {
        self.tokenId = tokenId
    }

    override var methodSignature: String {
        "ownerOf(uint256)"
    }

    override var arguments: [Any] {
        [tokenId]
    }
}
