package com.fuseos.app.ui.auth

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import com.fuseos.app.ui.components.AuthSwitchRow
import com.fuseos.app.ui.components.ErrorBanner
import com.fuseos.app.ui.components.FusePrimaryButton
import com.fuseos.app.ui.components.FuseTextField
import com.fuseos.app.ui.components.FuseWordmark

@Composable
fun SignUpScreen(viewModel: AuthViewModel) {
    val state by viewModel.state.collectAsState()
    val focus = LocalFocusManager.current

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.background)
            .systemBarsPadding()
            .imePadding()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 24.dp),
        horizontalAlignment = Alignment.Start,
        verticalArrangement = Arrangement.Top,
    ) {
        Spacer(Modifier.height(56.dp))
        FuseWordmark()
        Spacer(Modifier.height(32.dp))

        Text("Create your account", style = MaterialTheme.typography.headlineMedium)
        Spacer(Modifier.height(6.dp))
        Text(
            "One account fuses all your devices.",
            style = MaterialTheme.typography.bodyLarge,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Spacer(Modifier.height(28.dp))

        FuseTextField(
            value = state.name,
            onValueChange = viewModel::onNameChange,
            label = "Your name",
            keyboardType = KeyboardType.Text,
            imeAction = ImeAction.Next,
            errorText = state.nameError,
            enabled = !state.isSubmitting,
        )
        Spacer(Modifier.height(14.dp))
        FuseTextField(
            value = state.email,
            onValueChange = viewModel::onEmailChange,
            label = "Email",
            keyboardType = KeyboardType.Email,
            imeAction = ImeAction.Next,
            errorText = state.emailError,
            enabled = !state.isSubmitting,
        )
        Spacer(Modifier.height(14.dp))
        FuseTextField(
            value = state.password,
            onValueChange = viewModel::onPasswordChange,
            label = "Password (min 8 characters)",
            isPassword = true,
            keyboardType = KeyboardType.Password,
            imeAction = ImeAction.Done,
            onImeAction = {
                focus.clearFocus()
                viewModel.submit()
            },
            errorText = state.passwordError,
            enabled = !state.isSubmitting,
        )

        if (state.error != null) {
            Spacer(Modifier.height(16.dp))
            ErrorBanner(state.error!!)
        }

        Spacer(Modifier.height(24.dp))
        FusePrimaryButton(
            text = "Create account",
            onClick = {
                focus.clearFocus()
                viewModel.submit()
            },
            loading = state.isSubmitting,
        )
        Spacer(Modifier.height(12.dp))
        AuthSwitchRow(
            prompt = "Already have an account?",
            action = "Sign in",
        ) { viewModel.switchTo(AuthMode.SignIn) }
        Spacer(Modifier.height(24.dp))
    }
}
