package com.fuseos.app.ime

import android.inputmethodservice.InputMethodService
import android.view.KeyEvent
import android.view.View
import androidx.compose.ui.platform.ComposeView
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import com.fuseos.app.data.ServiceLocator
import com.fuseos.app.ui.island.OverlayHost
import com.fuseos.app.ui.theme.FuseOSTheme

/**
 * The FuseOS keyboard — and the reason clipboard sync can be automatic at all.
 *
 * Android refuses a clipboard read to any app that is not the focused window, with one
 * exemption that matters: the **default input method**. The check is on the package, not
 * on whether the keyboard happens to be showing, so once FuseOS is the selected keyboard
 * the whole process may read the clipboard — including the listener held open by
 * `FuseConnectionService`. Copying in WhatsApp then reaches FuseOS with no tile, no
 * notification and no tap, which is the behaviour the Quick Settings tile only
 * approximates. See `docs/protocol.md` §5.1.
 *
 * That is the entire purpose of this class. It has to be a keyboard someone is willing to
 * type on, so it is a real one, but it is deliberately a plain one: letters, digits, a
 * symbol layer and the keys people actually press. No autocorrect, no suggestions, no
 * gesture typing, no per-key haptics — none of that is what FuseOS is for, and each would
 * be a feature to maintain forever in service of a permission workaround.
 *
 * It never sees clipboard *content* differently from the rest of the app: keystrokes go
 * straight to the `InputConnection` and are neither stored nor sent anywhere.
 */
class FuseKeyboardService : InputMethodService() {

    private var host: OverlayHost? = null

    override fun onCreateInputView(): View {
        // An IME has no Activity, so Compose gets its lifecycle from the same minimal
        // owner the island uses.
        host?.detach()
        val host = OverlayHost(this)
        this.host = host

        val view = ComposeView(this).apply {
            setContent {
                FuseOSTheme {
                    val clips by ServiceLocator.clipboardSync.history.collectAsState()
                    FuseKeyboard(
                        onKey = ::commit,
                        onBackspace = ::backspace,
                        onEnter = ::enter,
                        clips = clips,
                        // The keyboard is the one place that may read the clipboard at any
                        // time, so "send what I copied" works from inside any app.
                        onSendClipboard = { ServiceLocator.clipboardSync.sendCurrent() },
                    )
                }
            }
        }
        // The IME window's root, not only the view: see OverlayHost.attach.
        host.attach(view, window?.window?.decorView)
        return view
    }

    override fun onDestroy() {
        host?.detach()
        host = null
        super.onDestroy()
    }

    private fun commit(text: String) {
        currentInputConnection?.commitText(text, 1)
    }

    private fun backspace() {
        val connection = currentInputConnection ?: return
        // Selection first: deleting "around" a selection would delete the wrong thing,
        // leaving the highlighted text in place and eating the character before it.
        val selected = connection.getSelectedText(0)
        if (!selected.isNullOrEmpty()) {
            connection.commitText("", 1)
            return
        }
        connection.deleteSurroundingText(1, 0)
    }

    /**
     * Enter means "send" in a chat and "newline" in a note, and only the field knows
     * which. Handing the action back to the editor lets it decide; a raw newline is the
     * fallback for fields that declare no action.
     */
    private fun enter() {
        val connection = currentInputConnection ?: return
        val action = currentInputEditorInfo?.imeOptions?.and(android.view.inputmethod.EditorInfo.IME_MASK_ACTION)
        if (action != null && action != android.view.inputmethod.EditorInfo.IME_ACTION_NONE &&
            action != android.view.inputmethod.EditorInfo.IME_ACTION_UNSPECIFIED
        ) {
            connection.performEditorAction(action)
            return
        }
        connection.sendKeyEvent(KeyEvent(KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_ENTER))
        connection.sendKeyEvent(KeyEvent(KeyEvent.ACTION_UP, KeyEvent.KEYCODE_ENTER))
    }
}
