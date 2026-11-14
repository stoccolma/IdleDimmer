import Foundation
final class DebugLog { static let shared = DebugLog(); func write(_ s: String) {} }
final class KeepAwake {
    private(set) var process: Process?
    var isRunning: Bool { process?.isRunning == true }
    var onChange: (() -> Void)?
    func start() throws {
        guard !isRunning else { return }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
        // Match the previously working Terminal invocation exactly.
        task.arguments = ["-di"]
        task.terminationHandler = { [weak self] finished in
            DispatchQueue.main.async {
                guard let self, self.process === finished else { return }
                self.process = nil
                DebugLog.shared.write("caffeinate exited code=\(finished.terminationStatus)")
                self.onChange?()
            }
        }
        try task.run()
        process = task
        DebugLog.shared.write("caffeinate started pid=\(task.processIdentifier)")
        onChange?()
    }
    func stop() {
        let task = process
        process = nil
        if task?.isRunning == true { task?.terminate() }
        DebugLog.shared.write("caffeinate stopped")
        onChange?()
    }
}

let awake = KeepAwake()
assert(!awake.isRunning)
try awake.start()
assert(awake.isRunning)
let child = awake.process!
try awake.start()
assert(awake.process === child)
awake.stop()
child.waitUntilExit()
assert(!awake.isRunning && !child.isRunning)
try awake.start()
assert(awake.isRunning)
let second = awake.process!
second.terminate()
second.waitUntilExit()
RunLoop.main.run(until: Date().addingTimeInterval(0.1))
assert(!awake.isRunning && awake.process == nil)
awake.stop()
print("PASS: start, duplicate prevention, stop, unexpected exit cleanup")
