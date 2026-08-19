package com.fuseos.app.ui.shell

import android.content.Intent
import android.net.Uri
import android.provider.Settings
import android.widget.Toast
import androidx.compose.animation.Crossfade
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ScreenShare
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.fuseos.app.data.ServiceLocator
import com.fuseos.app.ui.components.ErrorBanner
import com.fuseos.app.ui.components.FuseWordmark
import com.fuseos.app.ui.dashboard.DashboardViewModel

/**
 * The signed-in app: one view model, five slots, a floating glass bar over all of them.
 *
 * Tabs are held in local state rather than a nav library. There is no back stack to model
 * and no deep links yet, so a Navigation dependency would buy nothing a `when` does not.
 */
@Composable
fun FuseShell() {
    val viewModel: DashboardViewModel = viewModel(factory = DashboardViewModel.Factory)
    val state by viewModel.state.collectAsState()
    val history by viewModel.history.collectAsState()
    val email by ServiceLocator.session.emailFlow.collectAsState(initial = null)
    val deviceName by ServiceLocator.session.deviceNameFlow.collectAsState(initial = null)
    val context = LocalContext.current

    var tab by remember { mutableStateOf(FuseTab.Home) }
    val linked = state.connected.isNotEmpty()
    // With one other device this is always the right name; with several, the connected
    // one is the only device a clip can have come from.
    val peerName = state.peers.firstOrNull { it.id in state.connected }?.name
        ?: state.peers.firstOrNull()?.name

    Box(
        Modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.background)
            .systemBarsPadding(),
    ) {
        Column(Modifier.fillMaxSize()) {
            Box(Modifier.padding(horizontal = 24.dp, vertical = 12.dp)) { FuseWordmark() }

            state.error?.let {
                Box(Modifier.padding(horizontal = 24.dp)) { ErrorBanner(it) }
                Spacer(Modifier.height(12.dp))
            }

            Crossfade(targetState = tab, animationSpec = tween(180), label = "tab") { current ->
                when (current) {
                    FuseTab.Home -> HomeScreen(
                        state = state,
                        history = history,
                        selfBattery = viewModel.selfBattery(),
                        peerBattery = { id -> state.presence[id]?.battery },
                        onCopy = viewModel::copyToClipboard,
                        onSeeAll = { tab = FuseTab.History },
                        peerName = peerName,
                    )

                    FuseTab.Screen -> ComingSoonScreen(
                        title = "Screen sharing",
                        detail = "See and control your Mac from here.",
                        icon = Icons.Filled.ScreenShare,
                    )

                    // Never selected: the centre button is an action, and tapping it
                    // leaves the current tab in place.
                    FuseTab.Send -> Box(Modifier.fillMaxSize())

                    FuseTab.History -> HistoryScreen(
                        entries = history,
                        peerName = peerName,
                        onCopy = viewModel::copyToClipboard,
                    )

                    FuseTab.Profile -> ProfileScreen(
                        email = email,
                        state = state,
                        deviceName = deviceName,
                        selfBattery = viewModel.selfBattery(),
                        onRename = viewModel::renameThisDevice,
                        peerBattery = { id -> state.presence[id]?.battery },
                        onBatterySettings = {
                            // Opens the OS screen; there is no API to grant this for the
                            // user, and on ColorOS this is the setting that actually
                            // stops the app being frozen.
                            runCatching {
                                context.startActivity(
                                    Intent(
                                        Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                                        Uri.parse("package:${context.packageName}"),
                                    ),
                                )
                            }
                        },
                        onSignOut = viewModel::signOut,
                    )
                }
            }
        }

        FuseNavBar(
            selected = tab,
            onSelect = { tab = it },
            centreEnabled = linked,
            onCentreTap = {
                val sent = viewModel.sendCurrentClipboard()
                Toast.makeText(
                    context,
                    if (sent) "Sent to your Mac" else "Nothing on the clipboard to send",
                    Toast.LENGTH_SHORT,
                ).show()
            },
            modifier = Modifier
                .align(Alignment.BottomCenter)
                .padding(bottom = 12.dp),
        )
    }
}
