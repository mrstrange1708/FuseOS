package com.fuseos.app.ui.dashboard

import com.fuseos.app.ui.DemoMode

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import com.fuseos.app.clipboard.ClipEntry
import com.fuseos.app.clipboard.ClipboardSync
import com.fuseos.app.core.ConnectState
import com.fuseos.app.core.ConnectStateEvaluator
import com.fuseos.app.data.ConnectionManager
import com.fuseos.app.data.DeviceItem
import com.fuseos.app.data.DeviceRepository
import com.fuseos.app.data.PeerPresence
import com.fuseos.app.data.ServiceLocator
import com.fuseos.app.data.SessionStore
import com.fuseos.app.data.SignalClient
import com.fuseos.app.net.LanTransport
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

class DashboardViewModel(
    private val repo: DeviceRepository,
    private val signal: SignalClient,
    private val session: SessionStore,
    private val transport: LanTransport,
    private val clipboard: ClipboardSync,
    private val connection: ConnectionManager,
) : ViewModel() {

    data class UiState(
        val selfDevice: DeviceItem? = null,
        /** Every other device on the account, as the server lists them. */
        val allPeers: List<DeviceItem> = emptyList(),
        val presence: Map<String, PeerPresence> = emptyMap(),
        /** Peers reachable over a direct LAN channel, not merely online. */
        val connected: Set<String> = emptySet(),
        val error: String? = null,
        val loading: Boolean = false,
        /** This device's advertised `ip:port`, or null until the LAN listener is bound. */
        val selfLanAddress: String? = null,
    ) {
        /**
         * The devices worth showing. A reinstall mints a new key and so a new device
         * record, leaving the old one on the account forever offline under the same name.
         * Per name and platform the connected record wins, then the online one. Mirrors
         * `DashboardViewModel.peers` on macOS.
         *
         * ponytail: hides stale records rather than deleting them; a "Remove device"
         * endpoint is the real fix.
         */
        val peers: List<DeviceItem>
            get() {
                fun rank(d: DeviceItem) = when {
                    d.id in connected -> 0
                    presence[d.id]?.online == true -> 1
                    else -> 2
                }
                val best = allPeers.groupBy { "${it.platform}|${it.name}" }
                    .mapValues { (_, same) -> same.minBy(::rank).id }
                return allPeers.filter { best["${it.platform}|${it.name}"] == it.id }
            }

        /** What the connect screen renders. Derived rather than stored so it cannot drift
         *  out of step with the roster and presence it is computed from. */
        val connect: ConnectState
            get() = ConnectStateEvaluator.evaluate(
                selfLanAddress = selfLanAddress,
                peerIds = peers.map { it.id },
                presence = presence,
                connected = connected,
            )
    }

    private val _state = MutableStateFlow(UiState())
    val state = _state.asStateFlow()

    /** Everything copied here or received from a peer, newest first. */
    val history: StateFlow<List<ClipEntry>> = clipboard.history

    /** Tapping a history entry puts it back on this device's clipboard. */
    fun copyToClipboard(entry: ClipEntry) = clipboard.copyToClipboard(entry)

    /** The nav bar's centre action: push this device's clipboard to the peer now. */
    fun sendCurrentClipboard(): Boolean = clipboard.sendCurrent()

    init {
        if (DemoMode.isOn) {
            _state.value = DemoMode.state()
            clipboard.merge(DemoMode.history())
            ServiceLocator.transfers.showForDemo(DemoMode.transfers())
        } else {
            startLive()
        }
    }

    private fun startLive() {
        viewModelScope.launch { bootstrap() }
        // lanAddress is re-read on every presence/channel change: it is null until the
        // listener binds, and it changes outright when the device switches network.
        viewModelScope.launch {
            signal.presence.collect { p ->
                _state.update { it.copy(presence = p, selfLanAddress = transport.lanAddress()) }
                // A device that just signed in on this account arrives as presence before
                // it exists in the REST roster — which holds the names the UI draws. This
                // is how a second device shows up with no pairing step, so it has to
                // self-heal.
                val known = _state.value
                if (p.keys.any { id -> id != known.selfDevice?.id && known.allPeers.none { it.id == id } }) {
                    refresh()
                }
            }
        }
        viewModelScope.launch {
            transport.connectedPeers.collect { c ->
                _state.update { it.copy(connected = c, selfLanAddress = transport.lanAddress()) }
            }
        }
    }

    private suspend fun bootstrap() {
        try {
            connection.ensureStarted()
            refresh()
        } catch (e: Exception) {
            _state.update { it.copy(error = e.message ?: "Unable to load your devices.") }
        }
    }

    suspend fun refresh() {
        _state.update { it.copy(loading = true) }
        try {
            val all = repo.listDevices(connection.ensureStarted())
            _state.update {
                it.copy(
                    selfDevice = all.firstOrNull { d -> d.isSelf },
                    allPeers = all.filter { d -> !d.isSelf },
                    error = null,
                    loading = false,
                    selfLanAddress = transport.lanAddress(),
                )
            }
        } catch (e: Exception) {
            _state.update { it.copy(error = e.message, loading = false) }
        }
    }

    /**
     * Manual linking, the safety net behind automatic linking. Both calls resolve the
     * device id through [ConnectionManager.ensureStarted], so opening the screen after a
     * failed launch registers then rather than refusing.
     */
    suspend fun initiatePairing(): String = repo.initiatePairing(connection.ensureStarted()).code

    suspend fun claimPairing(code: String) {
        repo.claimPairing(connection.ensureStarted(), code)
        refresh()
    }

    fun selfBattery(): Int? = repo.batteryPercent()

    /**
     * Renames this device and pushes it straight to the server.
     *
     * Registration is an upsert keyed on the public key, so re-registering is the rename.
     * Doing it now rather than at the next launch means the Mac's list updates while the
     * user is still looking at the change.
     */
    fun renameThisDevice(name: String) {
        viewModelScope.launch {
            session.saveDeviceName(name)
            runCatching { repo.registerThisDevice() }
            refresh()
        }
    }

    fun presenceFor(device: DeviceItem): PeerPresence =
        _state.value.presence[device.id]
            ?: PeerPresence(device.online, device.battery, publicKey = null, lanAddress = null)

    /** Records that the connect screen has been passed, so launches go straight to home. */
    fun markConnectDone() {
        viewModelScope.launch { session.markConnectDone() }
    }

    fun signOut() {
        // MainActivity stops the foreground service when the token clears.
        viewModelScope.launch {
            connection.stop()
            // Ends the session on the server too, so the token stops working at once.
            ServiceLocator.authRepository.signOut()
        }
    }

    /** Removes a stale (offline) device from the account, then reloads the list. */
    fun removeDevice(id: String) {
        viewModelScope.launch {
            try {
                repo.removeDevice(id)
                refresh()
            } catch (e: Exception) {
                _state.update { it.copy(error = e.message) }
            }
        }
    }

    companion object {
        val Factory = viewModelFactory {
            initializer {
                DashboardViewModel(
                    ServiceLocator.deviceRepository,
                    ServiceLocator.signalClient,
                    ServiceLocator.session,
                    ServiceLocator.lanTransport,
                    ServiceLocator.clipboardSync,
                    ServiceLocator.connectionManager,
                )
            }
        }
    }
}
