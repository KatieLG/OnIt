import Foundation
@testable import OnIt

/// A controllable clock for injecting into `AppStore`.
final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var _now: Date

    init(_ now: Date = Date(timeIntervalSince1970: 1_800_000_000)) {
        _now = now
    }

    var now: Date {
        get { lock.withLock { _now } }
        set { lock.withLock { _now = newValue } }
    }

    func advance(days: Double) {
        now = now.addingTimeInterval(days * 86_400)
    }

    var closure: @Sendable () -> Date { { [self] in now } }
}

/// A fresh temporary directory, removed when the test process exits.
func makeTempDirectory() -> URL {
    let url = FileManager.default.temporaryDirectory
        .appending(path: "OnItTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
