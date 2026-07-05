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
import com.fuseos.app.ui.home.HomeScreen

/** Top-level router: the persisted session decides auth vs. home. */
@Composable
fun AppRoot() {
    val repository = ServiceLocator.authRepository
    val token by repository.tokenFlow.collectAsState(initial = null)

    Crossfade(targetState = token != null, animationSpec = tween(220), label = "auth-root") { signedIn ->
        if (signedIn) {
            HomeScreen()
        } else {
            AuthFlow()
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
