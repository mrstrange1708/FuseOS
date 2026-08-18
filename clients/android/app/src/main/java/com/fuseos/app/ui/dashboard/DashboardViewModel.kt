package com.fuseos.app.ui.dashboard

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
import kotlinx.coroutines.flow.SharedFlow
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
        val peers: List<DeviceItem> = emptyList(),
        val presence: Map<String, PeerPresence> = emptyMap(),
        /** Peers reachable over a direct LAN channel, not merely online. */
        val connected: Set<String> = emptySet(),
        val error: String? = null,
        val loading: Boolean = false,
        /** This device's advertised `ip:port`, or null until the LAN listener is bound. */
        val selfLanAddress: String? = null,
    ) {
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

    /** Emits when a pairing completes (so an open pairing sheet can close). */
    val paired: SharedFlow<Unit> = signal.paired

    /** Everything copied here or received from a peer, newest first. */
    val history: StateFlow<List<ClipEntry>> = clipboard.history

    /** Tapping a history entry puts it back on this device's clipboard. */
    fun copyToClipboard(entry: ClipEntry) = clipboard.copyToClipboard(entry)

    /** The nav bar's centre action: push this device's clipboard to the peer now. */
    fun sendCurrentClipboard(): Boolean = clipboard.sendCurrent()

    init {
        viewModelScope.launch { bootstrap() }
        // lanAddress is re-read on every presence/channel change: it is null until the
        // listener binds, and it changes outright when the device switches network.
        viewModelScope.launch {
            signal.presence.collect { p ->
                _state.update { it.copy(presence = p, selfLanAddress = transport.lanAddress()) }
            }
        }
        viewModelScope.launch {
            transport.connectedPeers.collect { c ->
                _state.update { it.copy(connected = c, selfLanAddress = transport.lanAddress()) }
            }
        }
        viewModelScope.launch { signal.paired.collect { refresh() } }
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
                    peers = all.filter { d -> !d.isSelf },
                    error = null,
                    loading = false,
                    selfLanAddress = transport.lanAddress(),
                )
            }
        } catch (e: Exception) {
            _state.update { it.copy(error = e.message, loading = false) }
        }
    }

    suspend fun initiatePairing(): String = repo.initiatePairing(connection.ensureStarted()).code

    suspend fun claimPairing(code: String) {
        repo.claimPairing(connection.ensureStarted(), code)
        refresh()
    }

    fun selfBattery(): Int? = repo.batteryPercent()

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
            session.clear()
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
