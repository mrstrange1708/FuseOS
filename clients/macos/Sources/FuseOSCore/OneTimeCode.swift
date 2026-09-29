import Foundation

/// Finds a one-time code — a sign-in, verification or payment OTP — in a notification from
/// the phone, so the island can offer it to copy or paste into the box you're typing in.
///
/// Deliberately narrow, because an order number, an amount, a date or a phone number is
/// also a run of digits: the text must say it is a code, currency amounts never count, and
/// of several candidates the one nearest those words wins. Spaced or dashed codes
/// (`123-456`) come back as digits only — what a code field expects.
/// ponytail: digits only; letters-and-digits codes (`K7Q-2PX`) are left alone.
public enum OneTimeCode {
    private static let keywords = [
        "otp", "code", "verification", "verify", "passcode", "password", "one-time", "one time",
        "2fa", "two-factor", "log in", "login", "sign in", "sign-in", "authenticat", "pin",
    ]

    // 4–8 digits, or 3–4 + 3–4 split by one space or dash; not glued to other digits, a
    // decimal point or a currency sign.
    private static let candidate = try! NSRegularExpression(
        pattern: #"(?<![\d.,₹$€£])(\d{3,4}[- ]\d{3,4}|\d{4,8})(?![\d]|[.,]\d)"#,
    )
    private static let currency = try! NSRegularExpression(
        pattern: #"(rs\.?|inr|usd|eur)\s*$"#, options: .caseInsensitive,
    )

    public static func find(in text: String) -> String? {
        let lower = text.lowercased() as NSString
        var marks: [Int] = []
        for word in keywords {
            var range = NSRange(location: 0, length: lower.length)
            while true {
                let hit = lower.range(of: word, options: [], range: range)
                if hit.location == NSNotFound { break }
                marks.append(hit.location)
                range = NSRange(location: hit.location + hit.length, length: lower.length - hit.location - hit.length)
            }
        }
        guard !marks.isEmpty else { return nil }

        let source = text as NSString
        let matches = candidate.matches(in: text, range: NSRange(location: 0, length: source.length))
        let codes = matches.compactMap { match -> (code: String, distance: Int)? in
            let before = source.substring(to: match.range.location)
            if currency.firstMatch(in: before, range: NSRange(location: 0, length: (before as NSString).length)) != nil {
                return nil
            }
            let code = source.substring(with: match.range).filter(\.isNumber)
            let distance = marks.map { abs($0 - match.range.location) }.min()!
            return (code, distance)
        }
        return codes.min { $0.distance < $1.distance }?.code
    }
}
