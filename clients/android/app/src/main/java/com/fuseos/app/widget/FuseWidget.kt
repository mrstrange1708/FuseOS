package com.fuseos.app.widget

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import com.fuseos.app.MainActivity
import com.fuseos.app.R
import com.fuseos.app.actions.TrackpadActivity
import com.fuseos.app.capture.CaptureActivity

/** What the widget shows. */
data class WidgetState(
    val linked: Boolean,
    val macName: String?,
    val macBattery: Int?,
    val macCharging: Boolean,
    val lastClip: String?,
)

/**
 * The FuseOS home-screen widget: whether the Mac is linked, its battery, the last clip,
 * and Send clipboard / Trackpad / Open. Pushed by [update] whenever one of those changes.
 */
class FuseWidget : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        render(context, manager, ids, last ?: WidgetState(false, null, null, false, null))
    }

    companion object {
        @Volatile private var last: WidgetState? = null

        /** The connection is going away: a widget left saying "Linked" would be a lie. */
        fun markOffline(context: Context) =
            update(context, (last ?: WidgetState(false, null, null, false, null)).copy(linked = false, macBattery = null))

        fun update(context: Context, state: WidgetState) {
            if (state == last) return
            last = state
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(ComponentName(context, FuseWidget::class.java))
            if (ids.isNotEmpty()) render(context, manager, ids, state)
        }

        private fun render(context: Context, manager: AppWidgetManager, ids: IntArray, state: WidgetState) {
            val views = RemoteViews(context.packageName, R.layout.widget_fuse).apply {
                setImageViewResource(R.id.widget_dot, if (state.linked) R.drawable.widget_dot else R.drawable.widget_dot_off)
                setTextViewText(R.id.widget_title, state.macName ?: "FuseOS")
                setTextViewText(
                    R.id.widget_status,
                    if (state.linked) "Linked · direct over Wi-Fi" else "Not linked — open FuseOS on your Mac",
                )
                setTextViewText(
                    R.id.widget_battery,
                    state.macBattery?.let { if (state.macCharging) "⚡ $it%" else "$it%" } ?: "",
                )
                setTextViewText(
                    R.id.widget_clip,
                    state.lastClip?.lines()?.joinToString(" ") { it.trim() } ?: "Copy something and it shows up here.",
                )
                setOnClickPendingIntent(R.id.widget_send, activity(context, 1, CaptureActivity.intent(context)))
                setOnClickPendingIntent(
                    R.id.widget_trackpad,
                    activity(context, 2, Intent(context, TrackpadActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)),
                )
                setOnClickPendingIntent(R.id.widget_open, activity(context, 3, Intent(context, MainActivity::class.java)))
                setOnClickPendingIntent(R.id.widget_root, activity(context, 3, Intent(context, MainActivity::class.java)))
            }
            manager.updateAppWidget(ids, views)
        }

        private fun activity(context: Context, code: Int, intent: Intent) = PendingIntent.getActivity(
            context, code, intent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
    }
}
