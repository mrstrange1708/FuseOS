package com.fuseos.app.screen

import android.media.projection.MediaProjectionManager
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.result.contract.ActivityResultContracts
import com.fuseos.app.data.ServiceLocator
import com.fuseos.proto.ScreenControl

/** Shows Android's "start recording or casting?" dialog and hands the answer on. */
class ScreenConsentActivity : ComponentActivity() {
    private val consent = registerForActivityResult(ActivityResultContracts.StartActivityForResult()) { result ->
        val data = result.data
        if (result.resultCode == RESULT_OK && data != null) {
            ScreenShareService.start(this, result.resultCode, data)
        } else {
            // Refused: tell the Mac, or it waits on "Check your phone" forever.
            ServiceLocator.screenShare.send(ScreenControl.Action.STOP)
        }
        finish()
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (savedInstanceState == null) {
            consent.launch(getSystemService(MediaProjectionManager::class.java).createScreenCaptureIntent())
        }
    }
}
