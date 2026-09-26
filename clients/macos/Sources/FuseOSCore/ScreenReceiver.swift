import AVFoundation
import CoreMedia
import Foundation

/// The Mac end of screen mirroring: asks the phone to start, and plays the H.264 it sends.
///
/// No decoder session of our own: `AVSampleBufferDisplayLayer` takes compressed samples
/// and decodes them in hardware. The work here is only reframing — Android emits Annex-B
/// (start codes), Core Media wants AVCC (length prefixes) plus a format description built
/// from the stream's SPS and PPS.
@MainActor
public final class ScreenReceiver {
    public enum State: Equatable {
        case idle
        /// Asked; the phone is showing its user the consent prompt.
        case requesting
        case streaming(width: Int, height: Int)
        /// The phone stopped (its user ended it, or refused).
        case ended
    }

    public private(set) var state: State = .idle {
        didSet { if state != oldValue { onStateChanged?(state) } }
    }
    public var onStateChanged: ((State) -> Void)?

    /// Whether the phone will act on input (its remote-control service is on). It says so
    /// with its START; until then, and for a view-only phone, clicks do nothing.
    public private(set) var canControl = false {
        didSet { if canControl != oldValue { onCanControlChanged?(canControl) } }
    }
    public var onCanControlChanged: ((Bool) -> Void)?

    /// Put this in a view. Frames are enqueued with "display immediately": mirroring wants
    /// the newest frame now, not a smooth schedule.
    public let layer = AVSampleBufferDisplayLayer()

    private let transport: LanTransport
    private var format: CMVideoFormatDescription?
    private var sps: Data?
    private var pps: Data?

    public init(transport: LanTransport) {
        self.transport = transport
        layer.videoGravity = .resizeAspect
        transport.onScreenEnvelope = { [weak self] envelope in self?.receive(envelope) }
    }

    public func start() {
        state = .requesting
        send(.start)
    }

    public func stop() {
        send(.stop)
        reset(to: .idle)
    }

    func receive(_ envelope: FuseEnvelope) {
        switch envelope.body {
        case .screenControl(let control):
            switch control.action {
            // The phone echoes our own stop; only a stop we did not ask for is news.
            case .stop: if state != .idle { reset(to: .ended) }
            // The phone is about to stream — whether we asked or its user started it there.
            case .start:
                canControl = control.remoteControl
                if case .streaming = state {} else { state = .requesting }
            default: break
            }
        case .screenFrame(let frame):
            // A phone that is still streaming after we stopped (or before we asked): ignore.
            guard state != .idle, state != .ended else { return }
            enqueue(frame)
        default:
            break
        }
    }

    private func enqueue(_ frame: FuseScreenFrame) {
        var picture: [Data] = []
        var carriesParameterSets = false
        for nal in Self.nalUnits(in: frame.data) {
            switch nal.first.map({ $0 & 0x1F }) {
            case 7: sps = nal; carriesParameterSets = true
            case 8: pps = nal; carriesParameterSets = true
            case .some: picture.append(nal)
            case nil: break
            }
        }
        if carriesParameterSets || format == nil {
            if let sps, let pps, let made = Self.format(sps: sps, pps: pps) {
                // A new shape (the phone rotated): samples of the old one must not linger.
                if let format, !CMFormatDescriptionEqual(format, otherFormatDescription: made) {
                    layer.flush()
                }
                format = made
                let size = CMVideoFormatDescriptionGetDimensions(made)
                state = .streaming(width: Int(size.width), height: Int(size.height))
            }
        }
        guard let format, !picture.isEmpty else { return }

        if layer.status == .failed {
            // A decode error poisons the layer until flushed; the next keyframe recovers.
            layer.flush()
            send(.keyframe)
            return
        }
        guard let sample = Self.sample(avcc: Self.avcc(picture), format: format) else { return }
        layer.enqueue(sample)
    }

    // MARK: - Remote control

    /// Positions are 0–1 of the mirrored image, top-left origin.
    public enum Input {
        case tap(x: Double, y: Double)
        case longPress(x: Double, y: Double)
        case swipe(fromX: Double, fromY: Double, toX: Double, toY: Double, durationMs: Int)
        case back, home, recents
        case text(String)
        case delete, enter
    }

