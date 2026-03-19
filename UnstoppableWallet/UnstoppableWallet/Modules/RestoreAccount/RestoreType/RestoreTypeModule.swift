enum RestoreTypeModule {
    enum RestoreType: String, CaseIterable, Identifiable {
        case recoveryOrPrivateKey
        case privateKey
//        case cloudRestore
//        case fileRestore

        var id: String {
            rawValue
        }
    }
}
