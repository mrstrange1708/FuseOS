import Foundation

/// A touch on the Sidecar display, 0–1 of that display, top-left origin.
public enum SidecarTouch: Equatable {
    case tap(x: Double, y: Double)
    case down(x: Double, y: Double)
    case move(x: Double, y: Double)
    case up(x: Double, y: Double)
    case scroll(x: Double, y: Double, dx: Double, dy: Double)
    case rightClick(x: Double, y: Double)
}

/// The wire side of Sidecar (the phone as a second display): control and touches in,
/// frames and control out. The app target owns the display, capture and encoder.
@MainActor
public final class SidecarLink {
    /// The phone asked for a display of this many pixels (landscape) at this density.
    public var onStart: ((_ width: Int, _ height: Int, _ dpi: Int) -> Void)?
    public var onStop: (() -> Void)?
    public var onKeyframeRequest: (() -> Void)?
    public var onTouch: ((SidecarTouch) -> Void)?

    private let transport: LanTransport

    public init(transport: LanTransport) {
        self.transport = transport
        transport.onSidecarEnvelope = { [weak self] envelope in self?.receive(envelope) }
    }

    public func started() { control(.start) }
    public func stopped() { control(.stop) }

    /// One encoded H.264 access unit, Annex-B, for the phone to decode.
    public func send(frame: Data, keyframe: Bool, config: Bool, width: Int, height: Int, ptsUs: Int64) {
        var envelope = transport.newEnvelope()
        envelope.sidecarFrame = FuseScreenFrame.with {
            $0.data = frame
            $0.keyframe = keyframe
            $0.config = config
            $0.width = UInt32(width)
            $0.height = UInt32(height)
            $0.ptsUs = ptsUs
        }
        transport.broadcast(envelope)
    }

    private func control(_ action: FuseSidecarControl.Action) {
        var envelope = transport.newEnvelope()
        envelope.sidecarControl = FuseSidecarControl.with { $0.action = action }
        transport.broadcast(envelope)
    }

    func receive(_ envelope: FuseEnvelope) {
        switch envelope.body {
        case .sidecarControl(let c):
            switch c.action {
            case .start where c.width > 0 && c.height > 0:
                onStart?(Int(c.width), Int(c.height), Int(max(c.dpi, 1)))
            case .stop: onStop?()
            case .keyframe: onKeyframeRequest?()
            default: break
            }
        case .sidecarInput(let i):
            if let touch = Self.touch(from: i) { onTouch?(touch) }
        default:
            break
        }
    }

    static func touch(from input: FuseSidecarInput) -> SidecarTouch? {
        let x = Double(min(max(input.x, 0), 1)), y = Double(min(max(input.y, 0), 1))
        switch input.kind {
        case .tap: return .tap(x: x, y: y)
        case .down: return .down(x: x, y: y)
        case .move: return .move(x: x, y: y)
        case .up: return .up(x: x, y: y)
        case .scroll: return .scroll(x: x, y: y, dx: Double(input.dx), dy: Double(input.dy))
        case .rightClick: return .rightClick(x: x, y: y)
        default: return nil
        }
    }
}
