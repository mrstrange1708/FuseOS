package com.fuseos.app.ui.dashboard

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import com.fuseos.app.clipboard.ClipboardSync
import com.fuseos.app.data.DeviceItem
import com.fuseos.app.data.DeviceRepository
import com.fuseos.app.data.PeerPresence
import com.fuseos.app.data.ServiceLocator
import com.fuseos.app.data.SessionStore
import com.fuseos.app.data.SignalClient
import com.fuseos.app.net.LanTransport
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

class DashboardViewModel(
    private val repo: DeviceRepository,
    private val signal: SignalClient,
    private val session: SessionStore,
    private val transport: LanTransport,
    private val clipboard: ClipboardSync,
) : ViewModel() {

    data class UiState(
        val selfDevice: DeviceItem? = null,
        val peers: List<DeviceItem> = emptyList(),
        val presence: Map<String, PeerPresence> = emptyMap(),
        /** Peers reachable over a direct LAN channel, not merely online. */
        val connected: Set<String> = emptySet(),
        val error: String? = null,
        val loading: Boolean = false,
    )

    private val _state = MutableStateFlow(UiState())
    val state = _state.asStateFlow()

    /** Set once registration and the LAN stack have come up; null means "not yet, retry". */
    private var startedDeviceId: String? = null
    private val startLock = Mutex()

    /** Emits when a pairing completes (so an open pairing sheet can close). */
    val paired: SharedFlow<Unit> = signal.paired

    init {
        viewModelScope.launch { bootstrap() }
        viewModelScope.launch { signal.presence.collect { p -> _state.update { it.copy(presence = p) } } }
        viewModelScope.launch { transport.connectedPeers.collect { c -> _state.update { it.copy(connected = c) } } }
        viewModelScope.launch { signal.paired.collect { refresh() } }
    }

    private suspend fun bootstrap() {
        try {
            ensureStarted()
            refresh()
        } catch (e: Exception) {
            _state.update { it.copy(error = e.message ?: "Unable to load your devices.") }
        }
    }

    /**
     * Registers this device and brings the LAN + signal stack up, returning our device id.
     *
     * Every action that needs the id goes through here rather than reading the stored one,
     * because this runs at launch — when the server may be unreachable. Doing it once and
     * giving up left the app reporting "this device isn't registered" for the rest of its
     * life, with a force-quit as the only way out. A failed attempt sets nothing, so the
     * next action retries the whole thing.
     */
    private suspend fun ensureStarted(): String = startLock.withLock {
        startedDeviceId?.let { return@withLock it }
        // Idempotent server-side, and it refreshes this device's battery and lastSeen.
        val deviceId = repo.registerThisDevice()
        // Bring the listener up before saying hello, so the very first hello can
        // already carry a lanAddress for peers to dial.
        transport.start(deviceId, signal.presence)
        clipboard.start(deviceId)
        session.currentToken()?.let { token -> signal.start(token, deviceId) }
        startedDeviceId = deviceId
        deviceId
    }

    suspend fun refresh() {
        _state.update { it.copy(loading = true) }
        try {
            val all = repo.listDevices(ensureStarted())
            _state.update {
                it.copy(
                    selfDevice = all.firstOrNull { d -> d.isSelf },
                    peers = all.filter { d -> !d.isSelf },
                    error = null,
                    loading = false,
                )
            }
        } catch (e: Exception) {
            _state.update { it.copy(error = e.message, loading = false) }
        }
    }

    suspend fun initiatePairing(): String = repo.initiatePairing(ensureStarted()).code

    suspend fun claimPairing(code: String) {
        repo.claimPairing(ensureStarted(), code)
        refresh()
    }

    fun selfBattery(): Int? = repo.batteryPercent()

    fun presenceFor(device: DeviceItem): PeerPresence =
        _state.value.presence[device.id]
            ?: PeerPresence(device.online, device.battery, publicKey = null, lanAddress = null)

    fun signOut() {
        signal.stop()
        clipboard.stop()
        transport.stop()
        viewModelScope.launch { session.clear() }
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
                )
            }
        }
    }
}
