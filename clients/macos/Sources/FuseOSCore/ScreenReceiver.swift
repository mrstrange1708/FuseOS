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
            case .stop: reset(to: .ended)
            case .start: if state != .idle { state = .requesting }
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
        for nal in Self.nalUnits(in: frame.data) {
            switch nal.first.map({ $0 & 0x1F }) {
            case 7: sps = nal
            case 8: pps = nal
            case .some: picture.append(nal)
            case nil: break
            }
        }
        if frame.config || format == nil {
            if let sps, let pps, let made = Self.format(sps: sps, pps: pps) {
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

    private func reset(to next: State) {
        format = nil
        sps = nil
        pps = nil
        layer.flushAndRemoveImage()
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
