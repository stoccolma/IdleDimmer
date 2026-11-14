import AVFoundation
import AppKit
import CoreGraphics
import CryptoKit
import Darwin

final class DebugLog {
    static let shared = DebugLog()
    let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/IdleDimmer/debug.log")
    var enabled = UserDefaults.standard.bool(forKey: "debugLogging")
    func write(_ message: String) {
        guard enabled else { return }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > 2_000_000 {
                let old = url.appendingPathExtension("previous")
                try? FileManager.default.removeItem(at: old)
                try FileManager.default.moveItem(at: url, to: old)
            }
            let data = Data((ISO8601DateFormatter().string(from: Date()) + " " + message + "\n").utf8)
            if !FileManager.default.fileExists(atPath: url.path) { FileManager.default.createFile(atPath: url.path, contents: nil) }
            let file = try FileHandle(forWritingTo: url)
            defer { try? file.close() }
            try file.seekToEnd(); try file.write(contentsOf: data)
        } catch { NSLog("IdleDimmer debug log failed: %@", String(describing: error)) }
    }
}

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
        guard let get else { DebugLog.shared.write("brightness.read unavailable"); return nil }
        let result = get(id, &value)
        guard result == 0, value.isFinite, value >= 0, value <= 1 else {
            DebugLog.shared.write("brightness.read failed display=\(id) code=\(result) value=\(value)"); return nil
        }
        return value
    }
    func write(_ id: UInt32, _ value: Float) -> Bool {
        let result = set?(id, value)
        DebugLog.shared.write("brightness.write display=\(id) target=\(value) code=\(String(describing: result)) readback=\(String(describing: read(id)))")
        return result == 0
    }
}

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

/// Records a short camera clip with sound when a wrong unlock code is entered.
final class IntruderCam: NSObject, AVCaptureFileOutputRecordingDelegate {
    static let folder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Movies/IdleDimmer")
    private let queue = DispatchQueue(label: "local.idledimmer.camera")
    private var session: AVCaptureSession?
    private var output: AVCaptureMovieFileOutput?
    static func requestAccess() {
        for media in [AVMediaType.video, .audio] where AVCaptureDevice.authorizationStatus(for: media) == .notDetermined {
            AVCaptureDevice.requestAccess(for: media) { _ in }
        }
    }
    func record(seconds: Double = 20, completion: ((URL?) -> Void)? = nil) {
        queue.async {
            guard self.session == nil else { return }   // one clip at a time
            guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized,
                  let camera = AVCaptureDevice.default(for: .video),
                  let input = try? AVCaptureDeviceInput(device: camera) else {
                DebugLog.shared.write("intruder clip skipped: camera unavailable or not permitted"); completion?(nil); return
            }
            let session = AVCaptureSession()
            let output = AVCaptureMovieFileOutput()
            guard session.canAddInput(input), session.canAddOutput(output) else { completion?(nil); return }
            session.addInput(input); session.addOutput(output)
            // Sound is optional: without microphone permission the clip is video only.
            if AVCaptureDevice.authorizationStatus(for: .audio) == .authorized, let mic = AVCaptureDevice.default(for: .audio),
               let sound = try? AVCaptureDeviceInput(device: mic), session.canAddInput(sound) { session.addInput(sound) }
            else { DebugLog.shared.write("intruder clip without sound: microphone unavailable or not permitted") }
            output.maxRecordedDuration = CMTime(seconds: seconds, preferredTimescale: 600)
            let stamp = DateFormatter(); stamp.dateFormat = "yyyy-MM-dd_HH-mm-ss"
            let url = IntruderCam.folder.appendingPathComponent("fel-kod-\(stamp.string(from: Date())).mov")
            try? FileManager.default.createDirectory(at: IntruderCam.folder, withIntermediateDirectories: true)
            self.session = session; self.output = output; self.completion = completion
            session.startRunning()
            output.startRecording(to: url, recordingDelegate: self)
            DebugLog.shared.write("intruder clip started \(url.lastPathComponent)")
        }
    }
    private var completion: ((URL?) -> Void)?
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo url: URL, from connections: [AVCaptureConnection], error: Error?) {
        // Reaching the maximum duration is reported as an error although the file is complete.
        let finished = (error as NSError?)?.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool ?? (error == nil)
        DebugLog.shared.write("intruder clip finished ok=\(finished) \(url.lastPathComponent)")
        queue.async {
            self.session?.stopRunning()
            self.session = nil; self.output = nil
            let done = self.completion; self.completion = nil
            done?(finished ? url : nil)
        }
    }
}

