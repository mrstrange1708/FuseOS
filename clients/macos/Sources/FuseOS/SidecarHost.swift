import AppKit
import ApplicationServices
import CoreMedia
import FuseOSCore
import ScreenCaptureKit
import VideoToolbox
import VirtualDisplay

/// Sidecar: the phone as a second display for this Mac.
///
/// The phone asks for a display of its own shape; this adds one (a CoreGraphics virtual
/// display, HiDPI so it is sharp), captures it with ScreenCaptureKit, encodes it to H.264
/// in hardware with VideoToolbox — realtime, no B-frames, SPS/PPS ahead of every keyframe
/// so the phone can join at any of them — and streams it over the LAN channel. Touches on
/// the phone come back as clicks and drags on that display.
///
/// macOS asks for Screen Recording the first time (capture fails without it, and the phone
/// is told), and touches need Accessibility, like the phone-as-trackpad does.
final class SidecarHost: NSObject, SCStreamOutput, SCStreamDelegate {
    private let link: SidecarLink
    private let onChange: (Bool) -> Void
    private var display: CGVirtualDisplay?
    private var stream: SCStream?
    private var session: VTCompressionSession?
    private var encodedSize = (width: 0, height: 0)
    private let captureQueue = DispatchQueue(label: "fuse.sidecar.capture", qos: .userInteractive)
    private let keyframeLock = NSLock()
    private var wantsKeyframe = false
    private let source = CGEventSource(stateID: .hidSystemState)

    @MainActor
    init(link: SidecarLink, onChange: @escaping (Bool) -> Void) {
        self.link = link
        self.onChange = onChange
        super.init()
        link.onStart = { [weak self] width, height, dpi in
            Task { @MainActor in await self?.start(width: width, height: height, dpi: dpi) }
        }
        link.onStop = { [weak self] in self?.stop(notifyPhone: false) }
        link.onKeyframeRequest = { [weak self] in self?.requestKeyframe() }
        link.onTouch = { [weak self] touch in self?.handle(touch) }
    }

    // MARK: - Lifecycle

