package com.fuseos.app.clipboard

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import com.fuseos.app.net.LanTransport
import com.fuseos.proto.ClipText
import com.fuseos.proto.Envelope
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * Mirrors the clipboard to paired devices over the LAN data plane.
 *
 * **Android only lets the focused app read the clipboard** (API 29+; API 31+ also shows a
 * toast on every read). No permission lifts this. So outbound capture works while FuseOS
 * is on screen and not otherwise — the Share sheet is the intended background path out of
 * Android. Injection is unrestricted, so macOS → Android always works. See
 * `docs/protocol.md`.
 *
 * All loop-prevention lives in [LoopGuard]; this class only bridges it to the platform.
 */
class ClipboardSync(
    context: Context,
    private val transport: LanTransport,
    private val scope: CoroutineScope,
) {
    private val appContext = context.applicationContext
    private val clipboard =
        appContext.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager

    private var guard: LoopGuard? = null
    private var listener: ClipboardManager.OnPrimaryClipChangedListener? = null
    private var inboundJob: Job? = null

    fun start(selfDeviceId: String) {
        stop()
        val guard = LoopGuard(selfDeviceId)
        this.guard = guard

        val listener = ClipboardManager.OnPrimaryClipChangedListener { onLocalChange(guard) }
        this.listener = listener
        clipboard.addPrimaryClipChangedListener(listener)

        inboundJob = scope.launch {
            transport.incoming.collect { envelope ->
                if (envelope.bodyCase == Envelope.BodyCase.CLIP_TEXT) apply(guard, envelope)
            }
        }
    }

    fun stop() {
        listener?.let { clipboard.removePrimaryClipChangedListener(it) }
        listener = null
        inboundJob?.cancel()
        inboundJob = null
        guard = null
    }

    /** A local copy — broadcast it unless it is the echo of something we just injected. */
    private fun onLocalChange(guard: LoopGuard) {
        val text = currentText() ?: return
        if (!guard.shouldEmit(LoopGuard.hash(text))) return
        // The listener fires on the main thread; socket writes must not.
        scope.launch(Dispatchers.IO) {
            transport.broadcast(
                transport.newEnvelope()
                    .setClipText(ClipText.newBuilder().setText(text))
                    .build(),
            )
        }
    }

    private suspend fun apply(guard: LoopGuard, envelope: Envelope) {
        val text = envelope.clipText.text
        if (text.isEmpty()) return
        if (!guard.shouldApply(envelope.sourceDeviceId, envelope.seq, envelope.sentAtUnixMs)) {
            return
        }
        // Record before writing: setPrimaryClip can notify the listener synchronously, and
        // the suppression has to already be in place when it does.
        guard.recordApplied(LoopGuard.hash(text), envelope.sentAtUnixMs)
        withContext(Dispatchers.Main) {
            clipboard.setPrimaryClip(ClipData.newPlainText("FuseOS", text))
        }
    }

    /** Returns null when the clipboard is empty, non-text, or unreadable in the
     *  background — which is the normal case, not an error. */
    private fun currentText(): String? = runCatching {
        val clip = clipboard.primaryClip ?: return null
        if (clip.itemCount == 0) return null
        clip.getItemAt(0).coerceToText(appContext)?.toString()?.takeIf { it.isNotEmpty() }
    }.getOrNull()
}
