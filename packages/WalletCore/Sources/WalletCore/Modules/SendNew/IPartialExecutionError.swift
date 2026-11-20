/// A `submit()` failure where value may ALREADY have moved on-chain — e.g. an interactive
/// broker session (StellarBroker) that signed and submitted transactions before failing.
/// Carries the last known tx hash so the send handler can persist a trackable swap record
/// (instead of a ghost swap the server record waits on forever) before surfacing the error.
public protocol IPartialExecutionError: Error {
    var partialTxHash: String? { get }
}
