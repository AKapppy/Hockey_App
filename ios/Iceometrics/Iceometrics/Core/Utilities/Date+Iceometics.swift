import Foundation

nonisolated extension Date {
    var iceometicsShortDateTime: String {
        formatted(date: .abbreviated, time: .shortened)
    }
}
