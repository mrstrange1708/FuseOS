package com.fuseos.app.ui

import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.Shader
import com.fuseos.app.BuildConfig
import com.fuseos.app.data.DeviceItem
import com.fuseos.app.data.PeerPresence
import com.fuseos.app.file.TransferProgress
import com.fuseos.app.ui.dashboard.DashboardViewModel
import com.fuseos.proto.HistoryItem
import com.fuseos.proto.HistorySync
import com.google.protobuf.ByteString
import java.io.ByteArrayOutputStream

/**
 * Design review without a Mac or a server: a debug build launched with
 * `adb shell am start -n com.fuseos.app/.MainActivity --ez fuse_demo true` skips sign-in and
 * networking and shows the real screens filled with sample devices, clips and transfers.
 * The Android twin of `DemoMode` on macOS. Release builds have no way in.
 */
object DemoMode {
    var isOn = false
        private set

    fun enableFrom(intent: Intent) {
        isOn = BuildConfig.DEBUG && intent.getBooleanExtra("fuse_demo", false)
    }

    private val phone = DeviceItem("phone", "Pixel 9a", "android", online = true, battery = 82, isSelf = true)
    private val mac = DeviceItem("mac", "Junaid's MacBook Pro", "macos", online = true, battery = 64, trusted = true)

    fun state() = DashboardViewModel.UiState(
        selfDevice = phone,
        allPeers = listOf(mac),
        presence = mapOf(mac.id to PeerPresence(online = true, battery = 64, publicKey = null, lanAddress = null)),
        connected = setOf(mac.id),
    )

    fun history(): HistorySync {
        val now = System.currentTimeMillis()
        fun text(t: String, agoMin: Long) = HistoryItem.newBuilder().setText(t).setAtUnixMs(now - agoMin * 60_000).build()
        return HistorySync.newBuilder()
            .addItems(text("https://github.com/mrstrange1708/FuseOS/pull/3", 1))
            .addItems(text("Meet at the café on 5th at 7 — I'll grab a table by the window.", 10))
            .addItems(
                HistoryItem.newBuilder().setImageMime("image/png").setImageData(ByteString.copyFrom(sampleImage()))
                    .setAtUnixMs(now - 30 * 60_000).build(),
            )
            .addItems(text("import numpy as np\nfrom sklearn.preprocessing import StandardScaler", 60))
            .addItems(text("OTP 482913", 120))
            .build()
    }

    fun transfers() = listOf(
        TransferProgress("t1", "Quarterly report.pdf", outgoing = true, bytes = 6_400_000, total = 10_000_000, state = TransferProgress.State.Active),
        TransferProgress("t2", "IMG_2041.HEIC", outgoing = false, bytes = 3_100_000, total = 3_100_000, state = TransferProgress.State.Done),
    )

    private fun sampleImage(): ByteArray {
        val bitmap = Bitmap.createBitmap(480, 300, Bitmap.Config.ARGB_8888)
        Canvas(bitmap).drawRect(
            0f, 0f, 480f, 300f,
            Paint().apply {
                shader = LinearGradient(0f, 0f, 480f, 300f, 0xFFFA8C4C.toInt(), 0xFF59338C.toInt(), Shader.TileMode.CLAMP)
            },
        )
        return ByteArrayOutputStream().also { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }.toByteArray()
    }
}
