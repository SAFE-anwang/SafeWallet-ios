import BigInt
import EvmKit
import Foundation
import HsExtensions
import MarketKit
import RxCocoa
import RxSwift
import SectionsTableView
import SnapKit
import UIExtensions
import UIKit

enum NftV2SendModule {
    static func viewController(
        asset: NftV2Asset,
        displayMetadata: SendNftModule.DisplayMetadata? = nil,
        onSendSuccess: @escaping (Data, Int) -> Void,
        onSendFailed: @escaping (String) -> Void
    ) -> UIViewController? {
        guard let account = Core.shared.accountManager.activeAccount, !account.watchAccount else {
            return nil
        }

        let nftUid = asset.nftUid
        let nftKey = NftKey(account: account, blockchainType: nftUid.blockchainType)

        guard let adapter = Core.shared.nftAdapterManager.adapter(nftKey: nftKey) else {
            return nil
        }

        let evmBlockchainManager = Core.shared.evmBlockchainManager
        guard let evmKitWrapper = try? evmBlockchainManager
            .evmKitManager(blockchainType: nftUid.blockchainType)
            .evmKitWrapper(account: account, blockchainType: nftUid.blockchainType)
        else {
            return nil
        }

        let viewController: UIViewController

        switch nftUid {
        case .evm:
            let transferType = resolvedTransferType(asset: asset, adapter: adapter)
            guard transferType != .unknown else {
                return nil
            }

            switch transferType {
            case .eip721:
                let addressService = addressService(blockchainType: nftUid.blockchainType)
                let service = SendEip721Service(
                    nftUid: nftUid,
                    adapter: adapter,
                    addressService: addressService,
                    nftMetadataManager: Core.shared.nftMetadataManager,
                    overrideAssetShortMetadata: displayMetadata?.assetShortMetadata
                )

                let recipientAddressViewModel = RecipientAddressViewModel(service: addressService, handlerDelegate: nil)
                let viewModel = SendEip721ViewModel(service: service)

                viewController = NftV2SendEip721ViewController(
                    evmKitWrapper: evmKitWrapper,
                    viewModel: viewModel,
                    recipientViewModel: recipientAddressViewModel,
                    onSendSuccess: { txHash in
                        onSendSuccess(txHash, 1)
                    },
                    onSendFailed: onSendFailed
                )
            case .eip1155:
                let balance = adapter.nftRecord(nftUid: nftUid)?.balance ?? asset.balance
                let addressService = addressService(blockchainType: nftUid.blockchainType)
                let service = SendEip1155Service(
                    nftUid: nftUid,
                    balance: balance,
                    adapter: adapter,
                    addressService: addressService,
                    nftMetadataManager: Core.shared.nftMetadataManager,
                    overrideAssetShortMetadata: displayMetadata?.assetShortMetadata
                )

                let viewModel = SendEip1155ViewModel(service: service)
                let availableBalanceViewModel = SendEip1155AvailableBalanceViewModel(service: service)
                let amountViewModel = IntegerAmountInputViewModel(service: service)
                let recipientAddressViewModel = RecipientAddressViewModel(service: addressService, handlerDelegate: nil)

                viewController = NftV2SendEip1155ViewController(
                    evmKitWrapper: evmKitWrapper,
                    viewModel: viewModel,
                    availableBalanceViewModel: availableBalanceViewModel,
                    amountViewModel: amountViewModel,
                    recipientViewModel: recipientAddressViewModel,
                    onSendSuccess: { txHash, amount in
                        onSendSuccess(txHash, amount)
                    },
                    onSendFailed: onSendFailed
                )
            case .unknown:
                return nil
            }

        default:
            return nil
        }

        return ThemeNavigationController(rootViewController: viewController)
    }

    fileprivate static func sendAmount(sendData: SendEvmData) -> Int {
        let input = sendData.transactionData.input
        let amount = sendAmount(input: input)
        return max(amount ?? 1, 1)
    }

