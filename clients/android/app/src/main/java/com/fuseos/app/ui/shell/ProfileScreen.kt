package com.fuseos.app.ui.shell

import com.fuseos.app.ui.components.glassCard
import androidx.compose.foundation.background
import androidx.compose.material3.Button
import androidx.compose.foundation.layout.Arrangement
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
    onRemoveDevice: (String) -> Unit,
    onSignOut: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier = modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 16.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(horizontal = 4.dp)) {
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
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }

        // Renaming has to be reachable, or the name is a one-time decision made before
        // you have seen how it reads on the other device.
        var draft by remember(deviceName) { mutableStateOf(deviceName.orEmpty()) }
        Panel(title = "This phone") {
            FuseTextField(value = draft, onValueChange = { draft = it }, label = "Device name")
            Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(top = 8.dp, start = 4.dp)) {
                Text(
                    "Your Mac shows this name.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.weight(1f),
                )
                Button(
                    onClick = { draft.trim().takeIf { it.isNotEmpty() }?.let(onRename) },
                    enabled = draft.trim().isNotEmpty() && draft.trim() != deviceName,
                    shape = CircleShape,
                ) { Text("Save") }
            }
        }

        Panel(title = "Your devices") {
            DeviceCard(
                name = state.selfDevice?.name ?: "This phone",
                subtitle = "This phone",
                platform = "android",
                online = true,
                battery = selfBattery,
            )
            // Every record, stale ones included, so an old one can be removed here.
            state.allPeers.sortedBy { if (it.id in state.connected) 0 else 1 }.forEach { device ->
                val linked = device.id in state.connected
                val online = linked || state.presence[device.id]?.online == true
                DeviceCard(
                    name = device.name,
                    subtitle = when {
                        linked -> "Linked · direct"
                        online -> "Online"
                        else -> "Offline"
                    },
                    platform = device.platform,
                    online = online,
                    battery = peerBattery(device.id),
                    onRemove = if (online) null else ({ onRemoveDevice(device.id) }),
                )
            }
        }

        Panel(title = "On this phone") {
            SettingItem(
                "Notification sync",
                if (notificationAccess) "This phone's notifications show up on your Mac."
                else "Allow notification access to see this phone's notifications on your Mac.",
                onNotifications,
                trailing = when {
                    !notificationAccess -> "Set up"
                    notificationsOn -> "On"
                    else -> "Off"
                },
                trailingLit = notificationAccess && notificationsOn,
            )
            SettingItem(
                "Island",
                if (islandEnabled) "Copies show up over whatever app you're in. Tap to send."
                else "Let FuseOS draw over other apps, so a copy can go without leaving the app you're in.",
                onEnableIsland,
                trailing = if (islandEnabled) "On" else "Set up",
                trailingLit = islandEnabled,
            )
            SettingItem(
                "Auto-capture",
                // Naming the real reason, because "install a keyboard to sync your
                // clipboard" is otherwise a bizarre thing to be asked.
                if (keyboardActive) "FuseOS is your keyboard, so a copy anywhere brings up the island."
                else "Android only lets your keyboard read the clipboard in the background.",
                onKeyboardSetup,
                trailing = if (keyboardActive) "On" else "Off",
                trailingLit = keyboardActive,
            )
            // Null below Android 13, where there is no API to offer this. A row that
            // cannot do anything is worse than no row.
            onAddTile?.let { addTile ->
                SettingItem(
                    "Quick Settings tile",
                    "Puts \"Send clipboard\" in your shade: one pull and one tap from any app.",
                    addTile,
                )
            }
            SettingItem(
                "Background activity",
                // Naming the real cause: on these phones the OS, not the app, is what stops
                // sync when the screen goes off.
                "Some phones freeze apps when the screen is off. Allow it to keep the link up.",
                onBatterySettings,
            )
        }

        Panel(title = "Account") {
            SettingItem(
                "Link with a code",
                "Devices on this account link themselves. Use a code only if one didn't show up.",
                onLinkManually,
            )
            SettingItem("Sign out", "Clears this phone's session and clipboard history.", onSignOut, destructive = true)
        }

        Spacer(Modifier.height(110.dp))
    }
}

