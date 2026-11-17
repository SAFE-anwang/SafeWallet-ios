import Foundation
import Combine
import UIKit
import WalletCore

final class AppDelegate: NSObject, UIApplicationDelegate, ObservableObject {
    @Published private(set) var initResult: Result<Void, Error>?

    // Only the unit-test Test action opts in. Full-app test schemes must omit this flag.
    static let isUnitTestHost: Bool = {
        #if DEBUG
            ProcessInfo.processInfo.environment["SAFEWALLET_UNIT_TEST_HOST"] == "1"
        #else
            false
        #endif
    }()

    func application(_: UIApplication, didFinishLaunchingWithOptions _: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // Keep initResult nil so SwiftUI renders EmptyView instead of constructing AppView.
        // Starting native wallets here races their background work against XCTest's exit().
        guard !Self.isUnitTestHost else { return true }

        #if DEV
            AppEnvironment.configure(.dev)
        #endif

        Theme.updateNavigationBarTheme() // TODO: get rid of this

        do {
            try UnstoppableApp.initCore()
            initResult = .success(())
        } catch {
            initResult = .failure(error)
        }

        return true
    }

    func application(_: UIApplication, shouldAllowExtensionPointIdentifier extensionPointIdentifier: UIApplication.ExtensionPointIdentifier) -> Bool {
        if extensionPointIdentifier == .keyboard {
            // disable custom keyboards
            return false
        }
        return true
    }

    func application(_: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options _: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let sceneConfig = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        // These callbacks access Core.shared, which deliberately does not exist in the unit host.
        if !Self.isUnitTestHost {
            sceneConfig.delegateClass = AppSceneDelegate.self
        }
        return sceneConfig
    }
}
