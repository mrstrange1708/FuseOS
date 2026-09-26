package com.fuseos.app.ui.shell

import com.fuseos.app.ui.components.glassCard
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.fuseos.app.ui.dashboard.DashboardViewModel
import com.fuseos.app.ui.components.FuseTextField
import com.fuseos.app.ui.dashboard.DeviceCard

/**
 * Account, the devices on it, and the way out.
 *
 * The device list lives here rather than on its own tab because it is reference material:
 * people check it when something is wrong, not on every visit. Home already answers the
 * everyday question of whether the link is up.
 */
@Composable
fun ProfileScreen(
    email: String?,
    state: DashboardViewModel.UiState,
    peerBattery: (String) -> Int?,
    deviceName: String?,
    onLinkManually: () -> Unit,
    islandEnabled: Boolean,
    onEnableIsland: () -> Unit,
    onAddTile: (() -> Unit)?,
    keyboardActive: Boolean,
    onKeyboardSetup: () -> Unit,
    selfBattery: Int?,
    onRename: (String) -> Unit,
    onBatterySettings: () -> Unit,
    notificationAccess: Boolean,
    notificationsOn: Boolean,
    onNotifications: () -> Unit,
    onSignOut: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier = modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 24.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Box(
                Modifier
                    .size(52.dp)
                    .clip(CircleShape)
                    .background(MaterialTheme.colorScheme.primary.copy(alpha = 0.16f)),
                contentAlignment = Alignment.Center,
            ) {
                Text(
                    email?.take(1)?.uppercase() ?: "?",
                    style = MaterialTheme.typography.titleLarge,
                    color = MaterialTheme.colorScheme.primary,
                )
            }
            Spacer(Modifier.size(14.dp))
            Column {
                Text(
                    email ?: "Signed in",
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.SemiBold,
                )
                Text(
                    "${state.peers.size + 1} device${if (state.peers.isEmpty()) "" else "s"} · " +
                        "${state.connected.size} linked",
                    style = MaterialTheme.typography.labelMedium,
                    fontFamily = FontFamily.Monospace,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }

        Spacer(Modifier.height(24.dp))
        // Renaming has to be reachable, or the name is a one-time decision made before
        // you have seen how it reads on the other device.
        var draft by remember(deviceName) { mutableStateOf(deviceName.orEmpty()) }
        Text("This phone's name", style = MaterialTheme.typography.titleMedium)
        Spacer(Modifier.height(8.dp))
        FuseTextField(value = draft, onValueChange = { draft = it }, label = "Device name")
        Spacer(Modifier.height(8.dp))
        SettingRow("Save name", "Your Mac shows this name.") {
            draft.trim().takeIf { it.isNotEmpty() }?.let(onRename)
        }

        Spacer(Modifier.height(26.dp))
        Text("Your devices", style = MaterialTheme.typography.titleMedium)
        Spacer(Modifier.height(10.dp))

        DeviceCard(
            name = state.selfDevice?.name ?: "This phone",
            subtitle = "This device",
            platform = "android",
            online = true,
            battery = selfBattery,
        )
        state.peers.forEach { device ->
            Spacer(Modifier.height(10.dp))
            DeviceCard(
                name = device.name,
                subtitle = if (device.id in state.connected) "connected · direct" else "not connected",
                platform = device.platform,
                online = device.id in state.connected,
                battery = peerBattery(device.id),
            )
        }

        Spacer(Modifier.height(14.dp))
        Spacer(Modifier.height(10.dp))
        SettingRow(
            "Link manually",
            "Devices on this account link themselves. Use a code only if one didn't show up.",
            onLinkManually,
        )
        Spacer(Modifier.height(10.dp))
        SettingRow(
            if (islandEnabled) "Island · on" else "Turn on the island",
            if (islandEnabled) {
                "Copies show up over whatever app you're in. Tap the island to send."
            } else {
                "Allow FuseOS to draw over other apps, so a copy can be sent without " +
                    "leaving the app you're in."
            },
            onEnableIsland,
        )
        Spacer(Modifier.height(10.dp))
        SettingRow(
            if (keyboardActive) "Auto-capture · on" else "Turn on auto-capture",
            if (keyboardActive) {
                "FuseOS is your keyboard, so copying anywhere brings up the island by itself."
            } else {
                // Naming the real reason, because "install a keyboard to sync your
                // clipboard" is otherwise a bizarre thing to be asked.
                "Android only lets your keyboard read the clipboard in the background. " +
                    "Make FuseOS your keyboard and a copy in any app pops the island on " +
                    "its own — no tile, no tap to reach it."
            },
            onKeyboardSetup,
        )

        Spacer(Modifier.height(10.dp))
        SettingRow(
            when {
                !notificationAccess -> "Turn on notification sync"
                notificationsOn -> "Notification sync · on"
                else -> "Notification sync · off"
            },
            when {
                !notificationAccess ->
                    "Allow FuseOS notification access, and this phone's notifications show up " +
                        "on your Mac while they're linked."
                notificationsOn -> "Your notifications show up on your Mac. Tap to pause."
                else -> "Paused. Tap to show this phone's notifications on your Mac again."
            },
            onNotifications,
        )

        // Null below Android 13, where there is no API to offer this and the user has to
        // edit the shade themselves. Showing a row that cannot do anything is worse than
        // not showing one.
        onAddTile?.let { addTile ->
            Spacer(Modifier.height(10.dp))
            SettingRow(
                "Add the Quick Settings tile",
                "Puts \"Send clipboard\" in your shade, so a copy is one pull and one tap " +
                    "away from any app.",
                addTile,
            )
        }
        Spacer(Modifier.height(10.dp))
        SettingRow(
            "Background permission",
            // Naming the real cause: on these phones the OS, not the app, is what stops
            // sync when the screen goes off.
            "Some phones freeze apps when the screen is off. Allow background activity to keep the link up.",
            onBatterySettings,
        )
        Spacer(Modifier.height(10.dp))
        SettingRow("Sign out", "Clears this device's session and clipboard history", onSignOut)

        Spacer(Modifier.height(120.dp))
    }
}

@Composable
private fun SettingRow(title: String, detail: String, onClick: () -> Unit) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .glassCard(16.dp)
            .clickable(onClick = onClick)
            .padding(16.dp),
    ) {
        Text(title, fontWeight = FontWeight.SemiBold)
        Spacer(Modifier.height(3.dp))
        Text(
            detail,
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}
