package com.fuseos.app.notify

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.os.Build
import android.service.notification.StatusBarNotification
import android.telecom.TelecomManager
import com.fuseos.proto.CallAction

/**
 * Answers, declines and ends the phone's calls for the Mac — two ways, because neither is
 * reliable alone. Through the telecom service when ANSWER_PHONE_CALLS is granted; but an
 * OEM dialer (ColorOS's, on the device this was tested on) can ignore that without an error,
 * so [NotificationSync] checks the call actually changed and otherwise presses the call
 * notification's own button whose label says what it does. Answering from the Mac turns the
 * speaker on, because the call's audio cannot leave the phone.
 */
class CallControl(context: Context) {
    private val app = context.applicationContext
    private val telecom = app.getSystemService(TelecomManager::class.java)

    fun hasPermission(): Boolean =
        app.checkSelfPermission(Manifest.permission.ANSWER_PHONE_CALLS) == PackageManager.PERMISSION_GRANTED

    /** The telecom route. True only means Android took the request, not that it acted. */
    fun viaTelecom(action: CallAction.Action): Boolean {
        if (!hasPermission()) return false
        return when (action) {
            CallAction.Action.ANSWER -> runCatching {
                @Suppress("DEPRECATION") telecom.acceptRingingCall()
            }.isSuccess.also { if (it) speakerOn() }
            CallAction.Action.DECLINE, CallAction.Action.END ->
                Build.VERSION.SDK_INT >= Build.VERSION_CODES.P &&
                    runCatching { @Suppress("DEPRECATION") telecom.endCall() }.getOrDefault(false)
            else -> false
        }
    }

    /** The notification route: the dialer's own Answer / Decline / End button. */
    fun viaNotification(action: CallAction.Action, call: StatusBarNotification?): Boolean {
        val labels = when (action) {
            CallAction.Action.ANSWER -> listOf("answer", "accept", "pick up")
            CallAction.Action.DECLINE, CallAction.Action.END -> listOf("decline", "reject", "hang up", "end")
            else -> return false
        }
        val button = call?.notification?.actions?.firstOrNull { a ->
            val title = a.title?.toString()?.lowercase().orEmpty()
            labels.any { it in title }
        } ?: return false
        val sent = runCatching { button.actionIntent.send() }.isSuccess
        if (sent && action == CallAction.Action.ANSWER) speakerOn()
        return sent
    }

    private fun speakerOn() {
        val audio = app.getSystemService(AudioManager::class.java)
        runCatching {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                audio.availableCommunicationDevices
                    .firstOrNull { it.type == AudioDeviceInfo.TYPE_BUILTIN_SPEAKER }
                    ?.let { audio.setCommunicationDevice(it) }
            } else {
                @Suppress("DEPRECATION")
                audio.isSpeakerphoneOn = true
            }
        }
    }
}