/// Decoy lock: covers every screen and swallows physical keyboard/mouse input,
/// while synthetic input and screen captures (automation agents) pass straight through.
final class FakeLock {
    private var windows: [NSPanel] = []
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var typed = ""
    private var clock: NSTextField?
    private var date: NSTextField?
    private var field: NSTextField?
    private var screenObserver: NSObjectProtocol?
    var onUnlock: (([Date]) -> Void)?
    private var failures: [Date] = []
    var onWrongCode: (() -> Void)?
    var isLocked: Bool { tap != nil }
    var hasCode: Bool { UserDefaults.standard.string(forKey: "lockHash") != nil }

    private static func hash(_ code: String, salt: String) -> String {
        SHA256.hash(data: Data((salt + code).utf8)).map { String(format: "%02x", $0) }.joined()
    }
    func setCode(_ code: String) {
        let salt = UUID().uuidString
        UserDefaults.standard.set(salt, forKey: "lockSalt")
        UserDefaults.standard.set(FakeLock.hash(code, salt: salt), forKey: "lockHash")
    }
    private func matches(_ code: String) -> Bool {
        guard let salt = UserDefaults.standard.string(forKey: "lockSalt"),
              let stored = UserDefaults.standard.string(forKey: "lockHash") else { return false }
        return FakeLock.hash(code, salt: salt) == stored
    }

