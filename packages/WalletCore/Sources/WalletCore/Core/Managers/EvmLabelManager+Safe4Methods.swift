import EvmKit

extension EvmLabelManager {
    enum ExSafe4Methods: CaseIterable {
        case addLiquidity
        case addEthLiquidity
        case dereaseLiquidity
        case removeLiquidity
        case removeLiquidityPermit
        case lineLock
        case promotion
        case deploy_0
        case deploy_1
        case destroy
        case removeVote
        case src20Lock
        case usdtCross
        case usdtCrossToSafe
        case lockRedeem1
        case lockRedeem2
        case lockRedeem3
        case lockRedeem4
        case registerMN
        case swapExIn
        case nftMint
        case nftSend
        case collect
        case approve
        case setDescription
        case setBaseURI
        case dappPromotion
        case dappDestroy
        case dappCreation
        case dappUpdateInfo
        case dappUpdateInfoAlternate
        case dappUpdateInfoLegacy

        var id: String {
            switch self {
            case .addLiquidity: "0xe8e33700"
            case .addEthLiquidity: "0xf305d719"
            case .dereaseLiquidity: "0x0c49ccbe"
            case .removeLiquidity: "0xbaa2abde"
            case .removeLiquidityPermit: "0x2195995c"
            case .lineLock: "0x9c4ee6bf"
            case .promotion: "0x198581a5"
            case .deploy_0: "0x40c10f19"
            case .deploy_1: "0x61016060"
            case .destroy: "0x42966c68"
            case .removeVote : "0x9fbe5cc5"
            case .src20Lock: "0x4b86c225"
            case .usdtCross: "0x49530e18"
            case .usdtCrossToSafe: "0xa9059cbb"
            case .lockRedeem1: "0xd885085f"
            case .lockRedeem2: "0x4c9e906a"
            case .lockRedeem3: "0x43594feb"
            case .lockRedeem4: "0x6d5b08d3"
            case .registerMN: "0x082ed4d5"
            case .swapExIn: "0xedad400c"
            case .nftMint: "0xe58306f9"
            case .nftSend: "0x42842e0e"
            case .collect: "0xfc6f7865"
            case .approve: "0x87517c45"
            case .setDescription: "0x90c3f38f"
            case .setBaseURI: "0x55f804b3"
            case .dappPromotion: "0x6b29297f"
            case .dappDestroy: "0x4cc82215"
            case .dappCreation: "0x45a36e76"
            case .dappUpdateInfo: "0x2a6446ca"
            case .dappUpdateInfoAlternate: "0x4c78529e"
            case .dappUpdateInfoLegacy: "0xd62d311f"
            }
        }

        var title: String {
            switch self {
            case .addLiquidity, .addEthLiquidity: "liquidity.title.add".localized
            case .removeLiquidity, .removeLiquidityPermit, .dereaseLiquidity: "liquidity.remove".localized
            case .lineLock: "safe_zone.row.linear".localized
            case .promotion: "SRC20_Info_Promotion".localized
            case .deploy_0, .deploy_1: "SRC20_Deploy_Title".localized
            case .destroy: "SRC20_Info_Destroy".localized
            case .removeVote: "safe_zone.vote_release".localized
            case .src20Lock: "SRC20_lock".localized
            case .usdtCross, .usdtCrossToSafe: "safe_zone.cross_chain".localized
            case .lockRedeem1, .lockRedeem2, .lockRedeem3, .lockRedeem4: "safe_zone.locked_balance_migration".localized
            case .registerMN: "safe_zone.register_master_node".localized
            case .swapExIn: "transactions.types.swap".localized
            case .nftMint: "add_token.NFT.mint".localized
            case .nftSend: "alert.sent".localized
            case .collect: "liquidity.collect_fees".localized
            case .approve: "button.approve".localized
            case .setDescription, .setBaseURI: "safe_zone.src721.transaction.update_nft_info".localized
            case .dappPromotion: "safe_zone.src721.transaction.dapp.promotion".localized
            case .dappDestroy: "safe_zone.src721.transaction.dapp.destroy".localized
            case .dappCreation: "safe_zone.src721.transaction.dapp.creation".localized
            case .dappUpdateInfo: "safe_zone.src721.transaction.dapp.update_info".localized
            case .dappUpdateInfoAlternate: "safe_zone.src721.transaction.dapp.update_info".localized
            case .dappUpdateInfoLegacy: "safe_zone.src721.transaction.dapp.update_info".localized
            }
        }
    }
}

extension EvmKit.Safe4Methods {

    var title: String {
        switch self {
        case .AppendRegister: "safe_zone.safe4.appendRegister".localized
        case .Withdraw: "safe_zone.safe4.withdraw".localized
        case .WithdrawByID: "safe_zone.safe4.WithdrawByID".localized
        case .CreateProposal: "safe_zone.safe4.CreateProposal".localized
        case .VoteSuperNode: "safe_zone.safe4.VoteSuperNode".localized
        case .MasterNodeRegister: "safe_zone.safe4.MasterNodeRegister".localized
        case .SuperNodeRegister: "safe_zone.safe4.SuperNodeRegister".localized
        case .NodeUpdateDesc: "safe_zone.safe4.NodeUpdate".localized
        case .NodeUpdateEnode: "safe_zone.safe4.NodeUpdate".localized
        case .NodeUpdateName: "safe_zone.safe4.NodeUpdate".localized
        case .NodeUpdateAddress: "safe_zone.safe4.NodeUpdate".localized
        case .LockVote: "safe_zone.safe4.lockVote".localized
        case .Reward: "safe_zone.safe4.reward".localized
        case .RedeemMsaternode: "safe_zone.safe4.redeem.msaternode".localized
        case .RedeemLocked: "safe_zone.safe4.redeem.locked".localized
        case .RedeemAvailable: "safe_zone.safe4.redeem.available".localized
        case .NodeStateUpload: "safe_zone.safe4.node.state.upload".localized
        case .ProposalVote: "safe_zone.safe4.ProposalVote".localized
        case .ContractDeployment: "safe_zone.safe4.contract.deployment".localized
        case .AddLockDay: "safe_zone.safe4.contract.addlockday".localized
        case .BatchRedeemLocked: "safe_zone.safe4.contract.batchRedeem.locked".localized
        case .BatchRedeemAvailable: "safe_zone.safe4.contract.batchRedeem.available".localized
        case .Eth2safe: "safe_zone.safe4.contract.crossChain".localized
        case .safe4ToBsc, .safe4ToEth, .safe4ToPol, .bscToSafe4, .ethToSafe4, .polToSafe4: "safe_zone.safe4.contract.crossChain".localized
        case .Safe4SwapSrc, .SrcSwapSafe4: "swap.safe4.title".localized
        }
    }
}
