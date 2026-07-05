package com.fuseos.app

import android.app.Application
import com.fuseos.app.data.ServiceLocator

class FuseApp : Application() {
    override fun onCreate() {
        super.onCreate()
        ServiceLocator.init(this)
    }
}
