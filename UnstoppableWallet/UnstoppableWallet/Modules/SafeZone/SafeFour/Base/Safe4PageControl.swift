import Foundation

struct Safe4PageControl {
    private let initCount: Int
    private(set) var totalNum: Int
    private var page: Int = 0
    private let isReverse: Bool
        
    init(initCount: Int, totalNum: Int = 0, page: Int = 0, isReverse: Bool = false) {
        self.initCount = initCount
        self.totalNum = totalNum
        self.page = page
        self.isReverse = isReverse
    }
    
    mutating func set(totalNum: Int) {
        self.page = 0
        self.totalNum = totalNum
    }
    
    mutating func plusPage() {
        let next = page + 1
        page = min(next, maxPageNum)
    }
    
    var numArray: [Int] {
        Array(0 ..< totalNum)
    }
    
    var pageArray: [[Int]] {
        let numbers = isReverse ? numArray.reversed() : numArray
        return stride(from: 0, to: numbers.count, by: initCount).map { startIndex -> [Int] in
            let endIndex = min(startIndex + initCount, numbers.count)
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
        if isReverse {
            return pageArray[page].last ?? 0
        }else {
            return pageArray[page].first ?? 0
        }
    }
}
