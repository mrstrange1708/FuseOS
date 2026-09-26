package com.fuseos.app.clipboard

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import androidx.core.content.FileProvider
import com.fuseos.app.net.LanTransport
import com.fuseos.proto.ClipImage
import com.fuseos.proto.ClipText
import com.fuseos.proto.Envelope
import com.fuseos.proto.HistoryItem
import com.fuseos.proto.HistorySync
import com.google.protobuf.ByteString
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asSharedFlow
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
 * Clipboard content read but not yet sent — what the island offers the user before they
 * tap it. Separate from [ClipEntry] because nothing has happened yet: no id, no history
 * row, no wire event. Produced by [ClipboardSync.capture], consumed by [ClipboardSync.send].
 */
data class PendingClip(val text: String?, val imageBytes: ByteArray?, val mime: String?) {
    override fun equals(other: Any?): Boolean =
        other is PendingClip && other.text == text && other.mime == mime &&
            other.imageBytes.contentEquals(imageBytes)

    override fun hashCode(): Int =
        (text?.hashCode() ?: 0) * 31 + (imageBytes?.contentHashCode() ?: 0)
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
    private val store = ClipHistoryStore(File(appContext.filesDir, "clip-history"))
    private val clipboard =
        appContext.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager

    private var guard: LoopGuard? = null
    private var listener: ClipboardManager.OnPrimaryClipChangedListener? = null
    private var inboundJob: Job? = null
    private var joinJob: Job? = null

    private val _history = MutableStateFlow<List<ClipEntry>>(emptyList())

    // Buffered and non-suspending: a clip must never block the clipboard listener or a
    // socket read waiting on whoever is drawing the island.
    private val _events = MutableSharedFlow<ClipEntry>(extraBufferCapacity = 8)

    /** Every clip that moves, in either direction, as it happens. Drives the island. */
    val events: SharedFlow<ClipEntry> = _events.asSharedFlow()

    /** Newest first. In memory only — clipboard content is never written to disk here. */
    val history: StateFlow<List<ClipEntry>> = _history.asStateFlow()

    // Restored ids continue upward rather than restarting, so a reloaded entry and a fresh
    // one can never collide in a list keyed by id.
    private var nextId = 0L

    fun start(selfDeviceId: String) {
        stop()
        val restored = store.load()
        _history.value = restored
        nextId = (restored.maxOfOrNull { it.id } ?: -1L) + 1
        val guard = LoopGuard(selfDeviceId)
        this.guard = guard

        val listener = ClipboardManager.OnPrimaryClipChangedListener { onLocalChange(guard) }
        this.listener = listener
        clipboard.addPrimaryClipChangedListener(listener)

        inboundJob = scope.launch {
            transport.incoming.collect { envelope -> apply(guard, envelope) }
        }
        // Both ends send their history whenever a peer gains a channel; each merges what
        // it lacks.
        joinJob = scope.launch {
            var previous = emptySet<String>()
            transport.connectedPeers.collect { now ->
                if ((now - previous).isNotEmpty()) sendHistory()
                previous = now
            }
        }
    }

    fun stop() {
        listener?.let { clipboard.removePrimaryClipChangedListener(it) }
        listener = null
        inboundJob?.cancel()
        inboundJob = null
        joinJob?.cancel()
        joinJob = null
        guard = null
        // Backgrounding calls this too, so the list is only cleared from memory; what is
        // on disk is what a relaunch restores. `forget()` is the sign-out path.
        _history.value = emptyList()
    }

    /** Sign-out: drop the history from memory *and* disk. */
    fun forget() {
        stop()
        store.clear()
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
        commit { current -> listOf(entry) + current }
        _events.tryEmit(entry)
    }

    /** Applies [change] to the history, trims it to the caps, and persists it. */
    private fun commit(change: (List<ClipEntry>) -> List<ClipEntry>) {
        _history.update { current ->
            val trimmed = change(current).take(MAX_ENTRIES)
            var bytes = 0L
            trimmed.takeWhile {
                bytes += it.imageBytes?.size ?: it.text?.length ?: 0
                bytes <= MAX_HISTORY_BYTES
            }
        }
        // Written on every change so an app the OS kills without warning — the norm on
        // Android — still has its history on the next launch.
        scope.launch(Dispatchers.IO) { store.save(_history.value) }
    }

    /**
     * Sends our recent history to peers (`HistorySync` in the proto), newest first,
     * stopping short of the channel's frame cap. An image too big for what is left of the
     * budget is skipped rather than ending the list.
     */
    private fun sendHistory() {
        var budget = MAX_HISTORY_SYNC_BYTES
        val items = _history.value.mapNotNull { entry ->
            val size = entry.imageBytes?.size ?: entry.text?.toByteArray()?.size ?: 0
            if (size > budget) return@mapNotNull null
            budget -= size
            HistoryItem.newBuilder().apply {
                if (entry.imageBytes != null) {
                    imageData = ByteString.copyFrom(entry.imageBytes)
                    imageMime = entry.mime ?: "image/png"
                } else {
                    text = entry.text.orEmpty()
                }
                atUnixMs = entry.atUnixMs
            }.build()
        }
        if (items.isEmpty()) return
        broadcast { it.setHistorySync(HistorySync.newBuilder().addAllItems(items)) }
    }

