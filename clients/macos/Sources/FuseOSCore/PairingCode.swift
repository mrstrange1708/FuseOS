import Foundation

/// The pairing-code format, mirrored from the server (see `docs/api.md`): 8 uppercase
/// alphanumerics shown grouped as `XXXX-XXXX`. The Android client has the same rules in
/// `core/PairingCode.kt` — keep the two in step.
public enum PairingCode {
    public static let length = 8

    /// The scheme the QR carries, so a stray QR isn't mistaken for a code.
    public static let uriPrefix = "fuseos://pair?code="

    /// Drop formatting and case so what the user typed matches what the server stored:
    /// "a7x2-9qkm" and "A7X2 9QKM" both become "A7X29QKM". Lenient in the same way the
    /// server's claim endpoint is, and capped at `length` so a paste can't overflow the
    /// boxes.
    public static func normalize(_ input: String) -> String {
        String(input.uppercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber) }.prefix(length))
    }

    /// "A7X29QKM" -> "A7X2-9QKM". Partial input groups as far as it reaches.
    public static func grouped(_ code: String) -> String {
        guard code.count > 4 else { return code }
        let split = code.index(code.startIndex, offsetBy: 4)
        return "\(code[..<split])-\(code[split...])"
    }

    /// What this device puts in its QR for the other one to scan.
    public static func uri(_ code: String) -> String {
        uriPrefix + grouped(normalize(code))
    }

    /// Read a code out of a scanned QR. Accepts the `fuseos://pair?code=` URI and a bare
    /// code, and returns nil for anything else — a camera points at whatever is in front
    /// of it, so this is a trust boundary, not a parser. Matching loosely here would turn
    /// any QR in the room into eight characters we'd send to `/pairing/claim`.
    public static func fromScan(_ payload: String) -> String? {
        let trimmed = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate = trimmed.lowercased().hasPrefix(uriPrefix)
            ? String(trimmed.dropFirst(uriPrefix.count))
            : trimmed
        return isBareCode(candidate) ? normalize(candidate) : nil
    }

    /// A complete code, with or without its separator — nothing else.
    private static func isBareCode(_ input: String) -> Bool {
        let chars = Array(input)
        func isCodeChar(_ c: Character) -> Bool { c.isASCII && (c.isLetter || c.isNumber) }
        if chars.count == length { return chars.allSatisfy(isCodeChar) }
        if chars.count == length + 1 {
            guard chars[4] == "-" || chars[4] == " " else { return false }
            return chars.enumerated().allSatisfy { $0.offset == 4 || isCodeChar($0.element) }
        }
        return false
    }
}
