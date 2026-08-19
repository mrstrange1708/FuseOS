package com.fuseos.app.ui.connect

import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
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
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.fuseos.app.core.ConnectStage
import com.fuseos.app.ui.components.ErrorBanner
import com.fuseos.app.ui.components.FusePrimaryButton
import com.fuseos.app.ui.components.FuseMark
import com.fuseos.app.ui.components.FuseWordmark
import com.fuseos.app.ui.dashboard.DashboardViewModel
import com.fuseos.app.ui.dashboard.PairingScreen

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
    var showPairing by remember { mutableStateOf(false) }

    if (showPairing) {
        PairingScreen(viewModel = viewModel, onClose = { showPairing = false })
        return
    }

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

        LinkDiagram(
            stage = connect.stage,
            selfName = state.selfDevice?.name ?: "This phone",
            peerName = peer?.name ?: "Your Mac",
            peerCaption = peerCaption(connect.stage),
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
                Spacer(Modifier.weight(1f))
                TextButton(onClick = { showPairing = true }) { Text("Link manually") }
            }
        }

        state.error?.let {
            Spacer(Modifier.height(16.dp))
            ErrorBanner(it)
        }
    }
}

/**
 * The two devices, the link between them, and the mark that lights when it is live.
 *
 * This is the whole status in one picture, so it is drawn rather than described: a phone
 * and a laptop as recognisable silhouettes, a channel between them that carries a pulse
 * while dialling and goes solid on connect, and the FuseOS mark riding the middle of it.
 *
 * Mirrors `LinkDiagram` in `ConnectView.swift` — the two screens are the same screen.
 */
