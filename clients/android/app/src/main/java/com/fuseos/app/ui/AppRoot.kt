package com.fuseos.app.ui

import androidx.compose.animation.Crossfade
import androidx.compose.animation.core.tween
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.lifecycle.viewmodel.compose.viewModel
import com.fuseos.app.data.ServiceLocator
import com.fuseos.app.ui.auth.AuthMode
import com.fuseos.app.ui.auth.AuthViewModel
import com.fuseos.app.ui.auth.LoginScreen
import com.fuseos.app.ui.auth.SignUpScreen
import com.fuseos.app.ui.connect.ConnectScreen
import com.fuseos.app.ui.dashboard.DashboardScreen
import com.fuseos.app.ui.device.DeviceTypeScreen

/** Which top-level destination the persisted session resolves to. */
private enum class RootDestination { Auth, DeviceType, Connect, Home }

/** Top-level router: signed out → auth; signed in without a device type → the
 *  device picker; then the connect space until it has been passed once; otherwise home. */
@Composable
fun AppRoot() {
    val repository = ServiceLocator.authRepository
    val token by repository.tokenFlow.collectAsState(initial = null)
    val deviceType by repository.deviceTypeFlow.collectAsState(initial = null)
    // Onboarding runs once. After the first Continue, launches go straight to the
    // dashboard — which shows the same connection status, so nothing is hidden by skipping.
    val connectDone by repository.connectDoneFlow.collectAsState(initial = true)

    val destination = when {
        token == null -> RootDestination.Auth
        deviceType == null -> RootDestination.DeviceType
        !connectDone -> RootDestination.Connect
        else -> RootDestination.Home
    }

    Crossfade(targetState = destination, animationSpec = tween(220), label = "auth-root") { screen ->
        when (screen) {
            RootDestination.Auth -> AuthFlow()
            RootDestination.DeviceType -> DeviceTypeScreen()
            RootDestination.Connect -> ConnectScreen()
            RootDestination.Home -> DashboardScreen()
        }
    }
}

@Composable
private fun AuthFlow() {
    val viewModel: AuthViewModel = viewModel(factory = AuthViewModel.Factory)
    val state by viewModel.state.collectAsState()
    when (state.mode) {
        AuthMode.SignIn -> LoginScreen(viewModel)
        AuthMode.SignUp -> SignUpScreen(viewModel)
    }
}
