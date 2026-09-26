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
 * Answers, declines and ends the phone's calls for the Mac.
 *
 * With ANSWER_PHONE_CALLS granted, through the telecom service — reliable across dialers.
 * Without it, by pressing the call notification's own button whose label says what it
 * does, which works for the stock dialer. Answering from the Mac turns the speaker on,
 * because the call's audio cannot leave the phone.
 */
class CallControl(context: Context) {
    private val app = context.applicationContext
    private val telecom = app.getSystemService(TelecomManager::class.java)

    fun hasPermission(): Boolean =
        app.checkSelfPermission(Manifest.permission.ANSWER_PHONE_CALLS) == PackageManager.PERMISSION_GRANTED

    fun perform(action: CallAction.Action, call: StatusBarNotification?) {
        when (action) {
            CallAction.Action.ANSWER -> {
                val answered = hasPermission() && runCatching {
                    @Suppress("DEPRECATION") telecom.acceptRingingCall()
                }.isSuccess
                if (!answered) press(call, "answer", "accept", "pick up")
                speakerOn()
            }
            CallAction.Action.DECLINE, CallAction.Action.END -> {
                val ended = hasPermission() && Build.VERSION.SDK_INT >= Build.VERSION_CODES.P &&
                    runCatching { @Suppress("DEPRECATION") telecom.endCall() }.getOrDefault(false)
                if (!ended) press(call, "decline", "reject", "hang up", "end")
            }
            else -> Unit
        }
    }

    private fun press(call: StatusBarNotification?, vararg labels: String) {
        val action = call?.notification?.actions?.firstOrNull { action ->
            val title = action.title?.toString()?.lowercase().orEmpty()
            labels.any { it in title }
        } ?: return
        runCatching { action.actionIntent.send() }
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
