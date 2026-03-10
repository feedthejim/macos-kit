public protocol TextRepresentable {
    var textSummary: String { get }
    var textDetail: String { get }
}

public protocol TableRepresentable {
    static var tableHeaders: [String] { get }
    var tableRow: [String] { get }
}