@Composable
private fun LinkDiagram(
    stage: ConnectStage,
    selfName: String,
    peerName: String,
    peerCaption: String,
) {
    val live = stage == ConnectStage.Connected
    Column(Modifier.fillMaxWidth()) {
        Row(
            modifier = Modifier.fillMaxWidth().height(86.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            DeviceFigure(phone = true, lit = true, modifier = Modifier.size(56.dp, 84.dp))
            LinkChannel(stage = stage, modifier = Modifier.weight(1f).height(84.dp))
            DeviceFigure(phone = false, lit = live, modifier = Modifier.size(108.dp, 84.dp))
        }
        Spacer(Modifier.height(12.dp))
        Row(Modifier.fillMaxWidth()) {
            Caption(selfName, "this device", lit = true, modifier = Modifier.weight(1f))
            Caption(peerName, peerCaption, lit = live, modifier = Modifier.weight(1f))
        }
    }
}

@Composable
private fun Caption(title: String, detail: String, lit: Boolean, modifier: Modifier = Modifier) {
    Column(modifier, horizontalAlignment = Alignment.CenterHorizontally) {
        Text(
            title,
            style = MaterialTheme.typography.bodyMedium,
            fontWeight = FontWeight.SemiBold,
            maxLines = 1,
        )
        Text(
            detail,
            fontFamily = FontFamily.Monospace,
            style = MaterialTheme.typography.labelSmall,
            color = if (lit) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant,
            maxLines = 1,
        )
    }
}

/**
 * A phone or a laptop, drawn rather than borrowed from an icon set so the two read as the
 * same family and the screen can light up independently of the body.
 */
@Composable
private fun DeviceFigure(phone: Boolean, lit: Boolean, modifier: Modifier = Modifier) {
    val outline = MaterialTheme.colorScheme.onSurface
    val accent = MaterialTheme.colorScheme.primary
    val dim = MaterialTheme.colorScheme.outlineVariant
    val surfaceAlt = MaterialTheme.colorScheme.surfaceVariant

    Canvas(modifier) {
        val stroke = if (lit) outline.copy(alpha = 0.75f) else dim
        val screen = if (lit) accent.copy(alpha = 0.16f) else surfaceAlt
        val w = size.width
        val h = size.height

        if (phone) {
            val bw = w * 0.76f
            val bh = h * 0.88f
            val left = (w - bw) / 2f
            val top = (h - bh) / 2f
            val radius = androidx.compose.ui.geometry.CornerRadius(w * 0.16f, w * 0.16f)
            drawRoundRect(screen, Offset(left, top), Size(bw, bh), radius)
            drawRoundRect(stroke, Offset(left, top), Size(bw, bh), radius, style = Stroke(width = 4f))
            // The speaker slot: the one detail that stops a rounded rectangle from
            // reading as a generic tile.
            drawLine(
                stroke.copy(alpha = 0.7f),
                Offset(w / 2f - bw * 0.14f, top + bh * 0.09f),
                Offset(w / 2f + bw * 0.14f, top + bh * 0.09f),
                strokeWidth = 5f,
            )
        } else {
            val lidW = w * 0.74f
            val lidH = h * 0.68f
            val left = (w - lidW) / 2f
            val radius = androidx.compose.ui.geometry.CornerRadius(8f, 8f)
            drawRoundRect(screen, Offset(left, 0f), Size(lidW, lidH), radius)
            drawRoundRect(stroke, Offset(left, 0f), Size(lidW, lidH), radius, style = Stroke(width = 4f))
            // The base is wider than the lid and barely tall — that proportion is the
            // entire reason this reads as a laptop and not as a monitor.
            drawRoundRect(
                stroke.copy(alpha = 0.85f),
                Offset(0f, lidH + 4f),
                Size(w, 9f),
                androidx.compose.ui.geometry.CornerRadius(4f, 4f),
            )
        }
    }
}

/**
 * The channel between the devices: a rail, a pulse that runs it while dialling, and the
 * FuseOS mark sitting on top of it.
 */
@Composable
private fun LinkChannel(stage: ConnectStage, modifier: Modifier = Modifier) {
    val live = stage == ConnectStage.Connected
    val dialling = stage == ConnectStage.Connecting
    val accent = MaterialTheme.colorScheme.primary
    val dim = MaterialTheme.colorScheme.outlineVariant
    val background = MaterialTheme.colorScheme.background

    // The comet only animates while we are actually dialling, so a screen sitting at
    // PeerOffline for an hour is not repainting something nobody is watching.
    val transition = rememberInfiniteTransition(label = "channel")
    val sweep by transition.animateFloat(
        initialValue = 0f,
        targetValue = if (dialling) 1f else 0f,
        animationSpec = infiniteRepeatable(tween(1400, easing = LinearEasing), RepeatMode.Restart),
        label = "sweep",
    )
    val glow by transition.animateFloat(
        initialValue = if (live) 0.35f else 0f,
        targetValue = if (live) 0.9f else 0f,
        animationSpec = infiniteRepeatable(tween(1600), RepeatMode.Reverse),
        label = "glow",
    )

    Box(modifier, contentAlignment = Alignment.Center) {
        Canvas(Modifier.fillMaxWidth().height(84.dp)) {
            val midY = size.height / 2f
            // Dashed until a channel exists, solid once one does — a broken line for a
            // broken link is the one piece of this that needs no caption.
            drawLine(
                color = if (live) accent else dim,
                start = Offset(0f, midY),
                end = Offset(size.width, midY),
                strokeWidth = if (live) 5f else 4f,
                pathEffect = if (live) null else PathEffect.dashPathEffect(floatArrayOf(10f, 13f)),
            )
            if (dialling) {
                // The comet — this is the preloader. It says "something is happening"
                // without a spinner, and it travels the way the connection is being made.
                val head = sweep * size.width
                val tail = size.width * 0.4f
                drawLine(
                    brush = Brush.horizontalGradient(
                        colors = listOf(Color.Transparent, accent, Color.Transparent),
                        startX = head - tail / 2f,
                        endX = head + tail / 2f,
                    ),
                    start = Offset((head - tail / 2f).coerceAtLeast(0f), midY),
                    end = Offset((head + tail / 2f).coerceAtMost(size.width), midY),
                    strokeWidth = 6f,
                )
            }
        }
        // The mark rides the middle of the rail and lights only when the channel is real,
        // so the logo itself is the status.
        Box(contentAlignment = Alignment.Center) {
            Canvas(Modifier.size(38.dp)) {
                drawCircle(background, radius = size.minDimension / 2f)
                if (live) {
                    drawCircle(accent.copy(alpha = glow * 0.3f), radius = size.minDimension / 2f + 10f)
                }
                drawCircle(
                    if (live) accent else dim,
                    radius = size.minDimension / 2f,
                    style = Stroke(width = if (live) 4f else 3f),
                )
            }
            Box(Modifier.alpha(if (live) 1f else 0.45f)) { FuseMark(height = 13.dp) }
        }
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