    private static func sendAmount(input: Data?) -> Int? {
        guard let input, input.count >= 4 else {
            return nil
        }

        let selector = input.prefix(4).hs.hexString.lowercased()
        guard selector == "f242432a" else {
            return nil
        }

        let valueStart = 4 + 32 * 3
        let valueEnd = valueStart + 32
        guard input.count >= valueEnd else {
            return nil
        }

        let valueData = input.subdata(in: valueStart ..< valueEnd)
        let value = BigUInt(valueData)

        return Int(exactly: value)
    }

    private static func addressService(blockchainType: BlockchainType) -> AddressService {
        let evmAddressParserItem = EvmAddressParser()

        let addressParserChain = AddressParserChain()
            .append(handler: evmAddressParserItem)

        if let httpSyncSource = Core.shared.evmSyncSourceManager.httpSyncSource(blockchainType: .ethereum),
           let ensAddressParserItem = EnsAddressParserItem(rpcSource: httpSyncSource.rpcSource, rawAddressParserItem: evmAddressParserItem)
        {
            addressParserChain.append(handler: ensAddressParserItem)
        }

        let addressUriParser = AddressParserFactory.parser(blockchainType: blockchainType, tokenType: nil)
        return AddressService(
            mode: .parsers(addressUriParser, addressParserChain),
            marketKit: Core.shared.marketKit,
            contactBookManager: Core.shared.contactManager,
            blockchainType: blockchainType,
            filter: nil
        )
    }

    private static func resolvedTransferType(asset: NftV2Asset, adapter: INftAdapter) -> NftV2TransferType {
        if asset.transferType != .unknown {
            return asset.transferType
        }

        guard let evmRecord = adapter.nftRecord(nftUid: asset.nftUid) as? EvmNftRecord else {
            return .unknown
        }

        switch evmRecord.type {
        case .eip721: return .eip721
        case .eip1155: return .eip1155
        }
    }
}

private enum NftV2SendEvmConfirmationModule {
    static func viewController(
        evmKitWrapper: EvmKitWrapper,
        sendData: SendEvmData,
        onSendSuccess: @escaping (Data) -> Void,
        onSendFailed: @escaping (String) -> Void
    ) -> UIViewController? {
        let evmKit = evmKitWrapper.evmKit

        guard let coinServiceFactory = EvmCoinServiceFactory(
            blockchainType: evmKitWrapper.blockchainType,
            marketKit: Core.shared.marketKit,
            currencyManager: Core.shared.currencyManager,
            coinManager: Core.shared.coinManager
        ) else {
            return nil
        }

        let predefinedGasLimit: Int? = [.ethereum, .polygon, .binanceSmartChain].contains(evmKitWrapper.blockchainType) ? 100000 : nil

        guard let (settingsService, settingsViewModel) = EvmSendSettingsModule.instance(
            evmKit: evmKit,
            blockchainType: evmKitWrapper.blockchainType,
            sendData: sendData,
            coinServiceFactory: coinServiceFactory,
            predefinedGasLimit: predefinedGasLimit,
            gasLimitType: .common
        ) else {
            return nil
        }

        let service = SendEvmTransactionService(
            sendData: sendData,
            privateSendMode: .none,
            evmKitWrapper: evmKitWrapper,
            settingsService: settingsService,
            evmLabelManager: Core.shared.evmLabelManager
        )
        let contactLabelService = ContactLabelService(contactManager: Core.shared.contactManager, blockchainType: evmKitWrapper.blockchainType)
        let viewModel = SendEvmTransactionViewModel(
            service: service,
            coinServiceFactory: coinServiceFactory,
            cautionsFactory: SendEvmCautionsFactory(),
            evmLabelManager: Core.shared.evmLabelManager,
            contactLabelService: contactLabelService
        )

        return NftV2SendEvmConfirmationViewController(
            mode: .send,
            transactionViewModel: viewModel,
            settingsViewModel: settingsViewModel,
            onSendSuccess: onSendSuccess,
            onSendFailed: onSendFailed
        )
    }
}

