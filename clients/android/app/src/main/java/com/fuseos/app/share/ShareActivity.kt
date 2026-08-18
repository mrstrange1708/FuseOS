package com.fuseos.app.share

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.lifecycle.lifecycleScope
import com.fuseos.app.data.ServiceLocator
import com.fuseos.app.service.FuseConnectionService
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
 */
class ShareActivity : ComponentActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val text = intent?.getStringExtra(Intent.EXTRA_TEXT)
        val uri = intent?.let { streamExtra(it) }
        if (text == null && uri == null) {
            finishWith("Nothing to send.")
            return
        }

        // The process may have been dead until this moment, so the whole stack has to come
        // up before anything can be sent. Starting the service first means the connection
        // then stays up, rather than being torn down the instant this activity finishes.
        FuseConnectionService.start(this)

        lifecycleScope.launch {
            val sent = withContext(Dispatchers.IO) { send(text, uri) }
            finishWith(
                when (sent) {
                    SendResult.Sent -> "Sent to your devices."
                    SendResult.NoPeer -> "No device connected. Open FuseOS on your Mac."
                    SendResult.TooBig -> "That image is too large to send."
                    SendResult.Failed -> "Couldn't send that."
                },
            )
        }
    }

    private enum class SendResult { Sent, NoPeer, TooBig, Failed }

    private suspend fun send(text: String?, uri: Uri?): SendResult {
        val transport = ServiceLocator.lanTransport
        // Registration can hit the network; without a bound deadline a share started on a
        // dead network would hang this activity over the user's screen indefinitely.
        val started = withTimeoutOrNull(CONNECT_TIMEOUT_MS) {
            runCatching { ServiceLocator.connectionManager.ensureStarted() }.getOrNull()
        } ?: return SendResult.Failed

        // A channel is dialled, not instant. Waiting beats failing on a peer that is about
        // to be there — but only briefly, because the user is staring at a frozen share.
        val connected = withTimeoutOrNull(CONNECT_TIMEOUT_MS) {
            transport.connectedPeers.first { it.isNotEmpty() }
        }
        if (connected.isNullOrEmpty()) return SendResult.NoPeer

        val bytes = uri?.let { readBytes(it) }
        if (uri != null && bytes == null) return SendResult.Failed

        val ok = ServiceLocator.clipboardSync.share(
            text = text,
            imageBytes = bytes,
            mime = uri?.let { contentResolver.getType(it) },
        )
        // The only rejection `share` reports for a non-empty image is the size cap.
        return if (ok) SendResult.Sent else if (bytes != null) SendResult.TooBig else SendResult.Failed
    }

    /** Reads the shared image fully; a URI is a grant we hold only while this task lives. */
    private fun readBytes(uri: Uri): ByteArray? = runCatching {
        contentResolver.openInputStream(uri)?.use { it.readBytes() }
    }.getOrNull()

    private fun streamExtra(intent: Intent): Uri? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
        } else {
            @Suppress("DEPRECATION")
            intent.getParcelableExtra(Intent.EXTRA_STREAM)
        }

    private fun finishWith(message: String) {
        Toast.makeText(this, message, Toast.LENGTH_SHORT).show()
        finish()
    }

    private companion object {
        /** Long enough to dial a peer on a LAN, short enough not to feel hung. */
        const val CONNECT_TIMEOUT_MS = 6_000L
    }
}
