package com.fuseos.app.data

import kotlinx.serialization.Serializable

// Wire models for the device registry (see docs/api.md).

@Serializable
data class DeviceRegisterRequest(
    val name: String,
    val platform: String,
    val publicKey: String,
    val battery: Int? = null,
)

@Serializable
data class DeviceRegisterResponse(val id: String, val name: String, val platform: String)

@Serializable
data class DeviceItem(
    val id: String,
    val name: String,
    val platform: String,
    val online: Boolean,
    val battery: Int? = null,
    val trusted: Boolean = false,
    val isSelf: Boolean = false,
)

@Serializable
data class DeviceListResponse(val devices: List<DeviceItem>)

// Manual linking — the safety net behind automatic linking. Claiming a code does not grant
// trust (same account already does); it forces the peer-card exchange that `/signal`
// normally delivers on its own. See docs/api.md.

@Serializable
data class PairInitiateRequest(val deviceId: String)

@Serializable
data class PairInitiateResponse(val code: String, val expiresAt: String)

@Serializable
data class PairClaimRequest(val deviceId: String, val code: String)

@Serializable
data class TrustedPeer(val deviceId: String, val name: String, val platform: String)

@Serializable
data class PairClaimResponse(val trustedWith: TrustedPeer)
