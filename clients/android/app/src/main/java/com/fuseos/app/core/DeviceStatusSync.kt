package com.fuseos.app.core

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.BatteryManager
import com.fuseos.app.net.LanTransport
import com.fuseos.proto.DeviceStatus
import com.fuseos.proto.Envelope
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/** The other device's battery and charging, as it last said. */
data class PeerStatus(val battery: Int?, val charging: Boolean)

/**
 * This phone's battery and charging to the Mac — when a channel comes up and whenever
 * the system's battery broadcast says they changed — and the Mac's back (`DeviceStatus`).
 */
class DeviceStatusSync(
    context: Context,
    private val transport: LanTransport,
    private val scope: CoroutineScope,
) {
    private val _peer = MutableStateFlow<PeerStatus?>(null)
    val peer: StateFlow<PeerStatus?> = _peer.asStateFlow()

    private var battery = -1
    private var charging = false
    private var lastSent: Pair<Int, Boolean>? = null

    init {
        // A sticky broadcast: registering hands back the current state straight away.
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                val level = intent.getIntExtra(BatteryManager.EXTRA_LEVEL, -1)
                val scale = intent.getIntExtra(BatteryManager.EXTRA_SCALE, 100)
                battery = if (level >= 0 && scale > 0) level * 100 / scale else -1
                val status = intent.getIntExtra(BatteryManager.EXTRA_STATUS, -1)
                charging = status == BatteryManager.BATTERY_STATUS_CHARGING || status == BatteryManager.BATTERY_STATUS_FULL
                send(force = false)
            }
        }
        context.applicationContext.registerReceiver(receiver, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        scope.launch {
            var previous = emptySet<String>()
            transport.connectedPeers.collect { now ->
                if ((now - previous).isNotEmpty()) send(force = true)
                if (now.isEmpty()) _peer.value = null
                previous = now
            }
        }
        scope.launch {
            transport.incoming.collect { envelope ->
                if (envelope.bodyCase == Envelope.BodyCase.DEVICE_STATUS) {
                    val s = envelope.deviceStatus
                    _peer.value = PeerStatus(s.battery.takeIf { it >= 0 }, s.charging)
                }
            }
        }
    }

    private fun send(force: Boolean) {
        val now = battery to charging
        if (!force && now == lastSent) return
        if (transport.connectedPeers.value.isEmpty()) return
        lastSent = now
        scope.launch(Dispatchers.IO) {
            transport.broadcast(
                transport.newEnvelope()
                    .setDeviceStatus(DeviceStatus.newBuilder().setBattery(battery).setCharging(charging))
                    .build(),
            )
        }
    }
}
