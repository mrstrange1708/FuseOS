package com.fuseos.app

import android.app.Application
import com.fuseos.app.data.ServiceLocator
import io.sentry.android.core.SentryAndroid

class FuseApp : Application() {
    override fun onCreate() {
        super.onCreate()
        startSentry()
        ServiceLocator.init(this)
    }

    /**
     * Crash and error reports, and nothing a person copied, typed or received (CLAUDE.md
     * principle 6): no screenshots, no view hierarchy, no tap breadcrumbs (a tapped
     * Compose node can carry its text), no PII. What arrives is the stack, the device model
     * and OS, and the app version.
     */
    private fun startSentry() {
        if (BuildConfig.SENTRY_DSN.isEmpty()) return
        SentryAndroid.init(this) { options ->
            options.dsn = BuildConfig.SENTRY_DSN
            options.environment = if (BuildConfig.DEBUG) "debug" else "production"
            options.release = "fuseos-android@${BuildConfig.VERSION_NAME}+${BuildConfig.VERSION_CODE}"
            options.isSendDefaultPii = false
            options.isAttachScreenshot = false
            options.isAttachViewHierarchy = false
            options.isEnableUserInteractionBreadcrumbs = false
            options.isEnableUserInteractionTracing = false
        }
    }
}
