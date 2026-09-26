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

    /**
     * [root] is the window's own root when the view is added to someone else's window —
     * an input method's. Compose looks up its lifecycle from the *root* view, not the
     * ComposeView, so owners on the view alone crash the keyboard the moment it opens.
     */
    fun attach(view: View, root: View? = null) {
        this.view = view
        savedState.performRestore(null)
        for (target in listOfNotNull(view, root)) {
            target.setViewTreeLifecycleOwner(this)
            target.setViewTreeViewModelStoreOwner(this)
            target.setViewTreeSavedStateRegistryOwner(this)
        }
        registry.currentState = Lifecycle.State.RESUMED
    }

    fun detach() {
        registry.currentState = Lifecycle.State.DESTROYED
        viewModelStore.clear()
    }
}
