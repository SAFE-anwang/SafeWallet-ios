import GRDB

class Safe4SRC20EnabledWalletRecord: Record {
    let accountId: String
    let chainId: Int
    let tokenQueryId: String
    let coinName: String?
    let coinCode: String?
    let coinImage: String?
    let tokenDecimals: Int?

    init(accountId: String, chainId: Int, tokenQueryId: String, coinName: String? = nil, coinCode: String? = nil, coinImage: String? = nil, tokenDecimals: Int? = nil) {
        self.accountId = accountId
        self.chainId = chainId
        self.tokenQueryId = tokenQueryId
        self.coinName = coinName
        self.coinCode = coinCode
        self.coinImage = coinImage
        self.tokenDecimals = tokenDecimals

        super.init()
    }

    convenience init(enabledWallet: EnabledWallet, chainId: Int) {
        self.init(
            accountId: enabledWallet.accountId,
            chainId: chainId,
            tokenQueryId: enabledWallet.tokenQueryId,
            coinName: enabledWallet.coinName,
            coinCode: enabledWallet.coinCode,
            coinImage: enabledWallet.coinImage,
            tokenDecimals: enabledWallet.tokenDecimals
        )
    }

    override class var databaseTableName: String {
        "safe4_src20_enabled_wallets"
    }

    enum Columns: String, ColumnExpression {
        case accountId, chainId, tokenQueryId, coinName, coinCode, coinImage, tokenDecimals
    }

    required init(row: Row) throws {
        accountId = row[Columns.accountId]
        chainId = row[Columns.chainId]
        tokenQueryId = row[Columns.tokenQueryId]
        coinName = row[Columns.coinName]
        coinCode = row[Columns.coinCode]
        coinImage = row[Columns.coinImage]
        tokenDecimals = row[Columns.tokenDecimals]

        try super.init(row: row)
    }

    override func encode(to container: inout PersistenceContainer) {
        container[Columns.accountId] = accountId
        container[Columns.chainId] = chainId
        container[Columns.tokenQueryId] = tokenQueryId
        container[Columns.coinName] = coinName
        container[Columns.coinCode] = coinCode
        container[Columns.coinImage] = coinImage
        container[Columns.tokenDecimals] = tokenDecimals
    }

    var enabledWallet: EnabledWallet {
        EnabledWallet(
            tokenQueryId: tokenQueryId,
            accountId: accountId,
            coinName: coinName,
            coinCode: coinCode,
            coinImage: coinImage,
            tokenDecimals: tokenDecimals
        )
    }
}
