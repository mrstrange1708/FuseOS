package com.fuseos.app.trust

import com.fuseos.app.trust.DeviceTrust.Verdict
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test

class DeviceTrustTest {
    private var saved = DeviceTrust.Snapshot()
    private fun trust() = DeviceTrust(saved) { saved = it }

    @Test
    fun theAccountsDevicesAtSignInAreTrustedAndPinned() {
        val trust = trust()
        assertEquals(Verdict.Pending, trust.check("mac", "k1")) // before any list
        trust.bootstrapIfNeeded(listOf("mac"))
        assertEquals(Verdict.Trusted, trust.check("mac", "k1"))
        assertEquals(Verdict.Pending, trust.check("mac", "k2")) // pinned: another key is asked about
    }

    @Test
    fun aNewcomerWaitsForApprovalAndBlockingSticks() {
        val trust = trust()
        trust.bootstrapIfNeeded(listOf("mac"))
        trust.bootstrapIfNeeded(listOf("mac", "stranger")) // only the first list counts
        assertEquals(Verdict.Pending, trust.check("stranger", "s"))
        trust.block("stranger", "s")
        assertEquals(Verdict.Blocked, trust.check("stranger", "s"))
        trust.approve("stranger", "s")
        assertEquals(Verdict.Trusted, trust.check("stranger", "s"))
    }

    @Test
    fun itSurvivesARelaunchAndResetsOnSignOut() {
        trust().apply { bootstrapIfNeeded(emptyList()); approve("phone", "p") }
        val relaunched = trust()
        assertEquals(Verdict.Trusted, relaunched.check("phone", "p"))
        relaunched.reset()
        assertEquals(Verdict.Pending, trust().check("phone", "p"))
        assertFalse(trust().bootstrapped)
    }
}
