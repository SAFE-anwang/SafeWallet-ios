import Foundation

extension DateHelper {
    func safe4Format(date: Date) -> String {
        DateFormatter.cachedFormatter(format: "MM-dd-yy, HH:mm:ss").string(from: date)
    }
}
