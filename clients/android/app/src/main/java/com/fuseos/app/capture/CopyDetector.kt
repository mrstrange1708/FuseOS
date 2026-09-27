package com.fuseos.app.capture

import android.view.accessibility.AccessibilityEvent

/**
 * Recognises "the user just copied something" from accessibility events, so the island can
 * offer the copy to the Mac with Gboard — or any keyboard — still in charge.
 *
 * Android lets no background app read the clipboard, and no app add a button to another
 * app's keyboard. What an accessibility service *can* see is the moment of copying: a tap
 * on a control labelled Copy (the text-selection toolbar, a chat app's copy icon, a
 * browser's "Copy link address"), or the confirmation the system or the app shows after
 * (Android 13's clipboard overlay, a "Copied to clipboard" toast). On that, FuseOS brings
 * up its focused, invisible `CaptureActivity` for an instant — which may read the
 * clipboard — and the island asks whether to send it.
 *
 * Pure, so the rules are pinned by a test. Only labels are looked at, never content.
 */
object CopyDetector {
    private val COPY_LABELS = listOf("copy", "copy link", "copy text", "copy link address", "copy url", "copy message", "copy code")
    private val CONFIRMATIONS = listOf("copied", "copied to clipboard", "link copied", "text copied")

    fun looksLikeCopy(eventType: Int, packageName: String?, ownPackage: String, texts: List<String>): Boolean {
        if (packageName == ownPackage) return false
        val labels = texts.map { it.trim().lowercase() }.filter { it.isNotEmpty() }
        return when (eventType) {
            AccessibilityEvent.TYPE_VIEW_CLICKED -> labels.any { it in COPY_LABELS }
            AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED,
            AccessibilityEvent.TYPE_NOTIFICATION_STATE_CHANGED,
            -> labels.any { label -> CONFIRMATIONS.any { label == it || label.startsWith("$it ") || label.endsWith(" $it") } }
            else -> false
        }
    }
}
