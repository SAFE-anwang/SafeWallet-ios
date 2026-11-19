import Foundation

protocol IDappSignService {
    func approveRequest(id: Int, result: Any)
    func rejectRequest(id: Int)
}
