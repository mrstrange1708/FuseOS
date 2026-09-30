package com.fuseos.app.actions

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class LastLinkTest {
    @Test
    fun theNewestLinkWinsEvenWithTextCopiedAfterIt() {
        val newestFirst = listOf("meeting at 5", "see https://fuseos.theshaik.dev/help.", "https://old.example")
        assertEquals("https://fuseos.theshaik.dev/help", PhoneActions.lastLink(newestFirst))
    }

    @Test
    fun noLinkCopiedIsNull() {
        assertNull(PhoneActions.lastLink(listOf("just text", "more text")))
    }
}
