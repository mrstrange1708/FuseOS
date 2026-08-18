package com.fuseos.app.ui.device

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.compose.ui.platform.LocalContext
import com.fuseos.app.core.DeviceInfo
import com.fuseos.app.data.ServiceLocator
import com.fuseos.app.ui.components.AuthSwitchRow
import com.fuseos.app.ui.components.FusePrimaryButton
import com.fuseos.app.ui.components.FuseTextField
import com.fuseos.app.ui.components.FuseWordmark
import kotlinx.coroutines.launch
import androidx.compose.runtime.rememberCoroutineScope

/**
 * Post-login step: name this phone.
 *
 * This replaces a "What device is this?" platform picker. The app is an Android app;
 * asking the user to tell it so was a question it already knew the answer to, the answer
 * was ignored by registration (which hardcodes the platform), and picking wrong only ever
 * produced a phone that drew itself as a Mac.
 *
 * The name is the thing that actually needs a human: the Mac shows it in every list, and
 * "Junaid's phone" is worth more there than "Realme RMX3998".
 */
@Composable
fun DeviceNameScreen() {
    val context = LocalContext.current
    val repository = ServiceLocator.authRepository
    val scope = rememberCoroutineScope()

    val detected = remember { DeviceInfo(context).deviceName() }
    var name by remember { mutableStateOf(detected) }
    val trimmed = name.trim()

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.background)
            .systemBarsPadding()
            .verticalScroll(rememberScrollState())
            .padding(24.dp),
    ) {
        FuseWordmark()
        Spacer(Modifier.height(30.dp))

        Text("Name this phone", style = MaterialTheme.typography.headlineMedium)
        Spacer(Modifier.height(6.dp))
        Text(
            "This is how it appears on your other devices. You can change it later.",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Spacer(Modifier.height(26.dp))

        FuseTextField(value = name, onValueChange = { name = it }, label = "Device name")
        Spacer(Modifier.height(20.dp))

        FusePrimaryButton(
            text = "Continue",
            // An empty name would show as a blank row on the Mac, so the only way past
            // this screen is with something to display.
            enabled = trimmed.isNotEmpty(),
            onClick = { scope.launch { repository.setDeviceName(trimmed) } },
        )

        Spacer(Modifier.height(24.dp))
        AuthSwitchRow(prompt = "Not you?", action = "Sign out") {
            scope.launch { ServiceLocator.session.clear() }
        }
    }
}
