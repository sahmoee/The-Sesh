import Foundation

/// Side-effect-free production transport, image and durable-write rules.
nonisolated enum SeshReliabilityPolicy {
    static let maxJSONBytes = 2 * 1024 * 1024
    static let maxImageBytes = 16 * 1024 * 1024
    static func serverDate(_ value: String) -> Date? {
        (try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(value))
            ?? (try? Date.ISO8601FormatStyle(includingFractionalSeconds: false).parse(value))
    }
    static func retryAfter(_ raw: String?, now: Date = Date()) -> TimeInterval? {
        guard let value = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        if let seconds = Double(value) {
            return seconds.isFinite && seconds >= 0 && seconds <= 31_536_000 ? seconds : nil
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss z"
        guard let date = formatter.date(from: value) else { return nil }
        let interval = max(0, date.timeIntervalSince(now))
        return interval <= 31_536_000 ? interval : nil
    }
    static func transient(_ error: Error) -> Bool {
        guard let error = error as? URLError else { return false }
        return [.timedOut, .networkConnectionLost, .cannotConnectToHost, .cannotFindHost,
                .dnsLookupFailed, .notConnectedToInternet, .resourceUnavailable].contains(error.code)
    }
    static func pathSegment(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_~")) ?? ""
    }
    static func validOutboxPath(_ value: String) -> Bool {
        guard value.hasPrefix("/api/"), !value.contains(".."), !value.contains("\\"),
              !value.contains("#"), !value.contains("?"),
              !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { return false }
        let decoded = value.removingPercentEncoding ?? value
        return !decoded.contains("..") && !decoded.contains("\\")
    }
    static func imagePixels(_ value: Double) -> Int {
        guard value.isFinite, value > 0 else { return 600 }
        return min(2048, max(64, Int(min(value, 2048).rounded(.up))))
    }
    static func imageKey(_ url: URL, pixels: Int) -> String { "\(pixels):\(url.absoluteString)" }
    static func ownerMatches(_ owner: String?, current: String?) -> Bool {
        guard let owner, !owner.isEmpty, let current, !current.isEmpty else { return false }
        return owner == current
    }
    static func mayReplayActivity(_ body: Data, sharesActivity: Bool, sharesDetails: Bool) -> Bool {
        guard sharesActivity else { return false }
        guard !sharesDetails else { return true }
        guard let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else { return false }
        return (object["detail"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    static func acceptsHTTPImage(status: Int, mime: String?, bytes: Int) -> Bool {
        (200...299).contains(status) && bytes > 0 && bytes <= maxImageBytes
            && (mime == nil || mime!.lowercased().hasPrefix("image/"))
    }
}
