package com.fuseos.app

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.content.ContextCompat
import androidx.lifecycle.lifecycleScope
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.ui.Modifier
import com.fuseos.app.data.ServiceLocator
import com.fuseos.app.service.FuseConnectionService
import com.fuseos.app.ui.AppRoot
import com.fuseos.app.ui.DemoMode
import com.fuseos.app.ui.theme.FuseOSTheme
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.launch

class MainActivity : ComponentActivity() {

    /** The service runs either way; this only decides whether its notification is visible. */
    private val requestNotifications =
        registerForActivityResult(ActivityResultContracts.RequestPermission()) { }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        DemoMode.enableFrom(intent)
        askForNotificationsIfNeeded()

        // Signing in starts the background connection, signing out ends it. Tying it to the
        // token rather than to this activity is what lets the connection outlive the UI —
        // which is the entire point of the service.
        lifecycleScope.launch {
            ServiceLocator.authRepository.tokenFlow.distinctUntilChanged().collect { token ->
                if (token != null) {
                    FuseConnectionService.start(this@MainActivity)
                } else {
                    FuseConnectionService.stop(this@MainActivity)
                }
            }
        }
        setContent {
            FuseOSTheme {
                Surface(
                    modifier = Modifier.fillMaxSize(),
                    color = MaterialTheme.colorScheme.background,
                ) {
                    AppRoot()
                }
            }
        }
    }

    private fun askForNotificationsIfNeeded() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return
        val granted = ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
        if (!granted) requestNotifications.launch(Manifest.permission.POST_NOTIFICATIONS)
    }
}
