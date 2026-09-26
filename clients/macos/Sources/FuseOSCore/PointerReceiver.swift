import Foundation

/// One trackpad or keyboard input from the phone (`PointerInput`), as plain values.
public enum PointerEvent: Equatable {
    case move(dx: Double, dy: Double)
    case click, rightClick, doubleClick
    case scroll(dx: Double, dy: Double)
    case dragStart, dragEnd
    case text(String)
    /// A Mac virtual key code, and modifiers (1 command, 2 shift, 4 option, 8 control).
    case key(code: UInt16, modifiers: UInt32)
}

/// Decodes the phone's `PointerInput` for the app target, which owns the permission and
/// the switch that decide whether any of it is acted on.
@MainActor
public final class PointerReceiver {
    public var onEvent: ((PointerEvent) -> Void)?

    public init(transport: LanTransport) {
        transport.onPointerEnvelope = { [weak self] envelope in self?.receive(envelope) }
    }

    func receive(_ envelope: FuseEnvelope) {
        guard case .pointerInput(let input) = envelope.body, let event = Self.event(from: input) else { return }
        onEvent?(event)
    }

    static func event(from input: FusePointerInput) -> PointerEvent? {
        switch input.kind {
        case .move: return .move(dx: Double(input.dx), dy: Double(input.dy))
        case .click: return .click
        case .rightClick: return .rightClick
        case .doubleClick: return .doubleClick
        case .scroll: return .scroll(dx: Double(input.dx), dy: Double(input.dy))
        case .dragStart: return .dragStart
        case .dragEnd: return .dragEnd
        case .text: return input.text.isEmpty ? nil : .text(input.text)
        case .key: return .key(code: UInt16(clamping: input.keyCode), modifiers: input.modifiers)
        default: return nil
        }
    }
}
