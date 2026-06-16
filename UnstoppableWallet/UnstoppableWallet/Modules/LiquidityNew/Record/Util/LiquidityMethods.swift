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

class GetToken0Method: ContractMethod {
    override var methodSignature: String { "token0()" }
    override var arguments: [Any] { [] }
}

class GetToken1Method: ContractMethod {
    override var methodSignature: String { "token1()" }
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

class AddLiquidityMethod: ContractMethod {
    static let methodSignature = "addLiquidity(address,address,uint256,uint256,uint256,uint256,address,uint256)"

    let tokenA: EvmKit.Address
    let tokenB: EvmKit.Address
    let amountADesired: BigUInt
    let amountBDesired: BigUInt
    let amountAMin: BigUInt
    let amountBMin: BigUInt
    let to: EvmKit.Address
    let deadline: BigUInt

    init(tokenA: EvmKit.Address, tokenB: EvmKit.Address, amountADesired: BigUInt, amountBDesired: BigUInt, amountAMin: BigUInt, amountBMin: BigUInt, to: EvmKit.Address, deadline: BigUInt) {
        self.tokenA = tokenA
        self.tokenB = tokenB
        self.amountADesired = amountADesired
        self.amountBDesired = amountBDesired
        self.amountAMin = amountAMin
        self.amountBMin = amountBMin
        self.to = to
        self.deadline = deadline
        super.init()
    }

    override var methodSignature: String { AddLiquidityMethod.methodSignature }

    override var arguments: [Any] {
        [tokenA, tokenB, amountADesired, amountBDesired, amountAMin, amountBMin, to, deadline]
    }
}

class AddLiquidityEthMethod: ContractMethod {
    static let methodSignature = "addLiquidityETH(address,uint256,uint256,uint256,address,uint256)"

    let token: EvmKit.Address
    let amountTokenDesired: BigUInt
    let amountTokenMin: BigUInt
    let amountEthMin: BigUInt
    let to: EvmKit.Address
    let deadline: BigUInt

    init(token: EvmKit.Address, amountTokenDesired: BigUInt, amountTokenMin: BigUInt, amountEthMin: BigUInt, to: EvmKit.Address, deadline: BigUInt) {
        self.token = token
        self.amountTokenDesired = amountTokenDesired
        self.amountTokenMin = amountTokenMin
        self.amountEthMin = amountEthMin
        self.to = to
        self.deadline = deadline
        super.init()
    }

    override var methodSignature: String { AddLiquidityEthMethod.methodSignature }

    override var arguments: [Any] {
        [token, amountTokenDesired, amountTokenMin, amountEthMin, to, deadline]
    }
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
    let approveMax: BigUInt
    let v: BigUInt
    let r: BigUInt
    let s: BigUInt
    
    init(tokenA: EvmKit.Address, tokenB: EvmKit.Address, liquidity: BigUInt, amountAMin: BigUInt, amountBMin: BigUInt, to: EvmKit.Address, deadline: BigUInt, approveMax: Bool, v: BigUInt, r: Data, s: Data) {
        self.tokenA = tokenA
        self.tokenB = tokenB
        self.liquidity = liquidity
        self.amountAMin = amountAMin
        self.amountBMin = amountBMin
        self.to = to
        self.deadline = deadline
        self.approveMax = approveMax ? 1 : 0
        self.v = v
        self.r = BigUInt(r)
        self.s = BigUInt(s)
        super.init()
    }

    override var methodSignature: String { RemoveLiquidityWithPermitMethod.methodSignature }

    override var arguments: [Any] {
        [tokenA, tokenB, liquidity, amountAMin, amountBMin, to, deadline, approveMax, v, r, s]
    }
}

class RemoveLiquidityEthMethod: ContractMethod {
    static let methodSignature = "removeLiquidityETH(address,uint256,uint256,uint256,address,uint256)"

    let token: EvmKit.Address
    let liquidity: BigUInt
    let amountTokenMin: BigUInt
    let amountEthMin: BigUInt
    let to: EvmKit.Address
    let deadline: BigUInt

    init(token: EvmKit.Address, liquidity: BigUInt, amountTokenMin: BigUInt, amountEthMin: BigUInt, to: EvmKit.Address, deadline: BigUInt) {
        self.token = token
        self.liquidity = liquidity
        self.amountTokenMin = amountTokenMin
        self.amountEthMin = amountEthMin
        self.to = to
        self.deadline = deadline
        super.init()
    }

    override var methodSignature: String { RemoveLiquidityEthMethod.methodSignature }

    override var arguments: [Any] {
        [token, liquidity, amountTokenMin, amountEthMin, to, deadline]
    }
}

class RemoveLiquidityEthWithPermitMethod: ContractMethod {
    static let methodSignature = "removeLiquidityETHWithPermit(address,uint256,uint256,uint256,address,uint256,bool,uint8,bytes32,bytes32)"

    let token: EvmKit.Address
    let liquidity: BigUInt
    let amountTokenMin: BigUInt
    let amountEthMin: BigUInt
    let to: EvmKit.Address
    let deadline: BigUInt
    let approveMax: BigUInt
    let v: BigUInt
    let r: BigUInt
    let s: BigUInt

    init(token: EvmKit.Address, liquidity: BigUInt, amountTokenMin: BigUInt, amountEthMin: BigUInt, to: EvmKit.Address, deadline: BigUInt, approveMax: Bool, v: BigUInt, r: Data, s: Data) {
        self.token = token
        self.liquidity = liquidity
        self.amountTokenMin = amountTokenMin
        self.amountEthMin = amountEthMin
        self.to = to
        self.deadline = deadline
        self.approveMax = approveMax ? 1 : 0
        self.v = v
        self.r = BigUInt(r)
        self.s = BigUInt(s)
        super.init()
    }

    override var methodSignature: String { RemoveLiquidityEthWithPermitMethod.methodSignature }

    override var arguments: [Any] {
        [token, liquidity, amountTokenMin, amountEthMin, to, deadline, approveMax, v, r, s]
    }
}

class ApproveMethod: ContractMethod {
    static let methodSignature = "approve(address,uint256)"

    let spender: EvmKit.Address
    let value: BigUInt

    init(spender: EvmKit.Address, value: BigUInt) {
        self.spender = spender
        self.value = value

        super.init()
    }

    override var methodSignature: String { ApproveMethod.methodSignature }
    override var arguments: [Any] { [spender, value] }
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
    let `operator`: EvmKit.Address
    let approved: BigUInt
    
    init(operator: EvmKit.Address, approved: Bool) {
        self.operator = `operator`
        self.approved = approved ? 1 : 0
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

class MulticallMethod: ContractMethod {
    static let methodSignature = "multicall(bytes[])"

    let methods: [ContractMethod]

    init(methods: [ContractMethod]) {
        self.methods = methods
        super.init()
    }

    override var methodSignature: String { MulticallMethod.methodSignature }

    override var arguments: [Any] {
        [ContractMethodHelper.MulticallParameters(methods.map { $0.encodedABI() })]
    }
}
