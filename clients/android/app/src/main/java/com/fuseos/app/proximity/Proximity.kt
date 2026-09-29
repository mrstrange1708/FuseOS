package com.fuseos.app.proximity

import android.Manifest
import android.bluetooth.BluetoothManager
import android.bluetooth.le.AdvertiseCallback
import android.bluetooth.le.AdvertiseData
import android.bluetooth.le.AdvertiseSettings
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.os.SystemClock
import com.fuseos.app.net.LanTransport
import com.fuseos.proto.Envelope
import com.fuseos.proto.Unlocked
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

/**
 * The phone's side of nearby lock and unlock.
 *
 * - A private Bluetooth beacon, so the Mac can tell how close the phone is: low power,
 *   not connectable, manufacturer data = the current [BeaconToken] under the key the Mac
 *   hands over on every channel. Nobody without the key can recognise it, and it changes
 *   every ten minutes.
 * - "Unlocked" to the Mac when the user unlocks this phone (the Mac decides whether to act).
 * - The Mac's "unlocked" wakes this phone's screen — an app cannot get past the lock itself.
 */
class Proximity(
    context: Context,
    private val transport: LanTransport,
    private val scope: CoroutineScope,
) {
    private val app = context.applicationContext
    private val main = Handler(Looper.getMainLooper())
    private val prefs = app.getSharedPreferences("proximity", Context.MODE_PRIVATE)
    /**
     * The Mac's latest key, kept on disk: a phone whose process was killed (ColorOS does,
     * freely) or whose link is down must keep beaconing, or the Mac can't tell it is close.
     */
    private var key: ByteArray? = prefs.getString(KEY_PREF, null)?.let { android.util.Base64.decode(it, android.util.Base64.NO_WRAP) }
    private var advertising = false
    private val rotate = Runnable { restartBeacon() }

    /** What the beacon is doing, in words for Profile — "On" used to mean only "permitted". */
    enum class Beacon { Broadcasting, NoPermission, BluetoothOff, WaitingForMac, Refused }
    private val _state = kotlinx.coroutines.flow.MutableStateFlow(Beacon.WaitingForMac)
    val state: kotlinx.coroutines.flow.StateFlow<Beacon> = _state
    /** Android's reason when it refused to broadcast (its AdvertiseCallback error code). */
    @Volatile var refusal: Int = 0
        private set

    private val callback = object : AdvertiseCallback() {
        override fun onStartSuccess(settingsInEffect: AdvertiseSettings?) {
            _state.value = Beacon.Broadcasting
        }

        override fun onStartFailure(errorCode: Int) {
            advertising = false
            refusal = errorCode
            _state.value = Beacon.Refused
            android.util.Log.e("FuseProximity", "beacon refused by Android: $errorCode")
        }
    }

    /** When the phone was unlocked with no link up — the link usually comes back seconds later. */
    private var unlockedAt = 0L

    init {
        scope.launch {
            transport.incoming.collect { envelope ->
                when (envelope.bodyCase) {
                    Envelope.BodyCase.BEACON_KEY -> {
                        val fresh = envelope.beaconKey.key.toByteArray()
                        key = fresh
                        prefs.edit().putString(KEY_PREF, android.util.Base64.encodeToString(fresh, android.util.Base64.NO_WRAP)).apply()
                        main.post { restartBeacon() }
                    }
                    Envelope.BodyCase.UNLOCKED -> main.post { wakeScreen() }
                    else -> Unit
                }
            }
        }
        // A locked phone often loses its LAN link; deliver the unlock once it is back.
        scope.launch {
            transport.connectedPeers.collect { peers ->
                if (peers.isNotEmpty() && SystemClock.elapsedRealtime() - unlockedAt < UNLOCK_GRACE_MS) {
                    unlockedAt = 0
                    sendUnlocked()
                }
            }
        }
        // Bluetooth switched back on: the advertiser went with it, so start again.
        app.registerReceiver(
            object : BroadcastReceiver() {
                override fun onReceive(context: Context, intent: Intent) {
                    main.post { restartBeacon() }
                }
            },
            IntentFilter(android.bluetooth.BluetoothAdapter.ACTION_STATE_CHANGED),
        )
        // A key from an earlier run: beacon straight away, before any link.
        main.post { restartBeacon() }
        // USER_PRESENT is only delivered to receivers registered at run time.
        app.registerReceiver(
            object : BroadcastReceiver() {
                override fun onReceive(context: Context, intent: Intent) = sendUnlocked()
            },
            IntentFilter(Intent.ACTION_USER_PRESENT),
        )
    }

    fun hasPermission(): Boolean = Build.VERSION.SDK_INT < Build.VERSION_CODES.S ||
        app.checkSelfPermission(Manifest.permission.BLUETOOTH_ADVERTISE) == PackageManager.PERMISSION_GRANTED

    /** After the permission is granted: start (or refresh) the beacon now. */
    fun permissionChanged() = main.post { restartBeacon() }

    @Suppress("MissingPermission")
    private fun restartBeacon() {
        main.removeCallbacks(rotate)
        val key = key ?: return run { _state.value = Beacon.WaitingForMac }
        if (!hasPermission()) return run { _state.value = Beacon.NoPermission }
        val adapter = app.getSystemService(BluetoothManager::class.java)?.adapter
        if (adapter?.isEnabled != true) {
            advertising = false
            _state.value = Beacon.BluetoothOff
            return
        }
        val advertiser = adapter.bluetoothLeAdvertiser ?: return run { _state.value = Beacon.Refused }
        runCatching {
            if (advertising) advertiser.stopAdvertising(callback)
            val now = System.currentTimeMillis()
            val settings = AdvertiseSettings.Builder()
                .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_POWER)
                .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_MEDIUM)
                .setConnectable(false)
                .build()
            val data = AdvertiseData.Builder()
                .setIncludeDeviceName(false)
                .addManufacturerData(COMPANY_ID, BeaconToken.token(key, BeaconToken.window(now)))
                .build()
            advertiser.startAdvertising(settings, data, callback)
            advertising = true
            // Re-derive at the next ten-minute boundary.
            main.postDelayed(rotate, BeaconToken.WINDOW_MS - now % BeaconToken.WINDOW_MS + 1_000)
        }
    }

    private fun sendUnlocked() {
        if (transport.connectedPeers.value.isEmpty()) {
            unlockedAt = SystemClock.elapsedRealtime()
            return
        }
        scope.launch(Dispatchers.IO) {
            transport.broadcast(transport.newEnvelope().setUnlocked(Unlocked.getDefaultInstance()).build())
        }
    }

    @Suppress("DEPRECATION")
    private fun wakeScreen() {
        val power = app.getSystemService(PowerManager::class.java)
        if (power.isInteractive) return
        power.newWakeLock(
            PowerManager.SCREEN_BRIGHT_WAKE_LOCK or PowerManager.ACQUIRE_CAUSES_WAKEUP,
            "fuseos:mac-unlocked",
        ).acquire(3_000)
    }

    private companion object {
        /** 0xFFFF: the Bluetooth SIG's id for testing/unassigned — FuseOS has no company id. */
        const val COMPANY_ID = 0xFFFF
        const val UNLOCK_GRACE_MS = 10_000L
        const val KEY_PREF = "beacon_key"
    }
}
