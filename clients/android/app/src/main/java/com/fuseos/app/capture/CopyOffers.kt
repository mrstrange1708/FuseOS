package com.fuseos.app.capture

import android.content.Context

/** The user's switch for "offer every copy to the Mac" (on by default once the service is). */
object CopyOffers {
    private const val PREFS = "copy-offers"
    private const val KEY = "enabled"

    fun isOn(context: Context): Boolean =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getBoolean(KEY, true)

    fun set(context: Context, on: Boolean) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putBoolean(KEY, on).apply()
    }
}
