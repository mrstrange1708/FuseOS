package com.fuseos.app.notify

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Which notifications cross to the Mac — see [NotificationSync.shouldForward]. */
class NotificationForwardTest {
    private fun forward(
        enabled: Boolean = true,
        linked: Boolean = true,
        fromSelf: Boolean = false,
        ongoing: Boolean = false,
        groupSummary: Boolean = false,
        hasContent: Boolean = true,
    ) = NotificationSync.shouldForward(enabled, linked, fromSelf, ongoing, groupSummary, hasContent)

    @Test fun forwardsAnOrdinaryNotificationWhileLinked() = assertTrue(forward())

    @Test fun holdsEverythingWhenTheUserTurnedItOff() = assertFalse(forward(enabled = false))

    // Dropped, not queued: an hour-old notification is not worth delivering late.
    @Test fun dropsWhileNoMacIsLinked() = assertFalse(forward(linked = false))

    // FuseOS's own ongoing service notification would otherwise mirror forever.
    @Test fun neverForwardsItsOwn() = assertFalse(forward(fromSelf = true))

    @Test fun skipsOngoingStatus() = assertFalse(forward(ongoing = true))

    @Test fun skipsGroupSummaries() = assertFalse(forward(groupSummary = true))

    @Test fun skipsOnesWithNothingToRead() = assertFalse(forward(hasContent = false))
}
