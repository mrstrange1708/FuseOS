package com.fuseos.app.share

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.util.Log
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.lifecycle.lifecycleScope
import com.fuseos.app.clipboard.ClipboardSync
import com.fuseos.app.data.ServiceLocator
import com.fuseos.app.file.Transfers
import com.fuseos.app.service.FuseConnectionService
import java.io.File
import java.util.UUID
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull

/**
 * Receives a Share-sheet send and pushes it to the paired devices.
 *
 * On Android this is not a convenience feature. Clipboard reads are refused to any app
 * that isn't on screen, so with FuseOS closed this is the *only* route content has off the
 * phone (`docs/protocol.md`). It has no UI: it does the work, says what happened in a
 * toast, and finishes over whatever the user was actually looking at.
 *
 * What it does with the content:
 * - text, or one small image → the Mac's clipboard, ready to paste;
 * - anything else (a PDF, a video, a large photo, several files) → a file transfer, which
 *   lands in the Mac's Downloads.
 */
class ShareActivity : ComponentActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val text = intent?.getStringExtra(Intent.EXTRA_TEXT)
        val uris = intent?.let { streams(it) }.orEmpty()
        if (text == null && uris.isEmpty()) {
            finishWith("Nothing to send.")
            return
        }

        // The process may have been dead until this moment, so the whole stack has to come
        // up before anything can be sent. Starting the service first means the connection
        // then stays up, rather than being torn down the instant this activity finishes.
        FuseConnectionService.start(this)

        lifecycleScope.launch {
            val message = withContext(Dispatchers.IO) { send(text, uris) }
            Log.i(TAG, "share result: $message")
            finishWith(message)
        }
    }

    private suspend fun send(text: String?, uris: List<Uri>): String {
        val transport = ServiceLocator.lanTransport
        // Registration can hit the network; without a bound deadline a share started on a
        // dead network would hang this activity over the user's screen indefinitely.
        withTimeoutOrNull(CONNECT_TIMEOUT_MS) {
            runCatching { ServiceLocator.connectionManager.ensureStarted() }.getOrNull()
        } ?: return "Couldn't send that."

        // A channel is dialled, not instant. Waiting beats failing on a peer that is about
        // to be there — but only briefly, because the user is staring at a frozen share.
        val connected = withTimeoutOrNull(CONNECT_TIMEOUT_MS) {
            transport.connectedPeers.first { it.isNotEmpty() }
        }
        if (connected.isNullOrEmpty()) return "No device connected. Open FuseOS on your Mac."

        val single = uris.singleOrNull()
        val singleMime = single?.let { contentResolver.getType(it) }
        val size = single?.let { ServiceLocator.transfers.describe(it)?.second }
        val clipImage = single != null && singleMime?.startsWith("image/") == true &&
            size != null && size <= ClipboardSync.MAX_INLINE_IMAGE_BYTES

        if (uris.isEmpty() || clipImage) {
            val bytes = single?.let { readBytes(it) }
            if (single != null && bytes == null) return "Couldn't read that."
            val ok = ServiceLocator.clipboardSync.share(text = text, imageBytes = bytes, mime = singleMime)
            return if (ok) "On your Mac's clipboard." else "Couldn't send that."
        }

        // Files. Text riding along (a caption, a link) still goes to the clipboard.
        text?.let { ServiceLocator.clipboardSync.share(text = it, imageBytes = null, mime = null) }
        var started = 0
        var tooLarge = 0
        for (uri in uris) {
            when (sendAsFile(uri)) {
                Transfers.SendResult.Started -> started++
                Transfers.SendResult.TooLarge -> tooLarge++
                else -> Unit
            }
        }
        return when {
            started == 0 && tooLarge > 0 -> "That's over the 1 GB limit."
            started == 0 -> "Couldn't read that."
            started == 1 -> "Sending to your Mac."
            else -> "Sending $started files to your Mac."
        }
    }

    /**
     * Copies the shared file into app storage and sends the copy.
     *
     * A shared Uri is only readable while this activity is alive, and it finishes as soon
     * as the send starts; the transfer reads the file twice (hash, then stream) after that.
     * ponytail: a copy doubles the disk writes for a large file; hold the activity open
     * behind a progress UI instead if that is ever noticeable.
     */
    private fun sendAsFile(uri: Uri): Transfers.SendResult {
        val transfers = ServiceLocator.transfers
        val (name, size) = transfers.describe(uri) ?: return Transfers.SendResult.Unreadable
        if (size > com.fuseos.app.file.FileTransfer.MAX_FILE_BYTES) return Transfers.SendResult.TooLarge
        val dir = File(cacheDir, "share").apply { mkdirs() }
        val copy = File(dir, UUID.randomUUID().toString())
        val copied = runCatching {
            contentResolver.openInputStream(uri)!!.use { input -> copy.outputStream().use { input.copyTo(it) } }
        }.isSuccess
        if (!copied) {
            copy.delete()
            return Transfers.SendResult.Unreadable
        }
        val mime = contentResolver.getType(uri) ?: "application/octet-stream"
        return transfers.sendCopy(copy, name, mime)
    }

    /** Reads the shared image fully; a URI is a grant we hold only while this task lives. */
    private fun readBytes(uri: Uri): ByteArray? = runCatching {
        contentResolver.openInputStream(uri)?.use { it.readBytes() }
    }.getOrNull()

    private fun streams(intent: Intent): List<Uri> =
        if (intent.action == Intent.ACTION_SEND_MULTIPLE) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM, Uri::class.java)
            } else {
                @Suppress("DEPRECATION")
                intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM)
            }.orEmpty()
        } else {
            listOfNotNull(
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
                } else {
                    @Suppress("DEPRECATION")
                    intent.getParcelableExtra(Intent.EXTRA_STREAM)
                },
            )
        }

    private fun finishWith(message: String) {
        Toast.makeText(this, message, Toast.LENGTH_SHORT).show()
        finish()
    }

    private companion object {
        const val TAG = "FuseShare"

        /** Long enough to dial a peer on a LAN, short enough not to feel hung. */
        const val CONNECT_TIMEOUT_MS = 6_000L
    }
}
