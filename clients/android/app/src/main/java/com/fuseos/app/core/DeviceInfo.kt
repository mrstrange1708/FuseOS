package com.fuseos.app.core

import android.content.Context
import android.os.BatteryManager
import android.os.Build

/** Reads this phone's name and battery. Battery is operational presence metadata,
 *  never a user payload. */
class DeviceInfo(private val context: Context) {

    fun deviceName(): String {
        val manufacturer = Build.MANUFACTURER?.replaceFirstChar { it.uppercase() }.orEmpty()
        val model = Build.MODEL.orEmpty()
        val name = "$manufacturer $model".trim()
        return name.ifEmpty { "Android" }
    }

    fun batteryPercent(): Int? {
        val manager = context.getSystemService(Context.BATTERY_SERVICE) as? BatteryManager ?: return null
        val level = manager.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY)
        return level.takeIf { it in 0..100 }
    }
}
