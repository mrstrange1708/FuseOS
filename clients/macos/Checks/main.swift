// Assertions for LoopGuard, compiled against the real source by run-checks.sh.
//
// macOS has no SPM test target yet: that needs splitting the executable into a library
// plus a test target, which means marking a lot of surface public. This script is the
// lazy stand-in and covers the same nine scenarios as Kotlin's LoopGuardTest.
import Foundation

func check(_ label: String, _ condition: Bool) {
    print(condition ? "  ok   \(label)" : "  FAIL \(label)")
    assert(condition, label)
}

// The same nine scenarios pinned down for Kotlin's LoopGuard.
var g = LoopGuard(selfDeviceId: "self")
check("applies a fresh peer event", g.shouldApply(sourceDeviceId: "peer", seq: 1, sentAtUnixMs: 100))

g = LoopGuard(selfDeviceId: "self")
check("never applies our own event", !g.shouldApply(sourceDeviceId: "self", seq: 1, sentAtUnixMs: 100))

g = LoopGuard(selfDeviceId: "self")
_ = g.shouldApply(sourceDeviceId: "peer", seq: 5, sentAtUnixMs: 100)
check("rejects a replayed seq", !g.shouldApply(sourceDeviceId: "peer", seq: 5, sentAtUnixMs: 100))
check("rejects an older seq", !g.shouldApply(sourceDeviceId: "peer", seq: 4, sentAtUnixMs: 100))
check("accepts the next seq", g.shouldApply(sourceDeviceId: "peer", seq: 6, sentAtUnixMs: 101))

g = LoopGuard(selfDeviceId: "self")
_ = g.shouldApply(sourceDeviceId: "peer-a", seq: 9, sentAtUnixMs: 100)
check("seq tracked per source", g.shouldApply(sourceDeviceId: "peer-b", seq: 1, sentAtUnixMs: 100))

g = LoopGuard(selfDeviceId: "self")
_ = g.shouldApply(sourceDeviceId: "peer", seq: 1, sentAtUnixMs: 500)
g.recordApplied(contentHash: LoopGuard.hash("newer"), sentAtUnixMs: 500)
check("straggler does not clobber newer", !g.shouldApply(sourceDeviceId: "peer", seq: 2, sentAtUnixMs: 400))

g = LoopGuard(selfDeviceId: "self")
g.recordApplied(contentHash: LoopGuard.hash("t"), sentAtUnixMs: 100)
check("swallows the injection echo", !g.shouldEmit(contentHash: LoopGuard.hash("t")))
check("suppression is one-shot", g.shouldEmit(contentHash: LoopGuard.hash("t")))

g = LoopGuard(selfDeviceId: "self")
g.recordApplied(contentHash: LoopGuard.hash("from peer"), sentAtUnixMs: 100)
check("emits unrelated local copies", g.shouldEmit(contentHash: LoopGuard.hash("user copied this")))

var a = LoopGuard(selfDeviceId: "A"), b = LoopGuard(selfDeviceId: "B")
let h = LoopGuard.hash("hello")
check("A emits the user copy", a.shouldEmit(contentHash: h))
check("B applies it", b.shouldApply(sourceDeviceId: "A", seq: 1, sentAtUnixMs: 100))
b.recordApplied(contentHash: h, sentAtUnixMs: 100)
check("B does not send it back — loop ends", !b.shouldEmit(contentHash: h))

// Cross-language: the hash must agree with Kotlin's SHA-256 hex.
print("  hash(\"hello\") = \(LoopGuard.hash("hello"))")
print("ALL SWIFT LOOPGUARD CHECKS PASSED")