    /// Sends one input to the phone. Ignored unless mirroring and the phone accepts control.
    public func send(_ input: Input) {
        guard canControl, case .streaming = state else { return }
        var message = FuseRemoteInput()
        switch input {
        case let .tap(x, y):
            message.kind = .tap; message.x = Float(x); message.y = Float(y)
        case let .longPress(x, y):
            message.kind = .longPress; message.x = Float(x); message.y = Float(y)
        case let .swipe(x1, y1, x2, y2, ms):
            message.kind = .swipe
            message.x = Float(x1); message.y = Float(y1); message.x2 = Float(x2); message.y2 = Float(y2)
            message.durationMs = UInt32(max(0, ms))
        case .back: message.kind = .back
        case .home: message.kind = .home
        case .recents: message.kind = .recents
        case let .text(text): message.kind = .text; message.text = text
        case .delete: message.kind = .key; message.keyCode = 67
        case .enter: message.kind = .key; message.keyCode = 66
        }
        var envelope = transport.newEnvelope()
        envelope.remoteInput = message
        transport.broadcast(envelope)
    }

    private func reset(to next: State) {
        format = nil
        sps = nil
        pps = nil
        layer.flushAndRemoveImage()
        canControl = false
        state = next
    }

    private func send(_ action: FuseScreenControl.Action) {
        var envelope = transport.newEnvelope()
        envelope.screenControl = FuseScreenControl.with { $0.action = action }
        transport.broadcast(envelope)
    }

    // MARK: - H.264 reframing

    /// Splits an Annex-B buffer on 3- and 4-byte start codes.
    static func nalUnits(in data: Data) -> [Data] {
        let bytes = [UInt8](data)
        var starts: [(at: Int, codeLength: Int)] = []
        var i = 0
        while i + 2 < bytes.count {
            if bytes[i] == 0, bytes[i + 1] == 0, bytes[i + 2] == 1 {
                let four = i > 0 && bytes[i - 1] == 0
                starts.append((four ? i - 1 : i, four ? 4 : 3))
                i += 3
            } else {
                i += 1
            }
        }
        return starts.enumerated().compactMap { index, start in
            let from = start.at + start.codeLength
            let to = index + 1 < starts.count ? starts[index + 1].at : bytes.count
            return from < to ? Data(bytes[from..<to]) : nil
        }
    }

    /// Length-prefixed (4-byte big-endian) NAL units, as Core Media expects.
    static func avcc(_ nals: [Data]) -> Data {
        var out = Data()
        for nal in nals {
            var length = UInt32(nal.count).bigEndian
            out.append(Data(bytes: &length, count: 4))
            out.append(nal)
        }
        return out
    }

    private static func format(sps: Data, pps: Data) -> CMVideoFormatDescription? {
        var format: CMVideoFormatDescription?
        let status = sps.withUnsafeBytes { spsBuf in
            pps.withUnsafeBytes { ppsBuf in
                let pointers = [
                    spsBuf.bindMemory(to: UInt8.self).baseAddress!,
                    ppsBuf.bindMemory(to: UInt8.self).baseAddress!,
                ]
                return CMVideoFormatDescriptionCreateFromH264ParameterSets(
                    allocator: kCFAllocatorDefault,
                    parameterSetCount: 2,
                    parameterSetPointers: pointers,
                    parameterSetSizes: [sps.count, pps.count],
                    nalUnitHeaderLength: 4,
                    formatDescriptionOut: &format,
                )
            }
        }
        return status == noErr ? format : nil
    }

    private static func sample(avcc: Data, format: CMVideoFormatDescription) -> CMSampleBuffer? {
        var block: CMBlockBuffer?
        guard CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: avcc.count,
            blockAllocator: kCFAllocatorDefault, customBlockSource: nil, offsetToData: 0,
            dataLength: avcc.count, flags: 0, blockBufferOut: &block,
        ) == kCMBlockBufferNoErr, let block else { return nil }
        let copied = avcc.withUnsafeBytes {
            CMBlockBufferReplaceDataBytes(
                with: $0.baseAddress!, blockBuffer: block, offsetIntoDestination: 0, dataLength: avcc.count,
            )
        }
        guard copied == kCMBlockBufferNoErr else { return nil }

        var sample: CMSampleBuffer?
        var size = avcc.count
        guard CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault, dataBuffer: block, formatDescription: format,
            sampleCount: 1, sampleTimingEntryCount: 0, sampleTimingArray: nil,
            sampleSizeEntryCount: 1, sampleSizeArray: &size, sampleBufferOut: &sample,
        ) == noErr, let sample else { return nil }

        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true),
           CFArrayGetCount(attachments) > 0 {
            let dict = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
            CFDictionarySetValue(
                dict,
                Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                Unmanaged.passUnretained(kCFBooleanTrue).toOpaque(),
            )
        }
        return sample
    }
}
