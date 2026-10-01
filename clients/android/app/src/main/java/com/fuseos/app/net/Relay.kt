package com.fuseos.app.net

import com.fuseos.proto.Envelope

/**
 * What a relayed channel carries (docs/protocol.md §18): copies, notifications, commands and the
 * channel's own heartbeats. Not files, mirroring, Sidecar or the history catch-up — the relay
 * is a fallback through a small server, rate-limited at 256 KB/s, and those want the LAN.
 */
object Relay {
    /** A copied image or Now Playing artwork larger than this waits for the LAN. */
    const val MAX_ENVELOPE_BYTES = 256 * 1024

    fun carries(envelope: Envelope): Boolean = when (envelope.bodyCase) {
        Envelope.BodyCase.FILE_META, Envelope.BodyCase.FILE_CHUNK, Envelope.BodyCase.FILE_CANCEL,
        Envelope.BodyCase.SCREEN_CONTROL, Envelope.BodyCase.SCREEN_FRAME, Envelope.BodyCase.REMOTE_INPUT,
        Envelope.BodyCase.SIDECAR_CONTROL, Envelope.BodyCase.SIDECAR_FRAME, Envelope.BodyCase.SIDECAR_INPUT,
        Envelope.BodyCase.HISTORY_SYNC,
        -> false
        else -> envelope.serializedSize <= MAX_ENVELOPE_BYTES
    }
}