    /**
     * Folds a peer's history into ours: the entries we lack, at the time they were first
     * copied. History only — the clipboard is not touched, the island stays quiet, and
     * nothing is sent back, which is what keeps this from looping.
     */
    internal fun merge(sync: HistorySync) {
        commit { current ->
            val known = current.mapNotNull(::contentHash).toMutableSet()
            val added = sync.itemsList.mapNotNull { item ->
                val isImage = !item.imageData.isEmpty
                if (!isImage && item.text.isEmpty()) return@mapNotNull null
                val hash = if (isImage) LoopGuard.hash(item.imageData.toByteArray()) else LoopGuard.hash(item.text)
                if (!known.add(hash)) return@mapNotNull null
                ClipEntry(
                    id = nextId++,
                    text = item.text.takeIf { !isImage },
                    imageBytes = item.imageData.toByteArray().takeIf { isImage },
                    mime = item.imageMime.takeIf { isImage },
                    fromSelf = false,
                    atUnixMs = item.atUnixMs,
                )
            }
            (current + added).sortedByDescending { it.atUnixMs }
        }
    }

    private fun contentHash(entry: ClipEntry): String? =
        entry.imageBytes?.let { LoopGuard.hash(it) } ?: entry.text?.let { LoopGuard.hash(it) }

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

    /**
     * Sends whatever is on the clipboard right now, on the user's explicit request.
     *
     * The nav bar's centre button. Reading the clipboard succeeds here because the app is
     * on screen — the same reason automatic capture only works in the foreground.
     * Returns false when there is nothing readable to send.
     */
    fun sendCurrent(): Boolean {
        val image = currentImage()
        if (image != null) {
            val (mime, bytes) = image
            return share(text = null, imageBytes = bytes, mime = mime)
        }
        return share(text = currentText(), imageBytes = null, mime = null)
    }

    /**
     * Reads the clipboard without sending anything.
     *
     * The island's prompt needs the content in hand *before* the user decides, and the
     * overlay window itself is unfocusable and so cannot read the clipboard. So the read
     * happens in a focused activity, the bytes are carried here, and [send] finishes the
     * job if the user taps. Returns null when there is nothing usable to offer.
     */
    fun capture(): PendingClip? {
        val image = currentImage()
        if (image != null) {
            val (mime, bytes) = image
            if (bytes.isEmpty() || bytes.size > MAX_INLINE_IMAGE_BYTES) return null
            return PendingClip(text = null, imageBytes = bytes, mime = mime)
        }
        return currentText()?.let { PendingClip(text = it, imageBytes = null, mime = null) }
    }

    /** Sends a clip taken earlier by [capture]. Same path as a Share-sheet send. */
    fun send(clip: PendingClip): Boolean = share(clip.text, clip.imageBytes, clip.mime)

    /**
     * Offered a local copy, decides what it does next.
     *
     * Set, and a copy is *proposed* — the island asks before anything leaves the device.
     * Unset, and a copy is sent outright, which is the behaviour when there is nowhere to
     * draw a prompt. Asking is the default because not everything a person copies is
     * something they want on another machine, and a password manager's clipboard is the
     * obvious case.
     *
     * ponytail: prompt-always. If the taps become the annoyance rather than the
     * safeguard, sending outright is this callback left null.
     */
    var onLocalCopy: ((PendingClip) -> Unit)? = null

    /** A local copy — offer it unless it is the echo of something we just injected. */
    private fun onLocalChange(guard: LoopGuard) {
        val clip = capture() ?: return
        // Images hash by bytes and text by string, exactly as the emit path always has;
        // getting this wrong would either loop injected content back or silence a real copy.
        val hash = clip.imageBytes?.let { LoopGuard.hash(it) } ?: LoopGuard.hash(clip.text.orEmpty())
        if (!guard.shouldEmit(hash)) return

        val offer = onLocalCopy
        if (offer != null) offer(clip) else send(clip)
    }

    /** The listener fires on the main thread; socket writes must not. */
    private fun broadcast(body: (Envelope.Builder) -> Envelope.Builder) {
        scope.launch(Dispatchers.IO) {
            transport.broadcast(body(transport.newEnvelope()).build())
        }
    }

    private suspend fun apply(guard: LoopGuard, envelope: Envelope) {
        if (envelope.bodyCase == Envelope.BodyCase.HISTORY_SYNC) {
            merge(envelope.historySync)
            return
        }
        val content = when (envelope.bodyCase) {
            Envelope.BodyCase.CLIP_TEXT ->
                envelope.clipText.text.takeIf { it.isNotEmpty() }?.let { it to LoopGuard.hash(it) }
            Envelope.BodyCase.CLIP_IMAGE ->
                envelope.clipImage.takeIf { !it.data.isEmpty }
                    ?.let { it to LoopGuard.hash(it.data.toByteArray()) }
            else -> null
        } ?: return

        val (payload, hash) = content
        if (!guard.shouldApply(
                envelope.sourceDeviceId,
                envelope.sessionId,
                envelope.seq,
                envelope.sentAtUnixMs,
            )
        ) {
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

    companion object {
        /**
         * Images ride inline in a single `ClipImage` frame rather than being chunked.
         * A screenshot is typically 1–2 MB, one frame on a LAN is faster than a chunked
         * stream, and `LanChannel` already caps a frame at 4 MB. A larger image shared
         * from the Share sheet goes as a file transfer instead (see ShareActivity).
         */
        const val MAX_INLINE_IMAGE_BYTES = 3 * 1024 * 1024

        private const val MAX_ENTRIES = 50
        private const val MAX_HISTORY_BYTES = 24L * 1024 * 1024

        /** One `HistorySync` frame, with headroom under `LanChannel`'s 4 MB frame cap. */
        private const val MAX_HISTORY_SYNC_BYTES = 3 * 1024 * 1024
    }
}