    /// Returns false when the input filter could not be installed (missing Accessibility permission).
    func lock() -> Bool {
        guard !isLocked else { return true }
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let lock = Unmanaged<FakeLock>.fromOpaque(refcon).takeUnretainedValue()
            return lock.pass(type, event) ? Unmanaged.passUnretained(event) : nil
        }
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                           eventsOfInterest: CGEventMask.max, callback: callback,
                                           userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return false }
        tap = port
        source = CFMachPortCreateRunLoopSource(nil, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        typed = ""; failures = []
        buildWindows()
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            if self?.isLocked == true { self?.buildWindows() }
        }
        DebugLog.shared.write("fake lock on screens=\(windows.count)")
        return true
    }
    func unlock() {
        guard let port = tap else { return }
        CGEvent.tapEnable(tap: port, enable: false)
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        CFMachPortInvalidate(port)
        tap = nil; source = nil; typed = ""
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
        windows.forEach { $0.orderOut(nil) }
        windows = []; clock = nil; date = nil; field = nil
        DebugLog.shared.write("fake lock off")
        let attempts = failures; failures = []
        onUnlock?(attempts)
    }

    /// true = deliver the event, false = swallow it.
    private func pass(_ type: CGEventType, _ event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return true
        }
        // Hardware events come from the HID system (pid 0); posted events carry the sender's pid.
        if event.getIntegerValueField(.eventSourceUnixProcessID) != 0 { return true }
        if type == .mouseMoved { return true }
        if type == .keyDown { key(event) }
        return false
    }
    private func key(_ event: CGEvent) {
        switch event.getIntegerValueField(.keyboardEventKeycode) {
        case 36, 76:
            if matches(typed) { unlock(); return }
            typed = ""
            field?.stringValue = "Fel lösenord"
            failures.append(Date())
            onWrongCode?()
            return
        case 51: if !typed.isEmpty { typed.removeLast() }
        case 53: typed = ""
        default:
            guard event.flags.intersection([.maskCommand, .maskControl]).isEmpty else { return }
            var length = 0
            var chars = [UniChar](repeating: 0, count: 8)
            event.keyboardGetUnicodeString(maxStringLength: 8, actualStringLength: &length, unicodeString: &chars)
            let text = String(utf16CodeUnits: chars, count: length).filter { !($0.unicodeScalars.first?.properties.generalCategory == .control) }
            guard typed.count < 64 else { return }
            typed += text
        }
        field?.stringValue = typed.isEmpty ? "Ange lösenord" : String(repeating: "●", count: typed.count)
    }

    private func label(_ size: CGFloat, _ weight: NSFont.Weight, alpha: CGFloat) -> NSTextField {
        let l = NSTextField(labelWithString: "")
        l.font = .systemFont(ofSize: size, weight: weight)
        l.textColor = NSColor.white.withAlphaComponent(alpha)
        l.alignment = .center
        return l
    }
    private func buildWindows() {
        windows.forEach { $0.orderOut(nil) }
        windows = []
        for (index, screen) in NSScreen.screens.enumerated() {
            let panel = NSPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
            panel.backgroundColor = .black
            panel.isOpaque = true
            panel.hasShadow = false
            panel.hidesOnDeactivate = false
            panel.ignoresMouseEvents = true      // synthetic clicks reach the apps underneath
            panel.sharingType = .none            // invisible to screenshots and screen capture
            panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
            let view = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
            view.wantsLayer = true
            let gradient = CAGradientLayer()
            gradient.colors = [NSColor(white: 0.13, alpha: 1).cgColor, NSColor(white: 0.02, alpha: 1).cgColor]
            gradient.frame = view.bounds
            gradient.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
            view.layer?.addSublayer(gradient)
            if index == 0 {
                let date = label(22, .medium, alpha: 0.8)
                let clock = label(104, .semibold, alpha: 0.95)
                let user = label(15, .medium, alpha: 0.9)
                user.stringValue = NSFullUserName()
                let field = label(13, .regular, alpha: 0.75)
                field.stringValue = "Ange lösenord"
                let pill = NSView()
                pill.wantsLayer = true
                pill.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.14).cgColor
                pill.layer?.cornerRadius = 15
                pill.translatesAutoresizingMaskIntoConstraints = false
                field.translatesAutoresizingMaskIntoConstraints = false
                pill.addSubview(field)
                let top = NSStackView(views: [date, clock])
                let bottom = NSStackView(views: [user, pill])
                for stack in [top, bottom] {
                    stack.orientation = .vertical; stack.alignment = .centerX
                    stack.translatesAutoresizingMaskIntoConstraints = false
                    view.addSubview(stack)
                }
                top.spacing = 0; bottom.spacing = 10
                NSLayoutConstraint.activate([
                    pill.widthAnchor.constraint(equalToConstant: 200), pill.heightAnchor.constraint(equalToConstant: 30),
                    field.centerXAnchor.constraint(equalTo: pill.centerXAnchor), field.centerYAnchor.constraint(equalTo: pill.centerYAnchor),
                    field.widthAnchor.constraint(lessThanOrEqualTo: pill.widthAnchor, constant: -16),
                    top.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                    top.topAnchor.constraint(equalTo: view.topAnchor, constant: screen.frame.height * 0.1),
                    bottom.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                    bottom.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -screen.frame.height * 0.1)
                ])
                self.clock = clock; self.date = date; self.field = field
            }
            panel.contentView = view
            panel.orderFrontRegardless()
            windows.append(panel)
        }
        updateClock()
    }
    func updateClock() {
        guard isLocked else { return }
        let now = Date()
        let time = DateFormatter(); time.dateFormat = "HH:mm"
        let day = DateFormatter(); day.setLocalizedDateFormatFromTemplate("EEEEdMMMM")
        clock?.stringValue = time.string(from: now)
        date?.stringValue = day.string(from: now)
    }
}

