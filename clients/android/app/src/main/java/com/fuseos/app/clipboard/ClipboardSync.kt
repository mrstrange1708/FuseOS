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
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File

/**
 * One entry in the visible clipboard history. [imageBytes] is null for text and the raw
 * encoded image otherwise — the same bytes that crossed the wire, so re-copying an old
 * item needs no re-encode. Mirrors `ClipEntry` on macOS.
 */
data class ClipEntry(
    val id: Long,
    val text: String?,
    val imageBytes: ByteArray?,
    val mime: String?,
    /** True when this device copied it, false when it arrived from a peer. */
    val fromSelf: Boolean,
    val atUnixMs: Long,
) {
    val isImage: Boolean get() = imageBytes != null

    // ByteArray gives data classes reference equality, which would make two identical
    // entries compare unequal and defeat any list diffing that leans on it.
    override fun equals(other: Any?): Boolean = other is ClipEntry && other.id == id
    override fun hashCode(): Int = id.hashCode()
}

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

    private val _history = MutableStateFlow<List<ClipEntry>>(emptyList())

    /** Newest first. In memory only — clipboard content is never written to disk here. */
    val history: StateFlow<List<ClipEntry>> = _history.asStateFlow()

    private var nextId = 0L

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
        // Sign-out must not leave the last user's copied content on screen.
        _history.value = emptyList()
    }

    /**
     * Adds to the visible history, newest first, and evicts to keep it bounded.
     *
     * Two caps, because entries are wildly uneven: [MAX_ENTRIES] keeps the list readable,
     * and [MAX_HISTORY_BYTES] keeps 50 screenshots from pinning 150 MB of heap.
     */
    private fun record(text: String?, imageBytes: ByteArray?, mime: String?, fromSelf: Boolean) {
        val entry = ClipEntry(
            id = nextId++,
            text = text,
            imageBytes = imageBytes,
            mime = mime,
            fromSelf = fromSelf,
            atUnixMs = System.currentTimeMillis(),
        )
        _history.update { current ->
            val trimmed = (listOf(entry) + current).take(MAX_ENTRIES)
            var bytes = 0L
            trimmed.takeWhile {
                bytes += it.imageBytes?.size ?: it.text?.length ?: 0
                bytes <= MAX_HISTORY_BYTES
            }
        }
    }

    /** Put a history entry back on this device's clipboard — the point of a history. */
    fun copyToClipboard(entry: ClipEntry) {
        // Goes through the same guard as an inbound apply, so re-copying an old item
        // isn't mistaken for a fresh local copy and rebroadcast to the peer.
        val hash = entry.imageBytes?.let { LoopGuard.hash(it) }
            ?: entry.text?.let { LoopGuard.hash(it) } ?: return
        guard?.recordApplied(hash, System.currentTimeMillis())
        val clip = when {
            entry.imageBytes != null -> imageClip(
                ClipImage.newBuilder()
                    .setMime(entry.mime.orEmpty())
                    .setData(ByteString.copyFrom(entry.imageBytes))
                    .build(),
            ) ?: return
            else -> ClipData.newPlainText("FuseOS", entry.text)
        }
        clipboard.setPrimaryClip(clip)
    }

    /**
     * Sends content the user explicitly shared, bypassing the clipboard entirely.
     *
     * This is the Share sheet's path, and the only way anything leaves this device while
     * FuseOS is off screen. No loop guard is involved: nothing is written to the local
     * clipboard here, so there is no echo to suppress.
     *
     * Returns false when the payload is unusable — an oversized image, or empty text — so
     * the caller can tell the user rather than silently dropping it.
     */
    fun share(text: String?, imageBytes: ByteArray?, mime: String?): Boolean {
        if (imageBytes != null) {
            if (imageBytes.isEmpty() || imageBytes.size > MAX_INLINE_IMAGE_BYTES) return false
            record(text = null, imageBytes = imageBytes, mime = mime, fromSelf = true)
            broadcast {
                it.setClipImage(
                    ClipImage.newBuilder()
                        .setMime(mime.orEmpty())
                        .setData(ByteString.copyFrom(imageBytes)),
                )
            }
            return true
        }
        val body = text?.takeIf { it.isNotEmpty() } ?: return false
        record(text = body, imageBytes = null, mime = null, fromSelf = true)
        broadcast { it.setClipText(ClipText.newBuilder().setText(body)) }
        return true
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
            record(text = null, imageBytes = bytes, mime = mime, fromSelf = true)
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
        record(text = text, imageBytes = null, mime = null, fromSelf = true)
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

        when (payload) {
            is String -> record(payload, null, null, fromSelf = false)
            is ClipImage -> record(null, payload.data.toByteArray(), payload.mime, fromSelf = false)
        }

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

        const val MAX_ENTRIES = 50
        const val MAX_HISTORY_BYTES = 24L * 1024 * 1024
    }
}
