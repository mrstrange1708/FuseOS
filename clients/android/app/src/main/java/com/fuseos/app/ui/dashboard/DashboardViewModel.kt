package com.fuseos.app.ui.dashboard

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import com.fuseos.app.data.DeviceItem
import com.fuseos.app.data.DeviceRepository
import com.fuseos.app.data.PeerPresence
import com.fuseos.app.data.ServiceLocator
import com.fuseos.app.data.SessionStore
import com.fuseos.app.data.SignalClient
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

class DashboardViewModel(
    private val repo: DeviceRepository,
    private val signal: SignalClient,
    private val session: SessionStore,
) : ViewModel() {

    data class UiState(
        val selfDevice: DeviceItem? = null,
        val peers: List<DeviceItem> = emptyList(),
        val presence: Map<String, PeerPresence> = emptyMap(),
        val error: String? = null,
        val loading: Boolean = false,
    )

    private val _state = MutableStateFlow(UiState())
    val state = _state.asStateFlow()

    /** Emits when a pairing completes (so an open pairing sheet can close). */
    val paired: SharedFlow<Unit> = signal.paired

    init {
        viewModelScope.launch { bootstrap() }
        viewModelScope.launch { signal.presence.collect { p -> _state.update { it.copy(presence = p) } } }
        viewModelScope.launch { signal.paired.collect { refresh() } }
    }

    private suspend fun bootstrap() {
        try {
            val deviceId = repo.registerThisDevice()
            session.currentToken()?.let { token -> signal.start(token, deviceId) }
            refresh()
        } catch (e: Exception) {
            _state.update { it.copy(error = e.message ?: "Unable to load your devices.") }
        }
    }

    suspend fun refresh() {
        val selfId = session.deviceIdFlow.first() ?: return
        _state.update { it.copy(loading = true) }
        try {
            val all = repo.listDevices(selfId)
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

    suspend fun initiatePairing(): String {
        val selfId = session.deviceIdFlow.first()
            ?: throw IllegalStateException("This device isn't registered yet.")
        return repo.initiatePairing(selfId).code
    }

    suspend fun claimPairing(code: String) {
        val selfId = session.deviceIdFlow.first()
            ?: throw IllegalStateException("This device isn't registered yet.")
        repo.claimPairing(selfId, code)
        refresh()
    }

    fun selfBattery(): Int? = repo.batteryPercent()

    fun presenceFor(device: DeviceItem): PeerPresence =
        _state.value.presence[device.id] ?: PeerPresence(device.online, device.battery)

    fun signOut() {
        signal.stop()
        viewModelScope.launch { session.clear() }
    }

    companion object {
        val Factory = viewModelFactory {
            initializer {
                DashboardViewModel(
                    ServiceLocator.deviceRepository,
                    ServiceLocator.signalClient,
                    ServiceLocator.session,
                )
            }
        }
    }
}
