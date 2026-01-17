import Foundation

struct Safe4PageControl: Codable {
    private let pageSize: Int
    private(set) var totalNum: Int
    private(set) var page: Int = 0
    private(set) var targetIndexPath: IndexPath
    private let isReverse: Bool
    private var isExceed: Bool = false
    
    init(totalNum: Int = 0, page: Int = 0, pageSize: Int = 0, isReverse: Bool = false) {
        self.totalNum = totalNum
        self.pageSize = pageSize
        self.page = page
        self.isReverse = isReverse
        self.targetIndexPath = IndexPath(row: 0, section: 0)
    }
    
    mutating func set(totalNum: Int) {
        self.page = 0
        self.totalNum = totalNum
        guard totalNum > 0 else { return }
        let row = isReverse ? 0 : (pageArray[page].count - 1)
        targetIndexPath = IndexPath(row: row, section: page)
    }
    
    mutating func update(totalNum: Int, page: Int, indexPath: IndexPath) {
        self.page = 0
        self.totalNum = totalNum
        guard totalNum > 0 else { return }
        let row = isReverse ? 0 : (pageArray[page].count - 1)
        targetIndexPath = IndexPath(row: row, section: page)
    }
    
    mutating func plusPage() {
        let next = page + 1
        isExceed = next > maxPageNum
        page = min(next, maxPageNum)
        guard totalNum > 0 else { return }
        let row = isReverse ? 0 : (pageArray[page].count - 1)
        targetIndexPath = IndexPath(row: row, section: page)
    }
    
    var numArray: [Int] {
        Array(0 ..< totalNum)
    }
    
    var pageArray: [[Int]] {
        let numbers = isReverse ? numArray.reversed() : numArray
        return stride(from: 0, to: numbers.count, by: pageSize).map { startIndex -> [Int] in
            let endIndex = min(startIndex + pageSize, numbers.count)
            return Array(numbers[startIndex..<endIndex])
        }
    }
    
    var maxPageNum: Int {
        pageArray.count - 1
    }
        
    var currentPageCount: Int {
        pageArray[page].count
    }
    
    var start: Int {
        guard totalNum > 0 else { return 0 }
        if isReverse {
            return pageArray[page].last ?? 0
        }else {
            return pageArray[page].first ?? 0
        }
    }
    
    var lastIndex: Int {
        guard totalNum > 0 else { return 0 }
        return pageArray[targetIndexPath.section][targetIndexPath.row]
    }
    
    var isLastPage: Bool {
        page == maxPageNum
    }
    
    var isAbleLoadMore: Bool {
        totalNum > 0 && !isExceed
    }
    
    mutating func reset() {
        set(totalNum: 0)
    }
}
