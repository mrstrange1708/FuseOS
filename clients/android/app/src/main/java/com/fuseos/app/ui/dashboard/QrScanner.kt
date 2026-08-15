package com.fuseos.app.ui.dashboard

import android.Manifest
import android.content.pm.PackageManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.annotation.OptIn
import androidx.camera.core.CameraSelector
import androidx.camera.core.ExperimentalGetImage
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageProxy
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.content.ContextCompat
import com.fuseos.app.core.PairingCode
import com.fuseos.app.ui.components.FusePrimaryButton
import com.google.mlkit.vision.barcode.BarcodeScannerOptions
import com.google.mlkit.vision.barcode.BarcodeScanning
import com.google.mlkit.vision.barcode.common.Barcode
import com.google.mlkit.vision.common.InputImage

/**
 * Camera preview that reports the first valid FuseOS pairing code it sees.
 *
 * [onCode] fires at most once — the analyzer keeps running until the camera unbinds, so
 * without the latch a single QR would claim the same code several times.
 */
@Composable
fun QrScanner(modifier: Modifier = Modifier, onCode: (String) -> Unit) {
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current
    var granted by remember {
        mutableStateOf(
            ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA) ==
                PackageManager.PERMISSION_GRANTED,
        )
    }
    var denied by remember { mutableStateOf(false) }
    val request = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) {
        granted = it
        denied = !it
    }
    LaunchedEffect(Unit) { if (!granted) request.launch(Manifest.permission.CAMERA) }

    if (!granted) {
        Column(modifier = modifier.fillMaxWidth()) {
            Text(
                if (denied) {
                    "FuseOS needs the camera to scan the code. You can allow it, or switch " +
                        "to “Enter code” and type it instead."
                } else {
                    "Waiting for camera permission…"
                },
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            if (denied) {
                Spacer(Modifier.height(16.dp))
                FusePrimaryButton(
                    text = "Allow camera",
                    onClick = { request.launch(Manifest.permission.CAMERA) },
                )
            }
        }
        return
    }

    // One latch and one scanner instance for the lifetime of this composable.
    val handled = remember { java.util.concurrent.atomic.AtomicBoolean(false) }
    val scanner = remember {
        BarcodeScanning.getClient(
            BarcodeScannerOptions.Builder()
                .setBarcodeFormats(Barcode.FORMAT_QR_CODE)
                .build(),
        )
    }
    val providerFuture = remember { ProcessCameraProvider.getInstance(context) }
    DisposableEffect(Unit) {
        onDispose {
            runCatching { providerFuture.get().unbindAll() }
            scanner.close()
        }
    }

    Box(
        modifier = modifier
            .fillMaxWidth()
            .height(300.dp)
            .clip(RoundedCornerShape(14.dp))
            .background(MaterialTheme.colorScheme.surface),
        contentAlignment = Alignment.Center,
    ) {
        AndroidView(
            modifier = Modifier.fillMaxWidth(),
            factory = { ctx ->
                val previewView = PreviewView(ctx)
                val executor = ContextCompat.getMainExecutor(ctx)
                providerFuture.addListener({
                    val provider = providerFuture.get()
                    val preview = Preview.Builder().build().also {
                        it.setSurfaceProvider(previewView.surfaceProvider)
                    }
                    val analysis = ImageAnalysis.Builder()
                        .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                        .build()
                    analysis.setAnalyzer(executor) { proxy ->
                        scan(scanner, proxy) { payload ->
                            val code = PairingCode.fromScan(payload)
                            if (code != null && handled.compareAndSet(false, true)) onCode(code)
                        }
                    }
                    provider.unbindAll()
                    provider.bindToLifecycle(
                        lifecycleOwner,
                        CameraSelector.DEFAULT_BACK_CAMERA,
                        preview,
                        analysis,
                    )
                }, executor)
                previewView
            },
        )
        Text(
            "Point at the QR code on your Mac",
            style = MaterialTheme.typography.labelSmall,
            textAlign = TextAlign.Center,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.align(Alignment.BottomCenter),
        )
    }
}

@OptIn(ExperimentalGetImage::class)
private fun scan(
    scanner: com.google.mlkit.vision.barcode.BarcodeScanner,
    proxy: ImageProxy,
    onPayload: (String) -> Unit,
) {
    val image = proxy.image
    if (image == null) {
        proxy.close()
        return
    }
    scanner.process(InputImage.fromMediaImage(image, proxy.imageInfo.rotationDegrees))
        .addOnSuccessListener { barcodes ->
            barcodes.firstNotNullOfOrNull { it.rawValue }?.let(onPayload)
        }
        // Every frame must be closed or the analyzer stalls, success or not.
        .addOnCompleteListener { proxy.close() }
}
