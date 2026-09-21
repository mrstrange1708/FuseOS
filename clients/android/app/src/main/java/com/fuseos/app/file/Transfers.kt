package com.fuseos.app.file

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import android.provider.OpenableColumns
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.FileProvider
import com.fuseos.app.R
import com.fuseos.app.net.LanTransport
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

/**
 * The Android side of [FileTransfer]: what the UI lists, where a received file ends up, and
 * how a picked document becomes a send. [FileTransfer] stays free of Android APIs so it is
 * testable on the JVM; everything that needs a [Context] is here.
 */
class Transfers(
    private val context: Context,
    private val transfer: FileTransfer,
    private val transport: LanTransport,
    private val scope: CoroutineScope,
) {
    private val _list = MutableStateFlow<List<TransferProgress>>(emptyList())

    /** Newest first. Finished rows stay so "did it arrive?" has an answer. */
    val list: StateFlow<List<TransferProgress>> = _list.asStateFlow()

    /** Where a received file was saved, by transfer id: what tapping its row opens. */
    private val saved = mutableMapOf<String, Pair<Uri, String>>()

    enum class SendResult { Started, NoPeer, Unreadable, TooLarge }

    init {
        transfer.onProgress = { progress ->
            _list.update { rows ->
                (listOf(progress) + rows.filter { it.transferId != progress.transferId })
                    // ponytail: newest 20 only; a list of every file ever sent belongs in a
                    // history store, which files do not have yet.
                    .take(MAX_ROWS)
            }
        }
        transfer.onFileReceived = { file -> publish(file) }
    }

    /**
     * Streams a picked document to the connected peer. Returns once the send has started
     * (or could not); progress arrives on [list].
     */
    fun send(uri: Uri): SendResult {
        if (transport.connectedPeers.value.isEmpty()) return SendResult.NoPeer
        val resolver = context.contentResolver
        val (name, size) = resolver.query(
            uri, arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE), null, null, null,
        )?.use { cursor ->
            if (!cursor.moveToFirst()) return SendResult.Unreadable
            // A provider may not know the size (a stream being generated, say). The size goes
            // on the wire before the first chunk, so an unknown one cannot be sent.
            if (cursor.isNull(1)) return SendResult.Unreadable
            (cursor.getString(0) ?: "file") to cursor.getLong(1)
        } ?: return SendResult.Unreadable
        if (size <= 0) return SendResult.Unreadable
        if (size > FileTransfer.MAX_FILE_BYTES) return SendResult.TooLarge
        val mime = resolver.getType(uri) ?: "application/octet-stream"

        // App scope, not the screen's: leaving the screen must not kill a send in flight.
        scope.launch(Dispatchers.IO) {
            transfer.send(name, mime, size) {
                resolver.openInputStream(uri) ?: error("provider returned no stream")
            }
        }
        return SendResult.Started
    }

    fun cancel(transferId: String) {
        scope.launch(Dispatchers.IO) { transfer.cancel(transferId) }
    }

    /** Opens a received file in whatever app handles its type. False if it is gone. */
    fun open(transferId: String): Boolean {
        val (uri, mime) = synchronized(saved) { saved[transferId] } ?: return false
        return runCatching { context.startActivity(viewIntent(uri, mime)) }.isSuccess
    }

    /**
     * Moves a verified file somewhere the user can find it, then says it arrived.
     *
     * API 29+: the public Downloads collection, which needs no permission. Below that,
     * writing to Downloads needs a storage permission this app does not otherwise want, so
     * the file stays in app storage and is opened through the FileProvider.
     * ponytail: this copies after the transfer; receive straight into MediaStore if the
     * second write on a large file is ever noticeable.
     */
    private fun publish(file: ReceivedFile) {
        val mime = file.mime.ifBlank { "application/octet-stream" }
        val uri = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            toDownloads(file, mime) ?: return
        } else {
            FileProvider.getUriForFile(context, "${context.packageName}.fileprovider", file.file)
        }
        synchronized(saved) { saved[file.transferId] = uri to mime }
        notifyArrived(file, uri, mime)
    }

    private fun toDownloads(file: ReceivedFile, mime: String): Uri? {
        val resolver = context.contentResolver
        val values = ContentValues().apply {
            put(MediaStore.Downloads.DISPLAY_NAME, file.name)
            put(MediaStore.Downloads.MIME_TYPE, mime)
            put(MediaStore.Downloads.IS_PENDING, 1)
        }
        val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values) ?: return null
        val copied = runCatching {
            resolver.openOutputStream(uri)!!.use { out -> file.file.inputStream().use { it.copyTo(out) } }
        }.isSuccess
        if (!copied) {
            resolver.delete(uri, null, null)
            return null
        }
        values.clear()
        values.put(MediaStore.Downloads.IS_PENDING, 0)
        resolver.update(uri, values, null, null)
        file.file.delete()
        return uri
    }

    private fun notifyArrived(file: ReceivedFile, uri: Uri, mime: String) {
        val manager = NotificationManagerCompat.from(context)
        if (!manager.areNotificationsEnabled()) return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            context.getSystemService(NotificationManager::class.java).createNotificationChannel(
                NotificationChannel(CHANNEL_ID, "Received files", NotificationManager.IMPORTANCE_DEFAULT),
            )
        }
        val open = PendingIntent.getActivity(
            context,
            file.transferId.hashCode(),
            viewIntent(uri, mime),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_notification)
            // The name is the user's own content, shown on the user's own device — the
            // rule against content in logs and analytics is not a rule against this.
            .setContentTitle("File received")
            .setContentText(file.name)
            .setContentIntent(open)
            .setAutoCancel(true)
            .build()
        // areNotificationsEnabled() above is the permission check.
        @Suppress("MissingPermission")
        manager.notify(file.transferId.hashCode(), notification)
    }

    private fun viewIntent(uri: Uri, mime: String) =
        Intent(Intent.ACTION_VIEW)
            .setDataAndType(uri, mime)
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)

    private companion object {
        const val CHANNEL_ID = "files"
        const val MAX_ROWS = 20
    }
}
