import BigInt
import Testing
@testable import WalletCore

struct MarketDappServiceTests {
    @Test func doesNotFilterSafeDappData() {
        let shortDescription = makeDapp(name: "Example SAFE Dapp", desc: "B", descEN: "D")
        let suspiciousSafeName = makeDapp(name: "i2553probe888")

        let result = MarketDappProvider.filterGetAllDapps([shortDescription, suspiciousSafeName])

        #expect(result.map(\.name) == ["Example SAFE Dapp", "i2553probe888"])
        #expect(MarketDappService.isDisplayable(shortDescription))
        #expect(MarketDappService.isDisplayable(suspiciousSafeName))
    }

    @Test func keepsValidSafeDappsAndOtherMarketEntries() {
        let validSafeDapp = makeDapp(name: "Example SAFE Dapp")
        let ordinaryMarketDapp = makeDapp(
            type: "BSC",
            subType: "DEX",
            name: "AAVE",
            desc: "B",
            descEN: "",
            contractAddress: nil,
            safeDappId: nil
        )

        #expect(MarketDappService.isDisplayable(validSafeDapp))
        #expect(MarketDappService.isDisplayable(ordinaryMarketDapp))
    }

    @Test func mergesSafeDappsWithoutDuplicatingApiEntries() {
        let apiDapp = makeDapp(type: "ETH", subType: "DEX", name: "AAVE", safeDappId: nil)
        let duplicateSafeDapp = makeDapp(name: "AAVE")
        let additionalSafeDapp = makeDapp(name: "Safe Portal")

        let result = MarketDappService.merge(
            apiDapps: [apiDapp],
            safeDapps: [duplicateSafeDapp, additionalSafeDapp]
        )

        #expect(result.map(\.name) == ["AAVE", "Safe Portal"])
    }

    @Test func filtersOnlySuspiciousNonSafeDappsFromGetAllData() {
        let probeDapp = makeDapp(
            type: "TEST",
            subType: "TEST",
            name: "i2553probe888",
            desc: "B",
            descEN: "",
            chainId: nil,
            contractAddress: nil,
            safeDappId: nil
        )
        let malformedBaseDapp = makeDapp(
            type: "T",
            subType: "T",
            name: "i2738f_base",
            desc: "D",
            descEN: "",
            chainId: nil,
            contractAddress: nil,
            safeDappId: nil
        )
        let sqlInjectionDapp = makeDapp(
            type: "T",
            subType: "T",
            name: "i2738i_sl' AND SLEEP(2)-- -",
            desc: "D",
            descEN: "",
            chainId: nil,
            contractAddress: nil,
            safeDappId: nil
        )
        let probeWithoutSuffixDapp = makeDapp(
            type: "TEST",
            subType: "TEST",
            name: "i2553probe",
            chainId: nil,
            contractAddress: nil,
            safeDappId: nil
        )
        let safeChainProbeDapp = makeDapp(
            type: "ETH",
            subType: "DEX",
            name: "i2738f_base",
            chainId: String(Safe4Network.chainId(testNet: false)),
            contractAddress: nil,
            safeDappId: nil
        )
        let aave = makeDapp(
            type: "ETH",
            subType: "DEX",
            name: "AAVE",
            chainId: nil,
            contractAddress: nil,
            safeDappId: nil
        )
        let compound = makeDapp(
            type: "ETH",
            subType: "DEX",
            name: "Compound",
            chainId: nil,
            contractAddress: nil,
            safeDappId: nil
        )
        let pancakeswap = makeDapp(
            type: "BSC",
            subType: "DEX",
            name: "PancakeSwap",
            chainId: "56",
            contractAddress: nil,
            safeDappId: nil
        )

        let filtered = MarketDappProvider.filterGetAllDapps([
            probeDapp,
            malformedBaseDapp,
            sqlInjectionDapp,
            probeWithoutSuffixDapp,
            safeChainProbeDapp,
            aave,
            compound,
            pancakeswap,
        ])

        #expect(filtered.map(\.name) == ["AAVE", "Compound", "PancakeSwap"])
    }

    private func makeDapp(
        type: String = "SAFE",
        subType: String = "SAFE DAPP",
        name: String,
        desc: String = "A valid SAFE DApp description.",
        descEN: String = "A valid SAFE DApp description.",
        chainId: String? = nil,
        contractAddress: String? = "0x1111111111111111111111111111111111111111",
        safeDappId: BigUInt? = BigUInt(1)
    ) -> MarktDapp {
        MarktDapp(
            type: type,
            subType: subType,
            name: name,
            desc: desc,
            descEN: descEN,
            icon: "",
            dlink: "https://example.org/app",
            md5Code: "1",
            chainId: chainId,
            safeDappId: safeDappId,
            safeDappContractAddr: contractAddress
        )
    }
}