private final class NftV2SendEvmConfirmationViewController: SendEvmConfirmationViewController {
    private let onSendSuccess: (Data) -> Void
    private let onSendFailed: (String) -> Void
    private var finished = false

    init(
        mode: Mode,
        transactionViewModel: SendEvmTransactionViewModel,
        settingsViewModel: EvmSendSettingsViewModel,
        onSendSuccess: @escaping (Data) -> Void,
        onSendFailed: @escaping (String) -> Void
    ) {
        self.onSendSuccess = onSendSuccess
        self.onSendFailed = onSendFailed
        super.init(mode: mode, transactionViewModel: transactionViewModel, settingsViewModel: settingsViewModel)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func handleSendSuccess(transactionHash: Data) {
        if !finished {
            finished = true
            onSendSuccess(transactionHash)
        }

        super.handleSendSuccess(transactionHash: transactionHash)
    }

    override func handleSendFailed(error: String) {
        if !finished {
            finished = true
            onSendFailed(error)
        }

        super.handleSendFailed(error: error)
    }
}

private final class NftV2SendEip721ViewController: KeyboardAwareViewController {
    private let evmKitWrapper: EvmKitWrapper
    private let viewModel: SendEip721ViewModel
    private let onSendSuccess: (Data) -> Void
    private let onSendFailed: (String) -> Void
    private let disposeBag = DisposeBag()

    private let tableView = SectionsTableView(style: .grouped)
    private let recipientCell: RecipientAddressInputCell
    private let recipientCautionCell: RecipientAddressCautionCell
    private let gradientWrapperView = BottomGradientHolder()
    private let nextButton = PrimaryButton()

    private var isLoaded = false

    init(
        evmKitWrapper: EvmKitWrapper,
        viewModel: SendEip721ViewModel,
        recipientViewModel: RecipientAddressViewModel,
        onSendSuccess: @escaping (Data) -> Void,
        onSendFailed: @escaping (String) -> Void
    ) {
        self.evmKitWrapper = evmKitWrapper
        self.viewModel = viewModel
        self.onSendSuccess = onSendSuccess
        self.onSendFailed = onSendFailed

        recipientCell = RecipientAddressInputCell(viewModel: recipientViewModel)
        recipientCautionCell = RecipientAddressCautionCell(viewModel: recipientViewModel)

        super.init(scrollViews: [tableView], accessoryView: gradientWrapperView)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = "send.send".localized

        navigationItem.largeTitleDisplayMode = .never
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: "button.cancel".localized, style: .plain, target: self, action: #selector(onTapCancel))
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "button.next".localized, style: .done, target: self, action: #selector(onTapNext))
        navigationItem.rightBarButtonItem?.tintColor = .themeJacob
        navigationItem.backBarButtonItem = UIBarButtonItem(title: "", style: .plain, target: nil, action: nil)

        view.addSubview(tableView)
        tableView.snp.makeConstraints { maker in
            maker.edges.equalToSuperview()
        }

        tableView.separatorStyle = .none
        tableView.backgroundColor = .clear
        tableView.allowsSelection = false
        tableView.sectionDataSource = self
        tableView.registerCell(forClass: NftAssetImageCell.self)

        recipientCell.onChangeHeight = { [weak self] in self?.reloadTable() }
        recipientCell.onOpenViewController = { [weak self] in self?.present($0, animated: true) }
        recipientCautionCell.onChangeHeight = { [weak self] in self?.reloadTable() }

        gradientWrapperView.add(to: self)
        gradientWrapperView.addSubview(nextButton)

        nextButton.set(style: .yellow)
        nextButton.setTitle("button.next".localized, for: .normal)
        nextButton.addTarget(self, action: #selector(onTapNext), for: .touchUpInside)

        subscribe(disposeBag, viewModel.proceedEnableDriver) { [weak self] in
            self?.nextButton.isEnabled = $0
            self?.navigationItem.rightBarButtonItem?.isEnabled = $0
        }
        subscribe(disposeBag, viewModel.nftImageDriver) { [weak self] _ in
            self?.tableView.buildSections()
        }
        subscribe(disposeBag, viewModel.proceedSignal) { [weak self] in
            self?.openConfirm(sendData: $0)
        }

        tableView.buildSections()
        isLoaded = true
    }

    @objc private func onTapNext() {
        viewModel.didTapProceed()
    }

    @objc private func onTapCancel() {
        dismiss(animated: true)
    }

    private func reloadTable() {
        guard isLoaded else {
            return
        }

        UIView.animate(withDuration: 0.2) {
            self.tableView.beginUpdates()
            self.tableView.endUpdates()
        }
    }

    private func openConfirm(sendData: SendEvmData) {
        guard let viewController = NftV2SendEvmConfirmationModule.viewController(
            evmKitWrapper: evmKitWrapper,
            sendData: sendData,
            onSendSuccess: onSendSuccess,
            onSendFailed: onSendFailed
        ) else {
            return
        }

        navigationController?.pushViewController(viewController, animated: true)
    }
}

extension NftV2SendEip721ViewController: SectionsDataSource {
    private func imageSection(nftImage: NftImage) -> SectionProtocol {
        Section(
            id: "image",
            headerState: .margin(height: .margin12),
            footerState: .margin(height: .margin12),
            rows: [
                Row<NftAssetImageCell>(
                    id: "image",
                    dynamicHeight: { width in
                        NftAssetImageCell.height(containerWidth: width, maxHeight: 120, ratio: nftImage.ratio)
                    },
                    bind: { cell, _ in
                        cell.bind(nftImage: nftImage, cornerRadius: .cornerRadius8)
                    }
                )
            ]
        )
    }

