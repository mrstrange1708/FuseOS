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
