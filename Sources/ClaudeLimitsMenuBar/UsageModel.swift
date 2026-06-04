import Foundation

/// One rate-limit window from /api/oauth/usage. Windows that don't apply to the
/// account (e.g. per-model weekly buckets on a Pro plan) come back as null.
struct UsageWindow: Codable {
    let utilization: Double          // 0–100
    let resets_at: String?           // ISO8601

    var fraction: Double { max(0, min(1, utilization / 100)) }

    var resetDate: Date? {
        guard let s = resets_at else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return iso.date(from: s) ?? ISO8601DateFormatter().date(from: s)
    }
}

/// Response from GET https://api.anthropic.com/api/oauth/usage.
struct UsageResponse: Codable {
    let five_hour: UsageWindow?
    let seven_day: UsageWindow?
    let seven_day_opus: UsageWindow?
    let seven_day_sonnet: UsageWindow?
}