    @MainActor
    private func start(width: Int, height: Int, dpi: Int) async {
        stop(notifyPhone: false)
        // Even pixel sizes, capped: a 4K phone does not need a 4K stream over Wi-Fi.
        let scale = min(1, 2400 / Double(max(width, height)))
        let w = Int(Double(width) * scale) / 2 * 2, h = Int(Double(height) * scale) / 2 * 2

        let descriptor = CGVirtualDisplayDescriptor()
        descriptor.queue = DispatchQueue.main
        descriptor.name = "FuseOS Sidecar"
        descriptor.maxPixelsWide = UInt32(w)
        descriptor.maxPixelsHigh = UInt32(h)
        let mmPerPixel = 25.4 / Double(dpi) / scale
        descriptor.sizeInMillimeters = CGSize(width: Double(w) * mmPerPixel, height: Double(h) * mmPerPixel)
        descriptor.productID = 0x1F05
        descriptor.vendorID = 0xF05E
        descriptor.serialNum = 1
        guard let display = CGVirtualDisplay(descriptor: descriptor) else { return link.stopped() }
        // HiDPI: the mode is in points, drawn at twice that in pixels — sharp on the phone.
        let settings = CGVirtualDisplaySettings()
        settings.hiDPI = 1
        settings.modes = [CGVirtualDisplayMode(width: UInt32(w / 2), height: UInt32(h / 2), refreshRate: 60)]
        guard display.apply(settings) else { return link.stopped() }
        self.display = display

        do {
            let captured = try await sharedDisplay(id: display.displayID)
            let config = SCStreamConfiguration()
            config.width = w
            config.height = h
            config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
            config.pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
            config.queueDepth = 4
            config.showsCursor = true
            let stream = SCStream(filter: SCContentFilter(display: captured, excludingWindows: []), configuration: config, delegate: self)
            try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: captureQueue)
            guard makeEncoder(width: w, height: h) else { throw CocoaError(.featureUnsupported) }
            try await stream.startCapture()
            self.stream = stream
            link.started()
            onChange(true)
        } catch {
            // Most often: Screen Recording not granted. The phone is told, not left waiting.
            stop(notifyPhone: true)
        }
    }

    @MainActor
    func stop(notifyPhone: Bool) {
        let wasActive = display != nil
        stream?.stopCapture { _ in }
        stream = nil
        if let session { VTCompressionSessionInvalidate(session) }
        session = nil
        display = nil // releasing the virtual display removes it
        if notifyPhone { link.stopped() }
        if wasActive { onChange(false) }
    }

    /// A new virtual display takes a moment to be listed by ScreenCaptureKit.
    private func sharedDisplay(id: CGDirectDisplayID) async throws -> SCDisplay {
        for _ in 0..<15 {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            if let match = content.displays.first(where: { $0.displayID == id }) { return match }
            try await Task.sleep(nanoseconds: 200_000_000)
        }
        throw CocoaError(.fileNoSuchFile)
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        Task { @MainActor in self.stop(notifyPhone: true) }
    }

    // MARK: - Encoding

    private func makeEncoder(width: Int, height: Int) -> Bool {
        var made: VTCompressionSession?
        VTCompressionSessionCreate(
            allocator: nil, width: Int32(width), height: Int32(height), codecType: kCMVideoCodecType_H264,
            encoderSpecification: nil, imageBufferAttributes: nil, compressedDataAllocator: nil,
            outputCallback: nil, refcon: nil, compressionSessionOut: &made,
        )
        guard let made else { return false }
        VTSessionSetProperty(made, key: kVTCompressionPropertyKey_RealTime, value: kCFBooleanTrue)
        VTSessionSetProperty(made, key: kVTCompressionPropertyKey_ProfileLevel, value: kVTProfileLevel_H264_Main_AutoLevel)
        VTSessionSetProperty(made, key: kVTCompressionPropertyKey_AllowFrameReordering, value: kCFBooleanFalse)
        VTSessionSetProperty(made, key: kVTCompressionPropertyKey_AverageBitRate, value: 8_000_000 as CFNumber)
        VTSessionSetProperty(made, key: kVTCompressionPropertyKey_MaxKeyFrameInterval, value: 60 as CFNumber)
        VTSessionSetProperty(made, key: kVTCompressionPropertyKey_ExpectedFrameRate, value: 30 as CFNumber)
        VTCompressionSessionPrepareToEncodeFrames(made)
        session = made
        encodedSize = (width, height)
        return true
    }

    @MainActor
    private func requestKeyframe() {
        keyframeLock.lock()
        wantsKeyframe = true
        keyframeLock.unlock()
    }

    /// ScreenCaptureKit hands over a frame only when the display changed; a still display
    /// sends nothing, and the phone keeps showing the last frame.
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid, let session, let pixels = sampleBuffer.imageBuffer,
              let info = (CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]])?.first,
              let raw = info[.status] as? Int, SCFrameStatus(rawValue: raw) == .complete else { return }
        keyframeLock.lock()
        let force = wantsKeyframe
        wantsKeyframe = false
        keyframeLock.unlock()
        let options = force ? [kVTEncodeFrameOptionKey_ForceKeyFrame: kCFBooleanTrue] as CFDictionary : nil
        VTCompressionSessionEncodeFrame(
            session, imageBuffer: pixels, presentationTimeStamp: sampleBuffer.presentationTimeStamp,
            duration: .invalid, frameProperties: options, infoFlagsOut: nil,
        ) { [weak self] status, _, encoded in
            guard status == noErr, let encoded, let self else { return }
            self.emit(encoded)
        }
    }

    /// AVCC (length-prefixed) out of VideoToolbox → Annex-B (start codes) for MediaCodec,
    /// with SPS and PPS ahead of every keyframe.
    private func emit(_ sample: CMSampleBuffer) {
        let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: false) as? [[CFString: Any]]
        let keyframe = !((attachments?.first?[kCMSampleAttachmentKey_NotSync] as? Bool) ?? false)
        var out = Data()
        let startCode: [UInt8] = [0, 0, 0, 1]
        if keyframe, let format = sample.formatDescription {
            for index in 0..<2 {
                var pointer: UnsafePointer<UInt8>?
                var size = 0
                CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
                    format, parameterSetIndex: index, parameterSetPointerOut: &pointer,
                    parameterSetSizeOut: &size, parameterSetCountOut: nil, nalUnitHeaderLengthOut: nil,
                )
                if let pointer {
                    out.append(contentsOf: startCode)
                    out.append(pointer, count: size)
                }
            }
        }
        guard let block = sample.dataBuffer else { return }
        let length = CMBlockBufferGetDataLength(block)
        var avcc = Data(count: length)
        let copied = avcc.withUnsafeMutableBytes {
            CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: $0.baseAddress!)
        }
        guard copied == kCMBlockBufferNoErr else { return }
        var offset = 0
        while offset + 4 <= avcc.count {
            let nalLength = avcc[offset..<offset + 4].reduce(0) { $0 << 8 | Int($1) }
            let start = offset + 4
            guard nalLength > 0, start + nalLength <= avcc.count else { break }
            out.append(contentsOf: startCode)
            out.append(avcc[start..<start + nalLength])
            offset = start + nalLength
        }
        let pts = Int64(CMTimeGetSeconds(sample.presentationTimeStamp) * 1_000_000)
        let size = encodedSize
        DispatchQueue.main.async { [link] in
            MainActor.assumeIsolated {
                link.send(frame: out, keyframe: keyframe, config: false, width: size.width, height: size.height, ptsUs: pts)
            }
        }
    }

    // MARK: - Touch

    @MainActor
    private func handle(_ touch: SidecarTouch) {
        guard let display, AXIsProcessTrusted() else { return }
        let bounds = CGDisplayBounds(display.displayID)
        func at(_ x: Double, _ y: Double) -> CGPoint {
            CGPoint(x: bounds.minX + x * bounds.width, y: bounds.minY + y * bounds.height)
        }
        switch touch {
        case let .tap(x, y):
            post(.leftMouseDown, at(x, y), .left)
            post(.leftMouseUp, at(x, y), .left)
        case let .down(x, y): post(.leftMouseDown, at(x, y), .left)
        case let .move(x, y): post(.leftMouseDragged, at(x, y), .left)
        case let .up(x, y): post(.leftMouseUp, at(x, y), .left)
        case let .rightClick(x, y):
            post(.rightMouseDown, at(x, y), .right)
            post(.rightMouseUp, at(x, y), .right)
        case let .scroll(x, y, dx, dy):
            post(.mouseMoved, at(x, y), .left)
            CGEvent(scrollWheelEvent2Source: source, units: .pixel, wheelCount: 2,
                    wheel1: Int32(dy.rounded()), wheel2: Int32(dx.rounded()), wheel3: 0)?
                .post(tap: .cghidEventTap)
        }
    }

    private func post(_ type: CGEventType, _ point: CGPoint, _ button: CGMouseButton) {
        CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: button)?
            .post(tap: .cghidEventTap)
    }
}
