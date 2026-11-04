import Testing
@testable import WalletCore

struct SafeDappRegistrationTests {
    @Test func retriesTransientPostRegistrationReads() async throws {
        enum ReadError: Error {
            case notReady
        }

        var attempts = 0
        let result = try await SafeDappService.retrying(attempts: 3, delayNanoseconds: 0) {
            attempts += 1
            if attempts < 3 {
                throw ReadError.notReady
            }
            return "registered"
        }

        #expect(result == "registered")
        #expect(attempts == 3)
    }

    @Test func reportsTheLastErrorAfterReadRetries() async {
        enum ReadError: Error, Equatable {
            case unavailable
        }

        var attempts = 0
        do {
            let _: String = try await SafeDappService.retrying(attempts: 2, delayNanoseconds: 0) {
                attempts += 1
                throw ReadError.unavailable
            }
            Issue.record("Expected the read retry to fail")
        } catch let error as ReadError {
            #expect(error == .unavailable)
            #expect(attempts == 2)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}
