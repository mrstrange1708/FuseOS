package com.fuseos.app.ui.connect

import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.fuseos.app.core.ConnectStage
import com.fuseos.app.ui.components.ErrorBanner
import com.fuseos.app.ui.components.FusePrimaryButton
import com.fuseos.app.ui.components.FuseWordmark
import com.fuseos.app.ui.dashboard.DashboardViewModel
import com.fuseos.app.ui.dashboard.DeviceCard

/**
 * The connect space: this device, the device it's linking to, and the one thing to do next.
 *
 * It advances on its own as presence and the LAN channel change — there is nothing to
 * refresh, nothing to poll, and nothing to press. Signing in on the Mac is the entire link
 * step; the rest happens while the user watches. Only [ConnectStage.Connected] offers
 * Continue, so reaching the rest of the app means a real encrypted channel exists, not
 * merely that both devices are online.
 */
@Composable
fun ConnectScreen() {
    val viewModel: DashboardViewModel = viewModel(factory = DashboardViewModel.Factory)
    val state by viewModel.state.collectAsState()

    val connect = state.connect
    val peer = state.peers.firstOrNull { it.id == connect.peerId }
    val peerName = peer?.name ?: "your other device"

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.background)
            .systemBarsPadding()
            .padding(24.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            FuseWordmark()
            Spacer(Modifier.weight(1f))
            TextButton(onClick = { viewModel.signOut() }) { Text("Sign out") }
        }

        Spacer(Modifier.weight(1f))

        DeviceCard(
            name = state.selfDevice?.name ?: "This phone",
            subtitle = "This device",
            platform = "android",
            online = true,
            battery = viewModel.selfBattery(),
        )
        LinkBeam(stage = connect.stage)
        DeviceCard(
            name = peer?.name ?: "Your other device",
            subtitle = peerCaption(connect.stage),
            platform = peer?.platform ?: "macos",
            online = connect.stage == ConnectStage.Connected,
            battery = peer?.let { viewModel.presenceFor(it).battery },
        )

        Spacer(Modifier.weight(1f))

        Text(headline(connect.stage), style = MaterialTheme.typography.headlineSmall)
        Spacer(Modifier.height(6.dp))
        Text(
            detail(connect.stage, peerName, connect.selfSubnet, connect.peerSubnet),
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )

        Spacer(Modifier.height(20.dp))
        when (connect.stage) {
            ConnectStage.Connected ->
                FusePrimaryButton(text = "Continue", onClick = viewModel::markConnectDone)

            // Deliberately no Continue here: past this screen the app assumes a live
            // channel, so letting someone through early only moves the confusion later.
            // Nothing to press either — every one of these stages clears itself.
            else -> Row(verticalAlignment = Alignment.CenterVertically) {
                CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp)
                Spacer(Modifier.width(10.dp))
                Text(
                    "Waiting…",
                    fontFamily = FontFamily.Monospace,
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }

        state.error?.let {
            Spacer(Modifier.height(16.dp))
            ErrorBanner(it)
        }
    }
}

/** The line between the two devices — the whole status in one glance. */
@Composable
private fun LinkBeam(stage: ConnectStage) {
    val pulse = rememberInfiniteTransition(label = "beam")
    val alpha by pulse.animateFloat(
        initialValue = 1f,
        targetValue = if (stage == ConnectStage.Connecting) 0.25f else 1f,
        animationSpec = infiniteRepeatable(tween(900), RepeatMode.Reverse),
        label = "beam-alpha",
    )
    Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
        Box(
            Modifier
                .width(2.dp)
                .height(34.dp)
                .alpha(alpha)
                .background(
                    if (stage == ConnectStage.Connected) {
                        MaterialTheme.colorScheme.primary
                    } else {
                        MaterialTheme.colorScheme.outlineVariant
                    },
                ),
        )
    }
}

private fun headline(stage: ConnectStage): String = when (stage) {
    ConnectStage.Alone -> "Sign in on your Mac"
    ConnectStage.PeerOffline -> "Open FuseOS on your Mac"
    ConnectStage.DifferentNetwork -> "Same WiFi, please"
    ConnectStage.Connecting -> "Connecting…"
    ConnectStage.Connected -> "Connected"
}

private fun detail(
    stage: ConnectStage,
    peerName: String,
    selfSubnet: String?,
    peerSubnet: String?,
): String = when (stage) {
    ConnectStage.Alone ->
        "Install FuseOS on your Mac and sign in with this same account. There is no code to " +
            "scan — the two link themselves. Nothing you copy ever leaves your network."

    ConnectStage.PeerOffline ->
        "$peerName is on this account but isn't running FuseOS right now."

    ConnectStage.DifferentNetwork ->
        "This phone is on ${selfSubnet?.let { "$it.x" } ?: "another network"} and $peerName is on " +
            "${peerSubnet?.let { "$it.x" } ?: "another network"}. They have to share a network to talk directly."

    ConnectStage.Connecting ->
        "Both devices are on the same network. Opening a direct encrypted channel."

    ConnectStage.Connected ->
        "Your clipboard and files now move straight between these devices over your network."
}

private fun peerCaption(stage: ConnectStage): String = when (stage) {
    ConnectStage.Alone -> "not signed in yet"
    ConnectStage.PeerOffline -> "offline"
    ConnectStage.DifferentNetwork -> "different network"
    ConnectStage.Connecting -> "connecting…"
    ConnectStage.Connected -> "connected · direct"
}
