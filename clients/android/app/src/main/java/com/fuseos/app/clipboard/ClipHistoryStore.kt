package com.fuseos.app.clipboard

import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

/**
 * Keeps clipboard history across app restarts.
 *
 * On disk, not in the control plane: clipboard content never reaches the server or its
 * database (see CLAUDE.md). This is local storage on the device that already has the
 * content on its clipboard, which is a different thing from shipping it anywhere.
 *
 * Text lives in one JSON index; image bytes go to files beside it, referenced by name.
 * Base64-ing a 2 MB screenshot into JSON would triple it and force the whole history to
 * be parsed to read one entry.
 */
class ClipHistoryStore(private val directory: File) {

    private val index = File(directory, "history.json")
    private val blobs = File(directory, "blobs")

    /** Newest first, oldest entries dropped if they no longer fit the caps. */
    fun load(): List<ClipEntry> = runCatching {
        if (!index.exists()) return emptyList()
        val array = JSONArray(index.readText())
        (0 until array.length()).mapNotNull { i ->
            val o = array.getJSONObject(i)
            val blob = o.optString("blob").takeIf { it.isNotEmpty() }
            val bytes = blob?.let { name ->
                File(blobs, name).takeIf { it.exists() }?.readBytes()
                // An entry whose blob went missing is dropped rather than shown as an
                // empty card the user cannot do anything with.
                    ?: return@mapNotNull null
            }
            ClipEntry(
                id = o.getLong("id"),
                text = o.optString("text").takeIf { it.isNotEmpty() },
                imageBytes = bytes,
                mime = o.optString("mime").takeIf { it.isNotEmpty() },
                fromSelf = o.getBoolean("fromSelf"),
                atUnixMs = o.getLong("at"),
            )
        }
    }.onFailure { Log.w(TAG, "history unreadable, starting empty: ${it.message}") }
        .getOrDefault(emptyList())

    /** Writes the whole list. Small and bounded, so a full rewrite beats incremental edits. */
    fun save(entries: List<ClipEntry>) {
        runCatching {
            directory.mkdirs()
            blobs.mkdirs()
            val array = JSONArray()
            val keep = mutableSetOf<String>()
            for (entry in entries) {
                val o = JSONObject()
                    .put("id", entry.id)
                    .put("fromSelf", entry.fromSelf)
                    .put("at", entry.atUnixMs)
                entry.text?.let { o.put("text", it) }
                entry.mime?.let { o.put("mime", it) }
                entry.imageBytes?.let { bytes ->
                    val name = "${entry.id}.bin"
                    File(blobs, name).writeBytes(bytes)
                    keep += name
                    o.put("blob", name)
                }
                array.put(o)
            }
            index.writeText(array.toString())
            // Evicted entries leave their blobs behind otherwise, and images are the only
            // thing here big enough to matter.
            blobs.listFiles()?.forEach { if (it.name !in keep) it.delete() }
        }.onFailure { Log.w(TAG, "could not save history: ${it.message}") }
    }

    /** Sign-out must not leave the last user's copied content on disk. */
    fun clear() {
        runCatching {
            index.delete()
            blobs.deleteRecursively()
        }
    }

    private companion object {
        const val TAG = "FuseHistory"
    }
}

/** How far back the history list shows. Mirrors `HistoryWindow` on macOS. */
enum class HistoryWindow(val label: String, val millis: Long?) {
    Day("24 hours", 24L * 60 * 60 * 1000),
    Week("7 days", 7L * 24 * 60 * 60 * 1000),
    Month("30 days", 30L * 24 * 60 * 60 * 1000),

    /** Everything still held. The caps in `ClipboardSync` bound this, not time. */
    All("All", null),
    ;

    fun filter(entries: List<ClipEntry>, now: Long = System.currentTimeMillis()): List<ClipEntry> {
        val cutoff = millis?.let { now - it } ?: return entries
        return entries.filter { it.atUnixMs >= cutoff }
    }
}
