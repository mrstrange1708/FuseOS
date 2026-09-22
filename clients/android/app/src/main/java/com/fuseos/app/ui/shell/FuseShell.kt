package com.fuseos.app.ui.shell

import android.content.Intent
import android.net.Uri
import android.provider.Settings
import android.widget.Toast
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
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
import com.fuseos.app.file.Transfers
import com.fuseos.app.ui.components.ErrorBanner
import com.fuseos.app.ui.components.FuseWordmark
import com.fuseos.app.ui.dashboard.DashboardViewModel
import com.fuseos.app.service.ClipTile
import com.fuseos.app.ui.island.ClipIsland
import com.fuseos.app.ui.dashboard.PairingScreen

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
    val transfers by ServiceLocator.transfers.list.collectAsState()
    // The system picker, not a file browser of our own: it reaches Drive, Downloads and
    // every other provider with no storage permission at all.
    val pickFile = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri == null) return@rememberLauncherForActivityResult
        val message = when (ServiceLocator.transfers.send(uri)) {
            Transfers.SendResult.Started -> null
            Transfers.SendResult.NoPeer -> "No device connected. Open FuseOS on your Mac."
            Transfers.SendResult.Unreadable -> "Couldn't read that file."
            Transfers.SendResult.TooLarge -> "That file is over the 1 GB limit."
        }
        message?.let { Toast.makeText(context, it, Toast.LENGTH_SHORT).show() }
    }

    var tab by remember { mutableStateOf(FuseTab.Home) }
    var showPairing by remember { mutableStateOf(false) }

    if (showPairing) {
        PairingScreen(viewModel = viewModel, onClose = { showPairing = false })
        return
    }
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
                        transfers = transfers,
                        onSendFile = { pickFile.launch(arrayOf("*/*")) },
                        onCancelTransfer = ServiceLocator.transfers::cancel,
                        onOpenTransfer = { id ->
                            if (!ServiceLocator.transfers.open(id)) {
                                Toast.makeText(context, "That file has moved or been deleted.", Toast.LENGTH_SHORT).show()
                            }
                        },
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
                        onLinkManually = { showPairing = true },
                        // Read on every recomposition rather than cached: the user grants
                        // this in Settings and comes back, so a snapshot taken on first
                        // draw would still read "off" when they return.
                        islandEnabled = ServiceLocator.clipIsland.canDraw(),
                        onAddTile = tileAdder(context),
                        keyboardActive = isFuseKeyboard(context),
                        onKeyboardSetup = { setUpKeyboard(context) },
                        onEnableIsland = {
                            runCatching {
                                context.startActivity(ClipIsland.overlaySettingsIntent(context))
                            }
                        },
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

/**
 * Offers to add the "Send clipboard" tile, or null where the platform cannot.
 *
 * Android will not place a tile on a user's behalf, and before API 33 it would not even
 * ask — the user had to find the shade's edit screen unaided, which most people never do.
 * `requestAddTileService` is the ask, and it is the difference between a tile that exists
 * and a tile that is used.
 */
private fun tileAdder(context: android.content.Context): (() -> Unit)? {
    if (android.os.Build.VERSION.SDK_INT < android.os.Build.VERSION_CODES.TIRAMISU) return null
    return {
        runCatching {
            context.getSystemService(android.app.StatusBarManager::class.java)
                ?.requestAddTileService(
                    android.content.ComponentName(context, ClipTile::class.java),
                    "Send clipboard",
                    android.graphics.drawable.Icon.createWithResource(
                        context, com.fuseos.app.R.drawable.ic_notification,
                    ),
                    {  it.run() },
                    {},
                )
        }
    }
}

/** True when FuseOS is the selected input method — which is what lifts the clipboard block. */
private fun isFuseKeyboard(context: android.content.Context): Boolean =
    Settings.Secure.getString(
        context.contentResolver, Settings.Secure.DEFAULT_INPUT_METHOD,
    )?.startsWith(context.packageName) == true

/**
 * Walks the user to making FuseOS the keyboard — two steps, because Android splits them.
 *
 * A keyboard must first be *enabled* in Settings (an explicit warning screen no app may
 * skip), and only then can it be *selected*. Sending someone straight to the picker before
 * enabling shows a list FuseOS is not in, which reads as the feature being broken.
 */
private fun setUpKeyboard(context: android.content.Context) {
    val manager = context.getSystemService(android.view.inputmethod.InputMethodManager::class.java)
    val enabled = manager?.enabledInputMethodList.orEmpty().any {
        it.packageName == context.packageName
    }
    runCatching {
        if (enabled) {
            manager?.showInputMethodPicker()
        } else {
            context.startActivity(
                Intent(Settings.ACTION_INPUT_METHOD_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            )
        }
    }
}
