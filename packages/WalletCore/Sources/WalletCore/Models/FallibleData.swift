struct FallibleData<T> {
    let data: T
    let errors: [Error]
    let warnings: [Warning]

    var cautionType: CautionType? {
        guard errors.isEmpty else {
            return .error
        }

        guard warnings.isEmpty else {
            return .warning
        }

        return nil
    }
}
