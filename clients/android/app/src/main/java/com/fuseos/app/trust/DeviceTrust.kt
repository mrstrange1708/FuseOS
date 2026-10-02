package com.fuseos.app.trust

import android.content.SharedPreferences

/**
 * Which of the account's devices this phone links with. Mirrors the Mac's `DeviceTrust`.
 *
 * Being on the same account is not enough: whoever learns the password could sign in on their
 * own device and start receiving this phone's copies, notifications and codes. So every device
 * keeps its own list, and a newcomer links only after the user allows it here — a decision the
 * server cannot make for them, even a compromised one.
 *
 * Each approved device is pinned to its key on first sight; the same device back with another
 * key is asked about again. The devices already on the account when this phone first signs in
 * (or first runs this version) are the user's own, and are approved then.
 */
class DeviceTrust(initial: Snapshot, private val persist: (Snapshot) -> Unit) {
    enum class Verdict { Trusted, Pending, Blocked }

    /** deviceId → pinned key ("" for a device approved before its key was seen). */
    data class Snapshot(
        val approved: Map<String, String> = emptyMap(),
        val blocked: Map<String, String> = emptyMap(),
        val bootstrapped: Boolean = false,
    )

    private var state = initial

    val bootstrapped: Boolean
        @Synchronized get() = state.bootstrapped

    /** The first device list after sign-in (or after this update): those are the user's own. */
    @Synchronized
    fun bootstrapIfNeeded(deviceIds: Collection<String>) {
        if (state.bootstrapped) return
        update(state.copy(approved = state.approved + deviceIds.filter { it !in state.approved }.associateWith { "" }, bootstrapped = true))
    }

    /** Whether to link with [deviceId] presenting [key]; pins an approved device's first key. */
    @Synchronized
    fun check(deviceId: String, key: String): Verdict {
        if (state.blocked[deviceId] == key) return Verdict.Blocked
        val pinned = state.approved[deviceId] ?: return Verdict.Pending
        if (pinned.isEmpty()) {
            update(state.copy(approved = state.approved + (deviceId to key)))
            return Verdict.Trusted
        }
        return if (pinned == key) Verdict.Trusted else Verdict.Pending
    }

    @Synchronized
    fun approve(deviceId: String, key: String) =
        update(state.copy(approved = state.approved + (deviceId to key), blocked = state.blocked - deviceId))

    @Synchronized
    fun block(deviceId: String, key: String) =
        update(state.copy(blocked = state.blocked + (deviceId to key), approved = state.approved - deviceId))

    /** Signed out: the next account's devices are a different set. */
    @Synchronized
    fun reset() = update(Snapshot())

    private fun update(next: Snapshot) {
        state = next
        persist(next)
    }

    companion object {
        private const val APPROVED = "approved"
        private const val BLOCKED = "blocked"
        private const val BOOTSTRAPPED = "bootstrapped"

        /** Backed by app-private prefs, which data_extraction_rules keep out of backups. */
        fun fromPrefs(prefs: SharedPreferences): DeviceTrust {
            fun read(key: String) = prefs.getStringSet(key, emptySet()).orEmpty()
                .associate { it.substringBefore('|') to it.substringAfter('|', "") }
            fun write(map: Map<String, String>) = map.map { (id, k) -> "$id|$k" }.toSet()
            val initial = Snapshot(read(APPROVED), read(BLOCKED), prefs.getBoolean(BOOTSTRAPPED, false))
            return DeviceTrust(initial) { s ->
                prefs.edit()
                    .putStringSet(APPROVED, write(s.approved))
                    .putStringSet(BLOCKED, write(s.blocked))
                    .putBoolean(BOOTSTRAPPED, s.bootstrapped)
                    .apply()
            }
        }
    }
}
