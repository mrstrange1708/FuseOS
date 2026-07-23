package com.fuseos.app.clipboard

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import androidx.core.content.FileProvider
import com.fuseos.app.net.LanTransport
import com.fuseos.proto.ClipImage
import com.fuseos.proto.ClipText
import com.fuseos.proto.Envelope
import com.google.protobuf.ByteString
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File

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
            transport.incoming.collect { envelope -> apply(guard, envelope) }
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
        // Images first: an image on the clipboard is a content URI, and coercing that to
        // text yields the URI string, which would sync a useless "content://…" instead.
        val image = currentImage()
        if (image != null) {
            val (mime, bytes) = image
            if (bytes.size > MAX_INLINE_IMAGE_BYTES) return // see the constant
            if (!guard.shouldEmit(LoopGuard.hash(bytes))) return
            broadcast {
                it.setClipImage(
                    ClipImage.newBuilder()
                        .setMime(mime)
                        .setData(ByteString.copyFrom(bytes)),
                )
            }
            return
        }

        val text = currentText() ?: return
        if (!guard.shouldEmit(LoopGuard.hash(text))) return
        broadcast { it.setClipText(ClipText.newBuilder().setText(text)) }
    }

    /** The listener fires on the main thread; socket writes must not. */
    private fun broadcast(body: (Envelope.Builder) -> Envelope.Builder) {
        scope.launch(Dispatchers.IO) {
            transport.broadcast(body(transport.newEnvelope()).build())
        }
    }

    private suspend fun apply(guard: LoopGuard, envelope: Envelope) {
        val content = when (envelope.bodyCase) {
            Envelope.BodyCase.CLIP_TEXT ->
                envelope.clipText.text.takeIf { it.isNotEmpty() }?.let { it to LoopGuard.hash(it) }
            Envelope.BodyCase.CLIP_IMAGE ->
                envelope.clipImage.takeIf { !it.data.isEmpty }
                    ?.let { it to LoopGuard.hash(it.data.toByteArray()) }
            else -> null
        } ?: return

        val (payload, hash) = content
        if (!guard.shouldApply(envelope.sourceDeviceId, envelope.seq, envelope.sentAtUnixMs)) {
            return
        }
        // Record before writing: setPrimaryClip can notify the listener synchronously, and
        // the suppression has to already be in place when it does.
        guard.recordApplied(hash, envelope.sentAtUnixMs)

        val clip = when (payload) {
            is String -> ClipData.newPlainText("FuseOS", payload)
            is ClipImage -> imageClip(payload) ?: return
            else -> return
        }
        withContext(Dispatchers.Main) { clipboard.setPrimaryClip(clip) }
    }

    /**
     * Android can only put an image on the clipboard as a content URI, so the bytes go to
     * a cache file exposed through [androidx.core.content.FileProvider].
     */
    private fun imageClip(image: ClipImage): ClipData? = runCatching {
        val directory = File(appContext.cacheDir, "clipboard").apply { mkdirs() }
        val file = File(directory, "incoming.${extensionFor(image.mime)}")
        file.writeBytes(image.data.toByteArray())
        val uri = FileProvider.getUriForFile(
            appContext, "${appContext.packageName}.fileprovider", file,
        )
        ClipData.newUri(appContext.contentResolver, "FuseOS", uri)
    }.getOrNull()

    private fun extensionFor(mime: String): String = when (mime) {
        "image/jpeg" -> "jpg"
        "image/gif" -> "gif"
        "image/webp" -> "webp"
        else -> "png"
    }

    /** Returns null when the clipboard holds no image, which is the normal case. */
    private fun currentImage(): Pair<String, ByteArray>? = runCatching {
        val clip = clipboard.primaryClip ?: return null
        if (clip.itemCount == 0) return null
        val uri = clip.getItemAt(0).uri ?: return null
        val mime = appContext.contentResolver.getType(uri) ?: return null
        if (!mime.startsWith("image/")) return null
        val bytes = appContext.contentResolver.openInputStream(uri)?.use { it.readBytes() }
            ?: return null
        mime to bytes
    }.getOrNull()

    /** Returns null when the clipboard is empty, non-text, or unreadable in the
     *  background — which is the normal case, not an error. */
    private fun currentText(): String? = runCatching {
        val clip = clipboard.primaryClip ?: return null
        if (clip.itemCount == 0) return null
        clip.getItemAt(0).coerceToText(appContext)?.toString()?.takeIf { it.isNotEmpty() }
    }.getOrNull()

    private companion object {
        /**
         * Images ride inline in a single `ClipImage` frame rather than being chunked.
         * A screenshot is typically 1–2 MB, one frame on a LAN is faster than a chunked
         * stream, and `LanChannel` already caps a frame at 4 MB. Anything larger is not
         * synced today; it will be covered when file transfer lands and brings
         * FileMeta/FileChunk reassembly with it.
         */
        const val MAX_INLINE_IMAGE_BYTES = 3 * 1024 * 1024
    }
}
