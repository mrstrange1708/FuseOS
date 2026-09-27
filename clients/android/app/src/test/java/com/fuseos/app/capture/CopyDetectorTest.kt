package com.fuseos.app.capture

import android.view.accessibility.AccessibilityEvent
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class CopyDetectorTest {
    private val own = "com.fuseos.app"
    private fun copy(type: Int, vararg texts: String, pkg: String = "com.whatsapp") =
        CopyDetector.looksLikeCopy(type, pkg, own, texts.toList())

    @Test fun aTapOnCopyInTheSelectionToolbar() = assertTrue(copy(AccessibilityEvent.TYPE_VIEW_CLICKED, "Copy"))

    @Test fun aBrowsersCopyLinkAddress() = assertTrue(copy(AccessibilityEvent.TYPE_VIEW_CLICKED, "Copy link address"))

    @Test fun theSystemsCopiedConfirmation() =
        assertTrue(copy(AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED, "Copied", pkg = "com.android.systemui"))

    @Test fun anAppsCopiedToast() =
        assertTrue(copy(AccessibilityEvent.TYPE_NOTIFICATION_STATE_CHANGED, "Link copied to clipboard"))

    // A button that merely mentions copying, or any other tap, is not a copy.
    @Test fun notEveryTap() {
        assertFalse(copy(AccessibilityEvent.TYPE_VIEW_CLICKED, "Send"))
        assertFalse(copy(AccessibilityEvent.TYPE_VIEW_CLICKED, "Copyright notice"))
        assertFalse(copy(AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED, "Photocopied receipts"))
    }

    // FuseOS's own island and toasts must never trigger another offer.
    @Test fun neverItsOwnEvents() = assertFalse(copy(AccessibilityEvent.TYPE_VIEW_CLICKED, "Copy", pkg = own))
}
