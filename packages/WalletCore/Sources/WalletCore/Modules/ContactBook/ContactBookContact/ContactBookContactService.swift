import Foundation
import MarketKit
import RxRelay
import RxSwift

class ContactBookContactService {
    static let maxAddressesPerBlockchain = 5

    private let disposeBag = DisposeBag()

    private let marketKit: MarketKit.Kit
    private let contactManager: ContactBookManager

    let oldContact: Contact?

    private let stateRelay = BehaviorRelay<State>(value: .idle)
    var state: State = .idle {
        didSet {
            stateRelay.accept(state)
        }
    }

    private let allBlockchainsUsedRelay = BehaviorRelay<Bool>(value: false)

    private let addressItemsRelay = BehaviorRelay<[AddressItem]>(value: [])
    private(set) var addresses: [ContactAddress] = [] {
        didSet {
            syncAddresses()
            sync()
            syncAllUsedBlockchains()
        }
    }

    var contactName: String = "" {
        didSet {
            sync()
        }
    }

    init(contactManager: ContactBookManager, marketKit: MarketKit.Kit, contact: Contact? = nil, newAddresses: [ContactAddress] = []) {
        self.marketKit = marketKit
        self.contactManager = contactManager

        oldContact = contact
        restoreContainer()

        for address in newAddresses {
            updateContact(address: address)
        }

        sync()
        syncAddresses()
        syncAllUsedBlockchains()
    }

    private func restoreContainer() {
        contactName = oldContact?.name ?? ""
        addresses = oldContact?.addresses ?? []
    }

    private func blockchain(by address: ContactAddress) -> Blockchain? {
        try? marketKit.blockchain(uid: address.blockchainUid)
    }

    private func syncAddresses() {
        let addressItems = addresses.compactMap { address -> AddressItem? in
            var edited = true
            // check if old address same with new - set edited false
            if let oldAddresses = oldContact?.addresses,
               oldAddresses.contains(where: { self.sameAddress($0, address) })
            {
                edited = false
            }
            return blockchain(by: address).map { AddressItem(blockchain: $0, address: address.address, edited: edited) }
        }.sorted { item, item2 in item.blockchain.type.order < item2.blockchain.type.order }

        addressItemsRelay.accept(addressItems)
    }

    private func syncAllUsedBlockchains() {
        guard !addresses.isEmpty else {
            allBlockchainsUsedRelay.accept(false)
            return
        }

        // check if all blockchains reached the per-chain address limit
        allBlockchainsUsedRelay.accept(
            BlockchainType
                .supported
                .filter { type in
                    addresses.filter { $0.blockchainUid == type.uid }.count < Self.maxAddressesPerBlockchain
                }.count == 0
        )
    }

    private func sameAddress(_ lhs: ContactAddress, _ rhs: ContactAddress) -> Bool {
        lhs.blockchainUid == rhs.blockchainUid && lhs.address.lowercased() == rhs.address.lowercased()
    }

    private func sync() {
        // check if name already exist
        let otherContactNames = contactManager
            .all?
            .filter { (oldContact?.name ?? "") != $0.name }
            .map { $0.name.lowercased() } ?? []

        if otherContactNames.contains(contactName.lowercased()) {
            state = .error(ValidationError.nameExist)
            return
        }

        // check empty name or empty addresses
        if contactName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || addresses.isEmpty {
            state = .idle
            return
        }
        // check no changes with old contact
        if let oldContact, contactName == oldContact.name, addresses == oldContact.addresses {
            state = .idle
            return
        }

        state = .updated
    }
}

extension ContactBookContactService {
    var stateObservable: Observable<State> {
        stateRelay.asObservable()
    }

    var addressItemsObservable: Observable<[AddressItem]> {
        addressItemsRelay.asObservable()
    }

    var allAddressesUsedObservable: Observable<Bool> {
        allBlockchainsUsedRelay.asObservable()
    }

    func updateContact(address: ContactAddress, replacing currentAddress: ContactAddress? = nil) {
        if let currentAddress, let index = addresses.firstIndex(where: { sameAddress($0, currentAddress) }) {
            addresses[index] = address
            return
        }

        if let index = addresses.firstIndex(where: { sameAddress($0, address) }) {
            addresses[index] = address
            return
        }

        let addressesCount = addresses.filter { $0.blockchainUid == address.blockchainUid }.count
        if addressesCount < Self.maxAddressesPerBlockchain {
            addresses.append(address)
        } else {
            HudHelper.instance.show(banner: .error(string: "contact_book.address_limit_exceeded".localized))
        }
    }

    func removeContact(address: ContactAddress?) {
        if let address, let index = addresses.firstIndex(where: { sameAddress($0, address) }) {
            addresses.remove(at: index)
        }
    }

    func save() throws {
        guard case .updated = state else {
            return
        }

        let uid = oldContact?.uid ?? UUID().uuidString
        let contact = Contact(uid: uid, modifiedAt: Date().timeIntervalSince1970, name: contactName, addresses: addresses)

        try contactManager.update(contact: contact)
    }

    func delete() throws {
        guard let uid = oldContact?.uid else {
            return
        }
        try contactManager.delete(uid)
    }
}

extension ContactBookContactService {
    struct AddressItem {
        let blockchain: Blockchain
        let address: String
        let edited: Bool

        var blockchainCode: String {
            blockchain.type == .safe ? "SAFE3" : ""
        }
    }

    struct Item {
        let name: String
        let addresses: [AddressItem]
    }

    enum State {
        case idle
        case updated
        case error(Error)
    }

    enum ValidationError: Error {
        case nameExist
    }
}
