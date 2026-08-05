import Foundation

enum ResetDateFormatting {
    static func parse(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }

        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) { return date }

        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]
        if let date = standard.date(from: value) { return date }

        return nil
    }

    /// One compact format for every provider, always rendered in the user's
    /// local timezone. The year is included only when the reset isn't in the
    /// current calendar year.
    static func display(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = calendar.component(.year, from: date) == calendar.component(.year, from: now)
            ? "MMM d, h:mm a"
            : "MMM d yyyy, h:mm a"
        return formatter.string(from: date).uppercased()
    }
}