    func buildSections() -> [SectionProtocol] {
        var sections = [SectionProtocol]()

        if let nftImage = viewModel.nftImage {
            sections.append(imageSection(nftImage: nftImage))
        }

        let nameFont: UIFont = .headline1
        let name = viewModel.name

        sections.append(
            Section(
                id: "title",
                rows: [
                    CellBuilderNew.row(
                        rootElement: .text { component in
                            component.font = nameFont
                            component.textColor = .themeLeah
                            component.text = name
                            component.numberOfLines = 0
                            component.textAlignment = .center
                        },
                        tableView: tableView,
                        id: "name",
                        dynamicHeight: { width in
                            CellBuilderNew.height(
                                containerWidth: width,
                                backgroundStyle: .transparent,
                                text: name,
                                font: nameFont,
                                verticalPadding: .margin12,
                                elements: [.multiline]
                            )
                        },
                        bind: { cell in
                            cell.set(backgroundStyle: .transparent, isFirst: true)
                        }
                    )
                ]
            )
        )

        sections.append(
            Section(
                id: "recipient",
                headerState: .margin(height: .margin12),
                footerState: .margin(height: .margin32),
                rows: [
                    StaticRow(
                        cell: recipientCell,
                        id: "recipient-input",
                        dynamicHeight: { [weak self] width in
                            self?.recipientCell.height(containerWidth: width) ?? 0
                        }
                    ),
                    StaticRow(
                        cell: recipientCautionCell,
                        id: "recipient-caution",
                        dynamicHeight: { [weak self] width in
                            self?.recipientCautionCell.height(containerWidth: width) ?? 0
                        }
                    )
                ]
            )
        )

        return sections
    }
}

private final class NftV2SendEip1155ViewController: KeyboardAwareViewController {
    private let evmKitWrapper: EvmKitWrapper
    private let viewModel: SendEip1155ViewModel
    private let onSendSuccess: (Data, Int) -> Void
    private let onSendFailed: (String) -> Void
    private let disposeBag = DisposeBag()

