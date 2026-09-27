package com.fuseos.app.actions

import androidx.compose.ui.geometry.Offset
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/** Three-finger swipes map to the Mac's own ⌃-arrow shortcuts, as on a Mac trackpad. */
class TrackpadSwipeTest {
    private fun code(dx: Float, dy: Float) = swipe(Offset(dx, dy))?.keyCode

    @Test fun leftAndRightSwitchDesktops() {
        assertEquals(124, code(-300f, 20f))
        assertEquals(123, code(300f, -20f))
    }

    @Test fun upIsMissionControlAndDownIsAppExpose() {
        assertEquals(126, code(10f, -300f))
        assertEquals(125, code(-10f, 300f))
    }

    @Test fun holdsControl() = assertEquals(8, swipe(Offset(-300f, 0f))?.modifiers)

    @Test fun aSmallMovementIsNothing() = assertNull(swipe(Offset(40f, 30f)))
}
