package com.fuseos.app.ui.shell

import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ContentPaste
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.History
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.ScreenShare
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import com.fuseos.app.ui.components.glassCard
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/** The five destinations, in bar order. The centre is the send action, not a page. */
enum class FuseTab(val label: String, val icon: ImageVector) {
    Home("Home", Icons.Filled.Home),
    Screen("Screen", Icons.Filled.ScreenShare),
    Send("Send", Icons.Filled.ContentPaste),
    History("History", Icons.Filled.History),
    Profile("You", Icons.Filled.Person),
}

/**
 * The glass bar: two destinations, a raised centre action, two more.
 *
 * The centre is deliberately a *verb* rather than a fifth page — pushing the clipboard is
 * the thing people come to this app to do, and burying it in a tab would put the most
 * common action at the same depth as the account screen.
 */
@Composable
fun FuseNavBar(
    selected: FuseTab,
    onSelect: (FuseTab) -> Unit,
    onCentreTap: () -> Unit,
    centreEnabled: Boolean,
    modifier: Modifier = Modifier,
) {
    Box(modifier = modifier.fillMaxWidth(), contentAlignment = Alignment.BottomCenter) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp)
                .height(64.dp)
                // Glass: a translucent wash over the background plus a hairline edge. A
                // flat opaque bar reads as a separate slab; this keeps the content
                // visible under it and the bar attached to the page.
                // Near-solid: text scrolling under a see-through bar read as clutter. The
                // fade behind it (FuseShell) does the "floating" instead.
                .glassCard(28.dp)
                .background(MaterialTheme.colorScheme.surface.copy(alpha = 0.92f)),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceEvenly,
        ) {
            NavItem(FuseTab.Home, selected, onSelect, Modifier.weight(1f))
            NavItem(FuseTab.Screen, selected, onSelect, Modifier.weight(1f))
            // Holds the gap the raised centre button sits in.
            Box(Modifier.weight(1f))
            NavItem(FuseTab.History, selected, onSelect, Modifier.weight(1f))
            NavItem(FuseTab.Profile, selected, onSelect, Modifier.weight(1f))
        }

        CentreButton(enabled = centreEnabled, onTap = onCentreTap, modifier = Modifier.offset(y = (-18).dp))
    }
}

@Composable
private fun NavItem(
    tab: FuseTab,
    selected: FuseTab,
    onSelect: (FuseTab) -> Unit,
    modifier: Modifier = Modifier,
) {
    val isSelected = tab == selected
    val tint by animateColorAsState(
        if (isSelected) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant,
        label = "nav-tint",
    )
    // The open tab's icon sits in an ember pill — the same mark the Mac's glass bar uses.
    val pill by animateColorAsState(
        if (isSelected) MaterialTheme.colorScheme.primary.copy(alpha = 0.16f) else Color.Transparent,
        label = "nav-pill",
    )
    Column(
        modifier = modifier
            .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = null,
                onClick = { onSelect(tab) },
            )
            .padding(vertical = 6.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Box(
            Modifier
                .size(width = 52.dp, height = 28.dp)
                .clip(CircleShape)
                .background(pill),
            contentAlignment = Alignment.Center,
        ) {
            Icon(tab.icon, contentDescription = tab.label, tint = tint, modifier = Modifier.size(21.dp))
        }
        Text(
            tab.label,
            fontSize = 10.5.sp,
            fontWeight = if (isSelected) FontWeight.SemiBold else FontWeight.Normal,
            color = tint,
        )
    }
}

/** The raised centre: send this device's clipboard to the other one, in one tap. */
@Composable
private fun CentreButton(enabled: Boolean, onTap: () -> Unit, modifier: Modifier = Modifier) {
    val scale by animateFloatAsState(
        if (enabled) 1f else 0.92f,
        spring(dampingRatio = 0.6f),
        label = "centre-scale",
    )
    val ring = MaterialTheme.colorScheme.primary
    Box(
        modifier = modifier
            .size(60.dp)
            .scale(scale)
            .semantics { contentDescription = "Send clipboard to your other device" }
            .clip(CircleShape)
            .background(
                if (enabled) {
                    Brush.verticalGradient(listOf(ring, ring.copy(alpha = 0.82f)))
                } else {
                    // Disconnected: the button stays visible but plainly inert, rather
                    // than vanishing and making the bar jump.
                    Brush.verticalGradient(
                        listOf(
                            MaterialTheme.colorScheme.surfaceVariant,
                            MaterialTheme.colorScheme.surfaceVariant,
                        ),
                    )
                },
            )
            .border(3.dp, MaterialTheme.colorScheme.background, CircleShape)
            .clickable(enabled = enabled, onClick = onTap),
        contentAlignment = Alignment.Center,
    ) {
        // The mark itself: two devices joined by a link — the app's whole idea, and the
        // "hole in the middle" of the bar.
        Row(verticalAlignment = Alignment.CenterVertically) {
            Box(
                Modifier
                    .size(9.dp)
                    .border(2.dp, if (enabled) Color.White else MaterialTheme.colorScheme.outline, CircleShape),
            )
            Box(
                Modifier
                    .size(width = 8.dp, height = 2.dp)
                    .background(if (enabled) Color.White else MaterialTheme.colorScheme.outline),
            )
            Box(
                Modifier
                    .size(9.dp)
                    .clip(CircleShape)
                    .background(if (enabled) Color.White else MaterialTheme.colorScheme.outline),
            )
        }
    }
}