    private let tableView = SectionsTableView(style: .grouped)
    private let availableBalanceCell: SendAvailableBalanceCell
    private let amountCell: IntegerAmountInputCell
    private let amountCautionCell = FormCautionCell()
    private let recipientCell: RecipientAddressInputCell
    private let recipientCautionCell: RecipientAddressCautionCell
    private let gradientWrapperView = BottomGradientHolder()
    private let nextButton = PrimaryButton()

    private var isLoaded = false
    private var keyboardShown = false

    init(
        evmKitWrapper: EvmKitWrapper,
        viewModel: SendEip1155ViewModel,
        availableBalanceViewModel: ISendAvailableBalanceViewModel,
        amountViewModel: IntegerAmountInputViewModel,
        recipientViewModel: RecipientAddressViewModel,
        onSendSuccess: @escaping (Data, Int) -> Void,
        onSendFailed: @escaping (String) -> Void
    ) {
        self.evmKitWrapper = evmKitWrapper
        self.viewModel = viewModel
        self.onSendSuccess = onSendSuccess
        self.onSendFailed = onSendFailed

        availableBalanceCell = SendAvailableBalanceCell(viewModel: availableBalanceViewModel)
        amountCell = IntegerAmountInputCell(viewModel: amountViewModel)
        recipientCell = RecipientAddressInputCell(viewModel: recipientViewModel)
        recipientCautionCell = RecipientAddressCautionCell(viewModel: recipientViewModel)

        super.init(scrollViews: [tableView], accessoryView: gradientWrapperView)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = "send.send".localized

        navigationItem.largeTitleDisplayMode = .never
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: "button.cancel".localized, style: .plain, target: self, action: #selector(onTapCancel))
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "button.next".localized, style: .done, target: self, action: #selector(onTapNext))
        navigationItem.rightBarButtonItem?.tintColor = .themeJacob
        navigationItem.backBarButtonItem = UIBarButtonItem(title: "", style: .plain, target: nil, action: nil)

        view.addSubview(tableView)
        tableView.snp.makeConstraints { maker in
            maker.edges.equalToSuperview()
        }

        tableView.separatorStyle = .none
        tableView.backgroundColor = .clear
        tableView.allowsSelection = false
        tableView.sectionDataSource = self
        tableView.registerCell(forClass: NftAssetImageCell.self)

        amountCautionCell.onChangeHeight = { [weak self] in self?.reloadTable() }
        recipientCell.onChangeHeight = { [weak self] in self?.reloadTable() }
        recipientCell.onOpenViewController = { [weak self] in self?.present($0, animated: true) }
        recipientCautionCell.onChangeHeight = { [weak self] in self?.reloadTable() }

        gradientWrapperView.add(to: self)
        gradientWrapperView.addSubview(nextButton)

        nextButton.set(style: .yellow)
        nextButton.setTitle("button.next".localized, for: .normal)
        nextButton.addTarget(self, action: #selector(onTapNext), for: .touchUpInside)

        subscribe(disposeBag, viewModel.proceedEnableDriver) { [weak self] in
            self?.nextButton.isEnabled = $0
            self?.navigationItem.rightBarButtonItem?.isEnabled = $0
        }
        subscribe(disposeBag, viewModel.nftImageDriver) { [weak self] _ in
            self?.tableView.buildSections()
        }
        subscribe(disposeBag, viewModel.amountCautionDriver) { [weak self] caution in
            self?.amountCell.set(cautionType: caution?.type)
            self?.amountCautionCell.set(caution: caution)
        }
        subscribe(disposeBag, viewModel.proceedSignal) { [weak self] in
            self?.openConfirm(sendData: $0)
        }

        tableView.buildSections()
        isLoaded = true
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        if !keyboardShown, viewModel.showKeyboard {
            DispatchQueue.main.async {
                _ = self.amountCell.becomeFirstResponder()
            }

            keyboardShown = true
        }
    }

    @objc private func onTapNext() {
        viewModel.didTapProceed()
    }

    @objc private func onTapCancel() {
        dismiss(animated: true)
    }

    private func reloadTable() {
        guard isLoaded else {
            return
        }

        UIView.animate(withDuration: 0.2) {
            self.tableView.beginUpdates()
            self.tableView.endUpdates()
        }
    }

    private func openConfirm(sendData: SendEvmData) {
        let amount = NftV2SendModule.sendAmount(sendData: sendData)

        guard let viewController = NftV2SendEvmConfirmationModule.viewController(
            evmKitWrapper: evmKitWrapper,
            sendData: sendData,
            onSendSuccess: { [onSendSuccess] txHash in
                onSendSuccess(txHash, amount)
            },
            onSendFailed: onSendFailed
        ) else {
            return
        }

        navigationController?.pushViewController(viewController, animated: true)
    }
}

extension NftV2SendEip1155ViewController: SectionsDataSource {
    private func imageSection(nftImage: NftImage) -> SectionProtocol {
        Section(
            id: "image",
            headerState: .margin(height: .margin12),
            footerState: .margin(height: .margin12),
            rows: [
                Row<NftAssetImageCell>(
                    id: "image",
                    dynamicHeight: { width in
                        NftAssetImageCell.height(containerWidth: width, maxHeight: 120, ratio: nftImage.ratio)
                    },
                    bind: { cell, _ in
                        cell.bind(nftImage: nftImage, cornerRadius: .cornerRadius8)
                    }
                )
            ]
        )
    }

