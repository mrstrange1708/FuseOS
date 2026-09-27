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
        liveActivity: Boolean = false,
    ) = NotificationSync.shouldForward(enabled, linked, fromSelf, ongoing, groupSummary, hasContent, liveActivity)

    @Test fun forwardsAnOrdinaryNotificationWhileLinked() = assertTrue(forward())

    @Test fun holdsEverythingWhenTheUserTurnedItOff() = assertFalse(forward(enabled = false))

    // Dropped, not queued: an hour-old notification is not worth delivering late.
    @Test fun dropsWhileNoMacIsLinked() = assertFalse(forward(linked = false))

    // FuseOS's own ongoing service notification would otherwise mirror forever.
    @Test fun neverForwardsItsOwn() = assertFalse(forward(fromSelf = true))

    @Test fun skipsOngoingStatus() = assertFalse(forward(ongoing = true))

    // A timer, a route or a download is ongoing too — but it is an activity, not a placard.
    @Test fun forwardsAnOngoingLiveActivity() = assertTrue(forward(ongoing = true, liveActivity = true))

    @Test fun progressOrAClockMakesALiveActivity() {
        assertTrue(NotificationSync.isLiveActivity(null, hasProgress = true, showsClock = false, isMedia = false))
        assertTrue(NotificationSync.isLiveActivity(null, hasProgress = false, showsClock = true, isMedia = false))
        assertTrue(NotificationSync.isLiveActivity("navigation", hasProgress = false, showsClock = false, isMedia = false))
    }

    // A service's "running in the background" placard, and media (Now Playing's job), are not.
    @Test fun aPlacardOrMediaIsNot() {
        assertFalse(NotificationSync.isLiveActivity("service", hasProgress = false, showsClock = false, isMedia = false))
        assertFalse(NotificationSync.isLiveActivity(null, hasProgress = true, showsClock = false, isMedia = true))
    }

    @Test fun skipsGroupSummaries() = assertFalse(forward(groupSummary = true))

    @Test fun skipsOnesWithNothingToRead() = assertFalse(forward(hasContent = false))
}
