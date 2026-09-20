enum RestoreTypeModule {
    enum RestoreType: String, CaseIterable, Identifiable {
        case recoveryOrPrivateKey
        case privateKey
        case backup

        var id: String {
            rawValue
        }
    }
}