    func buildSections() -> [SectionProtocol] {
        var sections = [SectionProtocol]()

        if let nftImage = viewModel.nftImage {
            sections.append(imageSection(nftImage: nftImage))
        }

        let nameFont: UIFont = .headline1
        let name = viewModel.name

        sections.append(
            Section(
                id: "title",
                rows: [
                    CellBuilderNew.row(
                        rootElement: .text { component in
                            component.font = nameFont
                            component.textColor = .themeLeah
                            component.text = name
                            component.numberOfLines = 0
                            component.textAlignment = .center
                        },
                        tableView: tableView,
                        id: "name",
                        dynamicHeight: { width in
                            CellBuilderNew.height(
                                containerWidth: width,
                                backgroundStyle: .transparent,
                                text: name,
                                font: nameFont,
                                verticalPadding: .margin12,
                                elements: [.multiline]
                            )
                        },
                        bind: { cell in
                            cell.set(backgroundStyle: .transparent, isFirst: true)
                        }
                    )
                ]
            )
        )

        sections.append(contentsOf: [
            Section(
                id: "available-balance",
                headerState: .margin(height: .margin4),
                rows: [
                    StaticRow(
                        cell: availableBalanceCell,
                        id: "available-balance",
                        height: availableBalanceCell.cellHeight
                    )
                ]
            ),
            Section(
                id: "amount",
                headerState: .margin(height: .margin8),
                rows: [
                    StaticRow(
                        cell: amountCell,
                        id: "amount-input",
                        height: amountCell.cellHeight
                    ),
                    StaticRow(
                        cell: amountCautionCell,
                        id: "amount-caution",
                        dynamicHeight: { [weak self] width in
                            self?.amountCautionCell.height(containerWidth: width) ?? 0
                        }
                    )
                ]
            )
        ])

        sections.append(
            Section(
                id: "recipient",
                headerState: .margin(height: .margin12),
                rows: [
                    StaticRow(
                        cell: recipientCell,
                        id: "recipient-input",
                        dynamicHeight: { [weak self] width in
                            self?.recipientCell.height(containerWidth: width) ?? 0
                        }
                    ),
                    StaticRow(
                        cell: recipientCautionCell,
                        id: "recipient-caution",
                        dynamicHeight: { [weak self] width in
                            self?.recipientCautionCell.height(containerWidth: width) ?? 0
                        }
                    )
                ]
            )
        )

        return sections
    }
}
