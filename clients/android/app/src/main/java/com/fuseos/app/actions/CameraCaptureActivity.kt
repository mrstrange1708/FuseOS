package com.fuseos.app.actions

import android.Manifest
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.os.Bundle
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.content.FileProvider
import androidx.lifecycle.lifecycleScope
import com.fuseos.app.clipboard.ClipboardSync
import com.fuseos.app.data.ServiceLocator
import java.io.ByteArrayOutputStream
import java.io.File
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * Continuity Camera: the Mac asked for a photo. Opens the phone's own camera, and sends
 * what it takes to the Mac's clipboard — ready to paste into whatever is open there.
 */
class CameraCaptureActivity : ComponentActivity() {
    private lateinit var photo: File

    private val capture = registerForActivityResult(ActivityResultContracts.TakePicture()) { taken ->
        if (!taken) {
            finish()
            return@registerForActivityResult
        }
        lifecycleScope.launch {
            val jpeg = withContext(Dispatchers.Default) { fitForClipboard(photo) }
            val sent = jpeg != null && ServiceLocator.clipboardSync.share(null, jpeg, "image/jpeg")
            photo.delete()
            Toast.makeText(
                this@CameraCaptureActivity,
                if (sent) "Sent to your Mac" else "Couldn't send that photo",
                Toast.LENGTH_SHORT,
            ).show()
            finish()
        }
    }

    // FuseOS declares CAMERA (for the link QR), and Android then refuses the system camera
    // intent to an app that declares it without holding it — so ask first.
    private val permission = registerForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        if (granted) openCamera() else finish()
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val directory = File(cacheDir, "clipboard").apply { mkdirs() }
        photo = File(directory, "camera.jpg")
        if (savedInstanceState != null) return
        if (checkSelfPermission(Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED) {
            openCamera()
        } else {
            permission.launch(Manifest.permission.CAMERA)
        }
    }

    private fun openCamera() = capture.launch(FileProvider.getUriForFile(this, "$packageName.fileprovider", photo))

    /**
     * A clip rides in one frame, so the photo is scaled to a 2560 px long side and
     * compressed until it fits [ClipboardSync.MAX_INLINE_IMAGE_BYTES].
     */
    private fun fitForClipboard(file: File): ByteArray? {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(file.path, bounds)
        var sample = 1
        while (maxOf(bounds.outWidth, bounds.outHeight) / (sample * 2) >= LONG_SIDE) sample *= 2
        val bitmap = BitmapFactory.decodeFile(file.path, BitmapFactory.Options().apply { inSampleSize = sample })
            ?: return null
        val scale = minOf(1f, LONG_SIDE.toFloat() / maxOf(bitmap.width, bitmap.height))
        val sized = if (scale < 1f) {
            Bitmap.createScaledBitmap(bitmap, (bitmap.width * scale).toInt(), (bitmap.height * scale).toInt(), true)
        } else {
            bitmap
        }
        for (quality in listOf(88, 75, 60, 45)) {
            val out = ByteArrayOutputStream()
            sized.compress(Bitmap.CompressFormat.JPEG, quality, out)
            if (out.size() <= ClipboardSync.MAX_INLINE_IMAGE_BYTES) return out.toByteArray()
        }
        return null
    }

    private companion object {
        const val LONG_SIDE = 2560
    }
}
