package com.fuseos.app.core

/**
 * The pairing-code format, mirrored from the server (see `docs/api.md`): 8 uppercase
 * alphanumerics shown grouped as `XXXX-XXXX`. The macOS client has the same rules in
 * `FuseOSCore/PairingCode.swift` — keep the two in step.
 */
object PairingCode {
    const val LENGTH = 8

    /** The scheme a scanned QR carries, so a stray QR isn't mistaken for a code. */
    const val URI_PREFIX = "fuseos://pair?code="

    /**
     * Drop formatting and case so what the user typed matches what the server stored:
     * "a7x2-9qkm" and "A7X2 9QKM" both become "A7X29QKM". Lenient in the same way the
     * server's claim endpoint is, and capped at [LENGTH] so a paste can't overflow the
     * boxes.
     */
    fun normalize(input: String): String =
        input.uppercase().filter { it.isLetterOrDigit() && it.code < 128 }.take(LENGTH)

    /** "A7X29QKM" -> "A7X2-9QKM". Partial input groups as far as it reaches. */
    fun grouped(code: String): String =
        if (code.length <= 4) code else code.take(4) + "-" + code.drop(4)

    /** What the initiating device puts in its QR. */
    fun uri(code: String): String = URI_PREFIX + grouped(normalize(code))

    /** A complete code, with or without its separator — nothing else. */
    private val BARE = Regex("^[A-Za-z0-9]{4}[-\\s]?[A-Za-z0-9]{4}$")

    /**
     * Read a code out of a scanned QR. Accepts the `fuseos://pair?code=` URI and a bare
     * code, and returns null for anything else — a camera points at whatever is in front
     * of it, so this is a trust boundary, not a parser. Matching loosely here would turn
     * any QR in the room into eight characters we'd send to `/pairing/claim`.
     */
    fun fromScan(payload: String): String? {
        val trimmed = payload.trim()
        val candidate = if (trimmed.startsWith(URI_PREFIX, ignoreCase = true)) {
            trimmed.substring(URI_PREFIX.length)
        } else {
            trimmed
        }
        return if (BARE.matches(candidate)) normalize(candidate) else null
    }
}
