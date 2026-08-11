import Foundation

enum ParserDiagnostic: Equatable {
    case emptyTitle
    case unmatchedList(String)
}
