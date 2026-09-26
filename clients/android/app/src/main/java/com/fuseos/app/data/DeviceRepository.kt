package com.fuseos.app.data

import com.fuseos.app.core.DeviceInfo

/** Coordinates device registration, listing, and manual linking. The UI talks to this. */
class DeviceRepository(
    private val api: ControlPlaneApi,
    private val session: SessionStore,
    private val deviceInfo: DeviceInfo,
) {
    val deviceIdFlow = session.deviceIdFlow

    /**
     * Registers (idempotently) this device and stores its stable server id.
     *
     * A `public_key_taken` means this phone's keypair is still registered to an account
     * someone signed in with earlier. The server must not hand the key over (that's the
     * guard in `POST /devices`), so the fix is ours: mint a new identity and retry once.
     */
    suspend fun registerThisDevice(): String = try {
        register()
    } catch (e: AuthException) {
        if (e.code != "public_key_taken") throw e
        session.resetDeviceKey()
        register()
    }

    private suspend fun register(): String {
        val response = api.registerDevice(
            DeviceRegisterRequest(
                name = session.currentDeviceName() ?: deviceInfo.deviceName(),
                platform = "android",
                publicKey = session.deviceKey(),
                battery = deviceInfo.batteryPercent(),
            ),
        )
        session.saveDeviceId(response.id)
        return response.id
    }

    suspend fun listDevices(selfId: String?): List<DeviceItem> =
        api.listDevices(selfId).devices

    suspend fun removeDevice(id: String) = api.removeDevice(id)

    suspend fun initiatePairing(deviceId: String): PairInitiateResponse =
        api.initiatePairing(PairInitiateRequest(deviceId))

    suspend fun claimPairing(deviceId: String, code: String): PairClaimResponse =
        api.claimPairing(PairClaimRequest(deviceId, code))

    fun batteryPercent(): Int? = deviceInfo.batteryPercent()
}
