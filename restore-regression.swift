import Foundation
final class DebugLog { static let shared = DebugLog(); func write(_ s: String) {} }
final class FakeBrightness {
 var current: Float? = 0.08
 var succeeds = true
 var settles = true
 func write(_ id: UInt32, _ value: Float) -> Bool { if succeeds && settles { current = value }; return succeeds }
 func read(_ id: UInt32) -> Float? { current }
}
final class Status { var title = "" }
final class Harness {
 var saved: (UInt32, Float)? = (1, 0.4375)
 var restorePending = false
 let brightness = FakeBrightness()
 let status = Status()
    func restore() {
        guard let (id, value) = saved else { restorePending = false; return }
        restorePending = true
        DebugLog.shared.write("restore fixed target display=\(id) target=\(value)")
        let wrote = brightness.write(id, value)
        let actual = brightness.read(id)
        if wrote, let actual, abs(actual - value) <= 0.01 {
            saved = nil
            restorePending = false
        }
        DebugLog.shared.write("restore verified=\(!restorePending) readback=\(String(describing: actual))")
        status.title = restorePending ? "Restoring brightness — retry pending" : "5 minutes idle → 5% brightness"
    }
}
let h = Harness()
h.restore()
assert(h.saved == nil && h.brightness.current == 0.4375)
h.saved = (1, 0.62254447); h.brightness.current = 0.16030934
h.brightness.succeeds = false; h.restore()
assert(h.saved != nil && h.restorePending)
h.brightness.succeeds = true; h.brightness.settles = false; h.restore()
assert(h.saved != nil && h.restorePending)
h.brightness.settles = true; h.restore()
assert(h.saved == nil && !h.restorePending && h.brightness.current == 0.62254447)
print("PASS: drift, failed write, unconfirmed readback, successful retry")
