package com.fuseos.app.core

import com.fuseos.proto.ClipText
import com.fuseos.proto.Envelope
import com.fuseos.proto.FileChunk
import com.fuseos.proto.FileMeta
import com.fuseos.proto.PointerInput
import com.fuseos.proto.ScreenControl
import com.google.protobuf.ByteString
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class UsageTest {
    @Test
    fun namesTheFeatureAndNeverTheContent() {
        val clip = Envelope.newBuilder().setClipText(ClipText.newBuilder().setText("my password")).build()
        val feature = Usage.featureOf(clip)!!
        assertEquals("clipboard_text", feature.name)
        assertFalse(feature.toString().contains("my password"))

        val file = Envelope.newBuilder().setFileMeta(FileMeta.newBuilder().setName("taxes.pdf").setSize(2048)).build()
        assertEquals(Usage.Feature("file_transfer", mapOf("sizeBytes" to 2048L)), Usage.featureOf(file))
    }

    @Test
    fun plumbingAndStopsAreNotFeatures() {
        val chunk = Envelope.newBuilder().setFileChunk(FileChunk.newBuilder().setData(ByteString.copyFromUtf8("x"))).build()
        assertNull(Usage.featureOf(chunk))
        val stop = Envelope.newBuilder().setScreenControl(ScreenControl.newBuilder().setAction(ScreenControl.Action.STOP)).build()
        assertNull(Usage.featureOf(stop))
        val start = Envelope.newBuilder().setScreenControl(ScreenControl.newBuilder().setAction(ScreenControl.Action.START)).build()
        assertEquals("screen_mirroring", Usage.featureOf(start)?.name)
    }

    @Test
    fun aTrackpadSessionCountsOncePerWindow() {
        val move = Envelope.newBuilder().setPointerInput(PointerInput.newBuilder().setKind(PointerInput.Kind.MOVE)).build()
        assertEquals("trackpad", Usage.featureOf(move)?.name)
        assertTrue(Usage.shouldCount("trackpad", 1_000_000))
        assertFalse(Usage.shouldCount("trackpad", 1_000_000 + 60_000))
        assertTrue(Usage.shouldCount("trackpad", 1_000_000 + 11 * 60_000))
        assertTrue(Usage.shouldCount("clipboard_text", 1_000_000))
        assertTrue(Usage.shouldCount("clipboard_text", 1_000_001))
    }
}
