package com.fuseos.app.capture

import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.lifecycle.lifecycleScope
import com.fuseos.app.data.ServiceLocator
import com.fuseos.app.service.FuseConnectionService
import com.fuseos.app.ui.island.ClipIsland
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull

/**
 * Reads the clipboard on demand and offers it to the island.
 *
 * It exists purely to hold input focus for a few frames. Android refuses a clipboard read
 * to any app that isn't the focused window (API 29+), and no service, permission or
 * manifest flag lifts that — so the only way to see what the user copied, from the Quick
 * Settings tile or the ongoing notification, is to *be* the focused window for an instant.
 * This activity is invisible, reads the clip the moment focus lands, hands it to
 * [ClipIsland], and finishes. The island then survives it, because the island is a
 * separate overlay window and not part of this task.
 *
 * The remaining tap is the cost of the platform restriction, not of the design. When
 * FuseOS is the default keyboard the IME is exempt from the same check, and the island can
 * be driven straight from the clipboard listener with no activity and no tap at all.
 */
class CaptureActivity : ComponentActivity() {

    private var handled = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // The connection may be down or the process freshly resurrected; bringing it up
        // here means the tap that captured is also the tap that reconnects.
        FuseConnectionService.start(this)
    }

    /**
     * The clipboard read happens here, not in `onCreate` — focus is what the framework
     * checks, and it has not been granted yet when the activity is merely created.
     */
    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (!hasFocus || handled) return
        handled = true

        val island = ServiceLocator.clipIsland
        if (!island.canDraw()) {
            // No overlay permission means there is nowhere to draw the prompt. Send it
            // outright rather than dropping it, and point the user at the setting once.
            sendDirectly()
            return
        }

        val clip = ServiceLocator.clipboardSync.capture()
        if (clip == null) {
            island.status(title = "Nothing to send", subtitle = "Your clipboard is empty")
        } else {
            island.prompt(clip) { pending ->
                // On the app scope, not this activity's: the tap happens seconds after
                // this activity has finished, so its scope is long gone by then.
                ServiceLocator.appScope.launch(Dispatchers.IO) {
                    ServiceLocator.clipboardSync.send(pending)
                }
            }
        }
        finish()
        // The island is the transition; a task animation on top of it reads as a flicker.
        overridePendingTransition(0, 0)
    }

    /** Overlay permission refused: behave like a Share-sheet send and say so in a toast. */
    private fun sendDirectly() {
        lifecycleScope.launch {
            val message = withContext(Dispatchers.IO) {
                val ready = withTimeoutOrNull(CONNECT_TIMEOUT_MS) {
                    runCatching { ServiceLocator.connectionManager.ensureStarted() }.getOrNull()
                }
                if (ready == null) return@withContext "Couldn't connect."
                val peers = withTimeoutOrNull(CONNECT_TIMEOUT_MS) {
                    ServiceLocator.lanTransport.connectedPeers.first { it.isNotEmpty() }
                }
                if (peers.isNullOrEmpty()) return@withContext "No device connected."
                val clip = ServiceLocator.clipboardSync.capture()
                    ?: return@withContext "Your clipboard is empty."
                if (!ServiceLocator.clipboardSync.send(clip)) return@withContext "Couldn't send that."
                // Naming the missing permission, because from here the send looks like it
                // worked and the island looks broken — and the fix is two taps away.
                "Sent. Turn on the island in FuseOS → Profile."
            }
            Toast.makeText(this@CaptureActivity, message, Toast.LENGTH_SHORT).show()
            finish()
        }
    }

    companion object {
        /** Long enough to dial a peer on a LAN, short enough not to feel hung. */
        private const val CONNECT_TIMEOUT_MS = 6_000L

        fun intent(context: Context): Intent =
            Intent(context, CaptureActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK)
    }
}
