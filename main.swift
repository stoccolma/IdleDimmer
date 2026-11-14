import AppKit
import CoreGraphics
import Darwin

final class Brightness {
    typealias Get = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32
    typealias Set = @convention(c) (UInt32, Float) -> Int32
    let handle: UnsafeMutableRawPointer?
    let get: Get?
    let set: Set?
    init() {
        handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY)
        get = handle.flatMap { dlsym($0, "DisplayServicesGetBrightness") }.map { unsafeBitCast($0, to: Get.self) }
        set = handle.flatMap { dlsym($0, "DisplayServicesSetBrightness") }.map { unsafeBitCast($0, to: Set.self) }
    }
    func builtIn() -> UInt32? {
        var ids = [UInt32](repeating: 0, count: 16)
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(16, &ids, &count) == .success else { return nil }
        return ids.prefix(Int(count)).first { CGDisplayIsBuiltin($0) != 0 }
    }
    func read(_ id: UInt32) -> Float? {
        var value: Float = 0
        guard let get, get(id, &value) == 0, value.isFinite, value >= 0, value <= 1 else { return nil }
        return value
    }
    func write(_ id: UInt32, _ value: Float) -> Bool { set?(id, value) == 0 }
}

final class Controller: NSObject, NSApplicationDelegate {
    let brightness = Brightness()
    var item: NSStatusItem!
    var timer: Timer?
    var saved: (UInt32, Float)?
    var enabled = true
    var previousIdle: Double = 0
    var waitForActivity = false
    let delay = 300.0
    let dimLevel: Float = 0.05
    var status: NSMenuItem!
    var toggle: NSMenuItem!
    func idle() -> Double { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: UInt32.max)!) }
    func applicationDidFinishLaunching(_ notification: Notification) {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "◐"
        item.button?.toolTip = "IdleDimmer — dim after 5 idle minutes"
        let menu = NSMenu()
        status = NSMenuItem(title: "5 minutes idle → 5% brightness", action: nil, keyEquivalent: "")
        menu.addItem(status)
        toggle = NSMenuItem(title: "Enabled", action: #selector(toggleEnabled), keyEquivalent: "")
        toggle.target = self; toggle.state = .on; menu.addItem(toggle)
        for (title, action) in [("Dim now", #selector(dimNow)), ("Restore brightness", #selector(restoreNow)), ("Quit IdleDimmer", #selector(quit))] {
            let entry = NSMenuItem(title: title, action: action, keyEquivalent: "")
            entry.target = self; menu.addItem(entry)
        }
        item.menu = menu
        previousIdle = idle()
        // Starting the utility never immediately dims a long-idle desktop.
        waitForActivity = previousIdle >= delay
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.tick() }
        if brightness.builtIn().flatMap({ brightness.read($0) }) == nil {
            status.title = "Built-in display brightness unavailable"
        }
    }
    func tick() {
        let now = idle()
        guard now.isFinite, now >= 0 else { return }
        let activity = now < previousIdle || now < 0.6
        previousIdle = now
        if activity {
            waitForActivity = false
            if saved != nil { restore() }
        }
        if enabled && !waitForActivity && saved == nil && now >= delay { dim() }
    }
    func dim() {
        guard saved == nil, let id = brightness.builtIn(), let value = brightness.read(id) else { return }
        guard value > dimLevel else { waitForActivity = true; return }
        saved = (id, value)
        guard brightness.write(id, dimLevel) else {
            saved = nil; status.title = "Could not change brightness"; return
        }
        status.title = "Dimmed — move mouse or press a key"
    }
    func restore() {
        guard let (id, value) = saved else { return }
        // Respect a manual brightness change made while dimmed.
        if let current = brightness.read(id), abs(current - dimLevel) > 0.025 {
            saved = nil
        } else if brightness.write(id, value) {
            saved = nil
        }
        status.title = saved == nil ? "5 minutes idle → 5% brightness" : "Restore failed — use brightness keys"
    }
    @objc func dimNow() {
        // Let the click that selected the menu settle before dimming.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self else { return }
            self.previousIdle = self.idle(); self.dim()
        }
    }
    @objc func restoreNow() { restore(); waitForActivity = true }
    @objc func toggleEnabled() {
        enabled.toggle(); toggle.state = enabled ? .on : .off
        if !enabled { restore() }
    }
    @objc func quit() { NSApp.terminate(nil) }
    func applicationWillTerminate(_ notification: Notification) { timer?.invalidate(); restore() }
}

if CommandLine.arguments.contains("--probe") {
    let b = Brightness()
    guard let id = b.builtIn(), let value = b.read(id), b.set != nil else {
        print("Built-in brightness control unavailable"); exit(1)
    }
    print("Built-in display \(id); brightness \(value); idle \(CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: UInt32.max)!)) seconds")
} else {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let controller = Controller()
    app.delegate = controller
    app.run()
}
