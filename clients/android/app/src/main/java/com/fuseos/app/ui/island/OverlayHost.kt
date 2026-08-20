package com.fuseos.app.ui.island

import android.content.Context
import android.view.View
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.LifecycleRegistry
import androidx.lifecycle.ViewModelStore
import androidx.lifecycle.ViewModelStoreOwner
import androidx.lifecycle.setViewTreeLifecycleOwner
import androidx.lifecycle.setViewTreeViewModelStoreOwner
import androidx.savedstate.SavedStateRegistry
import androidx.savedstate.SavedStateRegistryController
import androidx.savedstate.SavedStateRegistryOwner
import androidx.savedstate.setViewTreeSavedStateRegistryOwner

/**
 * The owners a `ComposeView` needs when it lives in a raw `WindowManager` window.
 *
 * Compose gets its lifecycle, its `ViewModelStore` and its saved-state registry from the
 * view tree, which normally comes from an Activity. An overlay has no Activity, so this
 * supplies a minimal set: created and resumed for as long as the window is up, destroyed
 * when it comes down. Skipping it does not fail loudly — the composition simply never
 * recomposes, and the island would freeze on its first frame.
 */
internal class OverlayHost(context: Context) : LifecycleOwner, ViewModelStoreOwner, SavedStateRegistryOwner {

    private val registry = LifecycleRegistry(this)
    private val savedState = SavedStateRegistryController.create(this)

    override val lifecycle: Lifecycle get() = registry
    override val viewModelStore = ViewModelStore()
    override val savedStateRegistry: SavedStateRegistry get() = savedState.savedStateRegistry

    lateinit var view: View
        private set

    fun attach(view: View) {
        this.view = view
        savedState.performRestore(null)
        view.setViewTreeLifecycleOwner(this)
        view.setViewTreeViewModelStoreOwner(this)
        view.setViewTreeSavedStateRegistryOwner(this)
        registry.currentState = Lifecycle.State.RESUMED
    }

    fun detach() {
        registry.currentState = Lifecycle.State.DESTROYED
        viewModelStore.clear()
    }
}
