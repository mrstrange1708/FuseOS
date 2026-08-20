package com.fuseos.app.service

import android.app.PendingIntent
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import androidx.annotation.RequiresApi
import com.fuseos.app.capture.CaptureActivity
import com.fuseos.app.data.ServiceLocator

/**
 * "Send clipboard" in the Quick Settings shade.
 *
 * The shortest route out of the phone that Android actually allows. Auto-capture is
 * refused to a background app, so something has to stand in for "the user copied": one
 * pull and one tap, reachable from inside any app and from the lock screen, versus leaving
 * the app you are in to open FuseOS. It launches [CaptureActivity], which is the part that
 * can legally read the clipboard, and the island takes over from there.
 */
@RequiresApi(Build.VERSION_CODES.N)
class ClipTile : TileService() {

    override fun onStartListening() {
        super.onStartListening()
        // Dimmed when there is no one to send to, so the tile tells the truth about
        // whether tapping it will do anything.
        val linked = runCatching {
            ServiceLocator.lanTransport.connectedPeers.value.isNotEmpty()
        }.getOrDefault(false)
        qsTile?.apply {
            state = if (linked) Tile.STATE_ACTIVE else Tile.STATE_INACTIVE
            subtitleCompat(if (linked) "Ready" else "No device")
            updateTile()
        }
    }

    override fun onClick() {
        super.onClick()
        val intent = CaptureActivity.intent(this)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            // API 34 replaced the Intent overload: a tile may only launch through a
            // PendingIntent it owns.
            startActivityAndCollapse(
                PendingIntent.getActivity(
                    this,
                    0,
                    intent,
                    PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
                ),
            )
        } else {
            @Suppress("DEPRECATION")
            startActivityAndCollapse(intent)
        }
    }

    /** `Tile.setSubtitle` is API 29+; below that the tile just carries its label. */
    private fun Tile.subtitleCompat(text: String) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) subtitle = text
    }
}
