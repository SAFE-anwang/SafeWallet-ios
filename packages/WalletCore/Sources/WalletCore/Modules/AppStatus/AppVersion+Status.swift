import Foundation

extension AppVersion {
    var desc: String {
        guard let build else {
            return version
        }

        return version + " (\(build))"
    }
}
