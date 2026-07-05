package com.fuseos.app.ui.auth

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import com.fuseos.app.data.AuthRepository
import com.fuseos.app.data.ServiceLocator
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

enum class AuthMode { SignIn, SignUp }

data class AuthUiState(
    val mode: AuthMode = AuthMode.SignIn,
    val email: String = "",
    val password: String = "",
    val name: String = "",
    val isSubmitting: Boolean = false,
    val error: String? = null,
    val emailError: String? = null,
    val passwordError: String? = null,
)

class AuthViewModel(private val repository: AuthRepository) : ViewModel() {

    private val _state = MutableStateFlow(AuthUiState())
    val state = _state.asStateFlow()

    fun onEmailChange(value: String) =
        _state.update { it.copy(email = value, emailError = null, error = null) }

    fun onPasswordChange(value: String) =
        _state.update { it.copy(password = value, passwordError = null, error = null) }

    fun onNameChange(value: String) =
        _state.update { it.copy(name = value, error = null) }

    fun switchTo(mode: AuthMode) =
        _state.update {
            it.copy(mode = mode, error = null, emailError = null, passwordError = null)
        }

    fun submit() {
        val current = _state.value
        val emailError = if (!EMAIL_REGEX.matches(current.email.trim())) {
            "Enter a valid email address"
        } else {
            null
        }
        val passwordError = if (current.password.length < 8) {
            "Use at least 8 characters"
        } else {
            null
        }
        if (emailError != null || passwordError != null) {
            _state.update { it.copy(emailError = emailError, passwordError = passwordError) }
            return
        }

        _state.update {
            it.copy(isSubmitting = true, error = null, emailError = null, passwordError = null)
        }
        viewModelScope.launch {
            try {
                if (current.mode == AuthMode.SignIn) {
                    repository.signIn(current.email.trim(), current.password)
                } else {
                    repository.signUp(current.email.trim(), current.password, current.name.trim())
                }
                // On success the session flow updates and AppRoot swaps to Home.
            } catch (e: Exception) {
                _state.update { it.copy(error = e.message ?: "Unable to continue. Try again.") }
            } finally {
                _state.update { it.copy(isSubmitting = false) }
            }
        }
    }

    companion object {
        private val EMAIL_REGEX =
            Regex("^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$")

        val Factory = viewModelFactory {
            initializer { AuthViewModel(ServiceLocator.authRepository) }
        }
    }
}
