package com.fuseos.app.actions

import android.content.Intent
import android.os.Bundle
import android.widget.Toast
import androidx.activity.ComponentActivity
import com.fuseos.app.data.ServiceLocator

/**
 * "Open on Mac" in the Share sheet: Handoff for links. Share a page from any browser or
 * app, and it opens in the Mac's browser.
 */
class OpenOnMacActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val link = intent?.getStringExtra(Intent.EXTRA_TEXT)?.let(PhoneActions::firstLink)
        val message = when {
            link == null -> "There's no link to open"
            ServiceLocator.phoneActions.sendLink(link) -> "Opening on your Mac"
            else -> "No Mac connected. Open FuseOS on your Mac."
        }
        Toast.makeText(this, message, Toast.LENGTH_SHORT).show()
        finish()
    }
}