final class Controller: NSObject, NSApplicationDelegate {
    let brightness = Brightness()
    let keepAwake = KeepAwake()
    let fakeLock = FakeLock()
    let intruderCam = IntruderCam()
    var lockStartedKeepAwake = false
    var awakeItem: NSMenuItem!
    var item: NSStatusItem!
    var timer: Timer?
    var saved: (UInt32, Float)?
    var prepared: (id: UInt32, value: Float, time: TimeInterval)?
    var manualPreparation = false
    var restorePending = false
    var dimRequest: DispatchWorkItem?
    var enabled = true
    var previousIdle: Double = 0
    var waitForActivity = false
    let delay = 300.0
    let dimLevel: Float = 0.05
    var status: NSMenuItem!
    var toggle: NSMenuItem!
    var debugItem: NSMenuItem!
    var lastSample = Date.distantPast
    var lastTick = Date()
    // While fake-locked only physical input counts, so agent activity does not undo the dim.
    func idle() -> Double { CGEventSource.secondsSinceLastEventType(fakeLock.isLocked ? .hidSystemState : .combinedSessionState, eventType: CGEventType(rawValue: UInt32.max)!) }
    func applicationDidFinishLaunching(_ notification: Notification) {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateIcon()

        let menu = NSMenu()
        status = NSMenuItem(title: "5 minutes idle → 5% brightness", action: nil, keyEquivalent: "")
        menu.addItem(status)
        toggle = NSMenuItem(title: "Enabled", action: #selector(toggleEnabled), keyEquivalent: "")
        toggle.target = self; toggle.state = .on; menu.addItem(toggle)
        awakeItem = NSMenuItem(title: "Håll datorn vaken (caffeinate -di)", action: #selector(toggleKeepAwake), keyEquivalent: "")
        awakeItem.target = self; menu.addItem(awakeItem)
        keepAwake.onChange = { [weak self] in
            guard let self else { return }
            self.awakeItem.state = self.keepAwake.isRunning ? .on : .off
            self.updateIcon()
        }
        for (title, action) in [("Lås skärmen (skenlås)", #selector(lockScreen)), ("Ställ in upplåsningskod…", #selector(chooseCode)), ("Visa filmer från fel kod", #selector(openClips))] {
            let entry = NSMenuItem(title: title, action: action, keyEquivalent: "")
            entry.target = self; menu.addItem(entry)
        }
        fakeLock.onWrongCode = { [weak self] in self?.intruderCam.record() }
        fakeLock.onUnlock = { [weak self] attempts in
            guard let self else { return }
            // Deferred: this runs inside the input filter callback.
            if !attempts.isEmpty { DispatchQueue.main.async { self.reportAttempts(attempts) } }
            if self.lockStartedKeepAwake { self.keepAwake.stop() }
            self.lockStartedKeepAwake = false
            self.previousIdle = self.idle()
        }
        for (title, action) in [("Dim now", #selector(dimNow)), ("Restore brightness", #selector(restoreNow)), ("Quit IdleDimmer", #selector(quit))] {
            let entry = NSMenuItem(title: title, action: action, keyEquivalent: "")
            entry.target = self; menu.addItem(entry)
        }
        menu.addItem(.separator())
        debugItem = NSMenuItem(title: "Debug logging", action: #selector(toggleDebug), keyEquivalent: "")
        debugItem.target = self; debugItem.state = DebugLog.shared.enabled ? .on : .off
        menu.addItem(debugItem)
        for (title, action) in [("Open debug log", #selector(openLog)), ("Capture debug snapshot", #selector(snapshot))] {
            let entry = NSMenuItem(title: title, action: action, keyEquivalent: "")
            entry.target = self; menu.addItem(entry)
        }
        item.menu = menu
        DebugLog.shared.write("launch build=2026-11-14-fake-lock-cam-audio pid=\(ProcessInfo.processInfo.processIdentifier)")
        previousIdle = idle()
        // Starting the utility never immediately dims a long-idle desktop.
        waitForActivity = previousIdle >= delay
        let pollingTimer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in self?.tick() }
        timer = pollingTimer
        RunLoop.main.add(pollingTimer, forMode: .common)
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
            NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(woke), name: name, object: nil)
        }
        if brightness.builtIn().flatMap({ brightness.read($0) }) == nil {
            status.title = "Built-in display brightness unavailable"
        }
    }
    func tick() {
        let gap = Date().timeIntervalSince(lastTick); lastTick = Date()
        if gap > 2 { DebugLog.shared.write("timer gap seconds=\(gap)") }
        if DebugLog.shared.enabled && Date().timeIntervalSince(lastSample) >= 5 { snapshot() }
        fakeLock.updateClock()
        if restorePending { restore() }
        let now = idle()
        guard now.isFinite, now >= 0 else { return }
        let activity = now < previousIdle || now < 0.6
        previousIdle = now
        if activity {
            if !manualPreparation {
                if prepared != nil { DebugLog.shared.write("automatic preparation cancelled by activity") }
                prepared = nil
            }
            waitForActivity = false
            if saved != nil { DebugLog.shared.write("activity detected idle=\(now)"); restore() }
        }
        if let sample = prepared, ProcessInfo.processInfo.systemUptime - sample.time >= 2 {
            applyDim()
        } else if enabled && !waitForActivity && saved == nil && prepared == nil && now >= delay - 2 { dim() }
    }
    func dim() {
        guard saved == nil, prepared == nil, let id = brightness.builtIn(), let value = brightness.read(id) else { return }
        guard value > dimLevel else { waitForActivity = true; return }
        prepared = (id, value, ProcessInfo.processInfo.systemUptime)
        DebugLog.shared.write("pre-dim fixed target display=\(id) brightness=\(value); waiting 2 seconds")
    }
    func applyDim() {
        guard saved == nil, let sample = prepared else { return }
        prepared = nil
        manualPreparation = false
        guard brightness.builtIn() == sample.id else { return }
        saved = (sample.id, sample.value)
        if !brightness.write(sample.id, dimLevel) {
            // A failed call may still have changed the screen; retain the target.
            restorePending = true
            status.title = "Dim failed — restoring saved brightness"
            return
        }
        DebugLog.shared.write("dim applied; fixed restore target=\(sample.value)")
        status.title = "Dimmed — move mouse or press a key"
    }
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
    @objc func dimNow() {
        dimRequest?.cancel()
        let request = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.previousIdle = self.idle()
            self.prepared = nil
            self.dim()
            self.manualPreparation = self.prepared != nil
            DebugLog.shared.write("manual dim preparation=\(self.manualPreparation)")
        }
        dimRequest = request
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: request)
    }
    @objc func restoreNow() {
        dimRequest?.cancel()
        prepared = nil
        manualPreparation = false
        restore(); waitForActivity = true
    }
    @objc func woke() { DebugLog.shared.write("wake notification"); restoreNow() }
    @objc func toggleDebug() {
        DebugLog.shared.enabled.toggle()
        UserDefaults.standard.set(DebugLog.shared.enabled, forKey: "debugLogging")
        debugItem.state = DebugLog.shared.enabled ? .on : .off
        DebugLog.shared.write("debug enabled"); snapshot()
    }
    @objc func openLog() {
        if !DebugLog.shared.enabled { toggleDebug() }
        snapshot(); NSWorkspace.shared.open(DebugLog.shared.url)
    }
    @objc func snapshot() {
        guard DebugLog.shared.enabled else { return }
        lastSample = Date()
        let id = brightness.builtIn()
        DebugLog.shared.write("snapshot idle=\(idle()) enabled=\(enabled) keepAwake=\(keepAwake.isRunning) wait=\(waitForActivity) pending=\(restorePending) saved=\(String(describing: saved)) display=\(String(describing: id)) brightness=\(String(describing: id.flatMap { brightness.read($0) }))")
    }
    @objc func toggleKeepAwake() {
        if keepAwake.isRunning { keepAwake.stop() }
        else {
            do { try keepAwake.start() }
            catch {
                DebugLog.shared.write("caffeinate launch failed: \(error)")
                let alert = NSAlert()
                alert.messageText = "Kunde inte hålla datorn vaken"
                alert.informativeText = error.localizedDescription
                alert.runModal()
            }
        }
    }
    /// Asks for a new unlock code; returns true when one was saved.
    @discardableResult @objc func chooseCode() -> Bool {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Upplåsningskod för skenlåset"
        alert.informativeText = "Skriv koden och tryck Retur på den låsta skärmen för att låsa upp. Minst 4 tecken."
        let input = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        alert.accessoryView = input
        alert.addButton(withTitle: "Spara"); alert.addButton(withTitle: "Avbryt")
        alert.window.initialFirstResponder = input
        guard alert.runModal() == .alertFirstButtonReturn else { return false }
        guard input.stringValue.count >= 4 else { return chooseCode() }
        fakeLock.setCode(input.stringValue)
        return true
    }
    func reportAttempts(_ attempts: [Date]) {
        let time = DateFormatter(); time.dateFormat = "HH:mm:ss"
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = attempts.count == 1 ? "1 försök med fel kod medan skärmen var låst" : "\(attempts.count) försök med fel kod medan skärmen var låst"
        alert.informativeText = "Tidpunkter: " + attempts.prefix(20).map { time.string(from: $0) }.joined(separator: ", ") + (attempts.count > 20 ? " …" : "") + "\n\nFilmerna ligger i \(IntruderCam.folder.path)."
        alert.addButton(withTitle: "Visa filmer"); alert.addButton(withTitle: "OK")
        if alert.runModal() == .alertFirstButtonReturn { openClips() }
    }
    @objc func openClips() {
        try? FileManager.default.createDirectory(at: IntruderCam.folder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(IntruderCam.folder)
    }
    @objc func lockScreen() {
        guard fakeLock.hasCode || chooseCode() else { return }
        IntruderCam.requestAccess()   // ask now, not from under the lock screen
        guard fakeLock.lock() else {
            // Shows the system prompt that deep-links to the Accessibility pane.
            _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = "Skenlåset behöver behörigheten Hjälpmedel"
            alert.informativeText = "Utan den kan fysiska tangent- och mustryck inte stoppas. Tillåt IdleDimmer under Systeminställningar → Integritet och säkerhet → Hjälpmedel och välj sedan Lås skärmen igen."
            alert.runModal()
            return
        }
        // Sleep would trigger the real lock and stop the agents.
        if !keepAwake.isRunning {
            do { try keepAwake.start(); lockStartedKeepAwake = true }
            catch { DebugLog.shared.write("caffeinate launch failed during fake lock: \(error)") }
        }
        previousIdle = idle()
    }
    func updateIcon() {
        item.button?.attributedTitle = NSAttributedString(string: "◐", attributes: [
            .foregroundColor: keepAwake.isRunning ? NSColor.systemOrange : (enabled ? NSColor.systemGreen : NSColor.white),
            .font: NSFont.systemFont(ofSize: 17)
        ])
        item.button?.toolTip = "IdleDimmer — dimning: \(enabled ? "på" : "av"), håll vaken: \(keepAwake.isRunning ? "på" : "av")"
    }
    @objc func toggleEnabled() {
        enabled.toggle(); toggle.state = enabled ? .on : .off
        updateIcon()
        if !enabled { restoreNow() }
    }
    @objc func quit() { NSApp.terminate(nil) }
    func applicationWillTerminate(_ notification: Notification) { timer?.invalidate(); fakeLock.unlock(); keepAwake.stop(); restore() }
}

if let flag = CommandLine.arguments.firstIndex(of: "--camera-test") {
    // Records a short clip exactly as a wrong code would, then prints the file path.
    let seconds = CommandLine.arguments.dropFirst(flag + 1).first.flatMap(Double.init) ?? 3
    print("camera authorization=\(AVCaptureDevice.authorizationStatus(for: .video).rawValue) (3 = allowed)")
    let cam = IntruderCam()
    cam.record(seconds: seconds) { url in print(url?.path ?? "No clip recorded"); exit(url == nil ? 1 : 0) }
    RunLoop.main.run(until: Date().addingTimeInterval(seconds + 10)); print("Timed out"); exit(1)
} else if CommandLine.arguments.contains("--probe") {
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
