import AppKit
import UserNotifications

// MARK: - Process helpers

@discardableResult
func run(_ path: String, _ args: [String]) -> (status: Int32, out: String) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: path)
    p.arguments = args
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = pipe
    do { try p.run() } catch { return (-1, "") }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return (p.terminationStatus, String(decoding: data, as: UTF8.self))
}

/// Counts coreaudiod "Audio IO Overload" events (the HAL log line emitted each time an I/O cycle
/// misses its deadline, i.e. an audible pop). Readable unprivileged via `log stream`.
final class OverloadWatcher {
    static let marker = "Audio IO Overload thread:"   // one per overload; the filter banner lacks "thread:"
    private let lock = NSLock()
    private var stamps: [Date] = []
    private var carry = ""
    private var stopped = false
    private var proc: Process?

    func start() {
        lock.lock(); defer { lock.unlock() }
        stopped = false
        launch()
    }

    private func launch() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/log")
        p.arguments = ["stream", "--style", "compact", "--predicate",
                       "process == \"coreaudiod\" AND eventMessage CONTAINS \"Audio IO Overload\""]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        pipe.fileHandleForReading.readabilityHandler = { [weak self] h in
            let d = h.availableData
            if d.isEmpty { h.readabilityHandler = nil; return }
            self?.ingest(String(decoding: d, as: UTF8.self))
        }
        p.terminationHandler = { [weak self] _ in
            guard let self else { return }
            DispatchQueue.global().asyncAfter(deadline: .now() + 5) {
                self.lock.lock(); defer { self.lock.unlock() }
                if !self.stopped { self.launch() }
            }
        }
        do { try p.run(); proc = p } catch { proc = nil }
    }

    private func ingest(_ chunk: String) {
        lock.lock(); defer { lock.unlock() }
        carry += chunk
        var lines = carry.split(separator: "\n", omittingEmptySubsequences: false)
        carry = String(lines.removeLast())
        let now = Date()
        for l in lines where l.contains(Self.marker) { stamps.append(now) }
    }

    /// Overloads seen in the last `window` seconds.
    func count(within window: TimeInterval) -> Int {
        lock.lock(); defer { lock.unlock() }
        let cutoff = Date().addingTimeInterval(-60)
        stamps.removeAll { $0 < cutoff }
        let c = Date().addingTimeInterval(-window)
        return stamps.reduce(0) { $0 + ($1 >= c ? 1 : 0) }
    }

    func stop() {
        lock.lock(); defer { lock.unlock() }
        stopped = true
        proc?.terminate()
    }
}

let sudoersPath = "/etc/sudoers.d/macos-pop-fix"

/// Auto path (`interactive: false`) only tries passwordless sudo; the admin prompt is manual-only.
func restartCoreaudiod(interactive: Bool) -> Bool {
    if run("/usr/bin/sudo", ["-n", "/usr/bin/killall", "coreaudiod"]).status == 0 { return true }
    guard interactive else { return false }
    let script = "do shell script \"/usr/bin/killall coreaudiod\" with administrator privileges"
    return run("/usr/bin/osascript", ["-e", script]).status == 0
}

func passwordlessRestartEnabled() -> Bool {
    run("/usr/bin/sudo", ["-n", "-l", "/usr/bin/killall", "coreaudiod"]).status == 0
}

func installSudoersRule() -> Bool {
    let tmp = NSTemporaryDirectory() + "macos-pop-fix.sudoers"
    let rule = "\(NSUserName()) ALL=(root) NOPASSWD: /usr/bin/killall coreaudiod\n"
    guard (try? rule.write(toFile: tmp, atomically: true, encoding: .utf8)) != nil else { return false }
    let sh = "/usr/sbin/visudo -cf '\(tmp)' && /usr/bin/install -m 0440 -o root -g wheel '\(tmp)' \(sudoersPath)"
    let script = "do shell script \"\(sh)\" with administrator privileges"
    return run("/usr/bin/osascript", ["-e", script]).status == 0
}

func removeSudoersRule() -> Bool {
    let script = "do shell script \"/bin/rm -f \(sudoersPath)\" with administrator privileges"
    return run("/usr/bin/osascript", ["-e", script]).status == 0
}

// MARK: - CLI probe

let window: TimeInterval = 10

if CommandLine.arguments.contains("--probe") {
    let w = OverloadWatcher()
    w.start()
    for _ in 0..<20 {
        Thread.sleep(forTimeInterval: 1)
        print("overloads in last \(Int(window))s: \(w.count(within: window))")
    }
    w.stop()
    exit(0)
}

// Writes a diagnostic report without restarting anything (for testing / manual bug reports).
if CommandLine.arguments.contains("--report") {
    let url = Report.newURL()
    Report.write(to: url, reason: "Manual report (--report)", count: 0, action: "none (report only)", snapshot: Report.snapshot())
    print(url.path)
    exit(0)
}

// MARK: - App

final class App: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    let defaults = UserDefaults.standard
    let queue = DispatchQueue(label: "popfix.restart")
    let watcher = OverloadWatcher()

    let thresholds = [3, 10, 30, 100]   // overloads per 10s window
    let cooldown: TimeInterval = 30     // after a restart

    var threshold: Int {
        get { defaults.object(forKey: "overloadThreshold") as? Int ?? 10 }
        set { defaults.set(newValue, forKey: "overloadThreshold") }
    }
    var autoRestart: Bool {
        get { defaults.object(forKey: "autoRestart") as? Bool ?? false }
        set { defaults.set(newValue, forKey: "autoRestart") }
    }

    var count = 0
    var spiking = false
    var restarting = false
    var cooldownUntil = Date.distantPast
    var lastRestart: Date?
    var passwordless = false
    var failureNotified = false

    func applicationDidFinishLaunching(_ note: Notification) {
        UNUserNotificationCenter.current().delegate = self
        Notifier.authorize()
        watcher.start()
        refreshPasswordless()
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [self] _ in tick() }
        render()
    }

    func applicationWillTerminate(_ note: Notification) { watcher.stop() }

    func userNotificationCenter(_ c: UNUserNotificationCenter, willPresent n: UNNotification,
                                withCompletionHandler done: @escaping (UNNotificationPresentationOptions) -> Void) {
        done([.banner, .sound])
    }

    func userNotificationCenter(_ c: UNUserNotificationCenter, didReceive r: UNNotificationResponse,
                                withCompletionHandler done: @escaping () -> Void) {
        if let path = r.notification.request.content.userInfo["report"] as? String {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
        }
        done()
    }

    func tick() {
        count = watcher.count(within: window)
        spiking = count >= threshold
        if !spiking { failureNotified = false }
        if spiking && autoRestart && !restarting && Date() >= cooldownUntil {
            restart(interactive: false, reason: "Auto-restart (\(count) overloads/\(Int(window))s)")
        }
        render()
    }

    func restart(interactive: Bool, reason: String) {
        restarting = true
        cooldownUntil = Date().addingTimeInterval(cooldown)
        let n = count
        let url = Report.newURL()
        queue.async { [self] in
            let snap = Report.snapshot()
            let ok = restartCoreaudiod(interactive: interactive)
            DispatchQueue.main.async {
                self.restarting = false
                if ok { self.lastRestart = Date() }
                if !ok && !interactive && !self.failureNotified {
                    self.failureNotified = true
                    Notifier.post("Audio pops detected", "Auto-restart failed. Enable passwordless restart from the PopFix menu.")
                }
            }
            guard ok else { return }
            Notifier.post("Restarted coreaudiod", "\(reason). Saving diagnostics to ~/Library/Logs/PopFix.", reveal: url)
            Report.write(to: url, reason: reason, count: n, action: "restarted coreaudiod", snapshot: snap)
        }
    }

    func refreshPasswordless() {
        queue.async { let v = passwordlessRestartEnabled(); DispatchQueue.main.async { self.passwordless = v } }
    }

    // MARK: UI

    func render() {
        let b = item.button
        b?.title = spiking ? " ⚠︎ \(count)" : ""
        b?.image = Icons.menuBar
        b?.imagePosition = .imageLeading

        let m = NSMenu()
        m.addItem(withTitle: "Audio overloads (last \(Int(window))s): \(count)", action: nil, keyEquivalent: "").isEnabled = false
        if let t = lastRestart {
            let f = DateFormatter(); f.timeStyle = .medium
            m.addItem(withTitle: "Last restart: \(f.string(from: t))", action: nil, keyEquivalent: "").isEnabled = false
        }
        m.addItem(.separator())
        m.addItem(withTitle: "Restart coreaudiod now", action: #selector(restartNow), keyEquivalent: "r").target = self

        let auto = m.addItem(withTitle: "Auto-restart on pops", action: #selector(toggleAuto), keyEquivalent: "")
        auto.target = self; auto.state = autoRestart ? .on : .off

        let sub = NSMenu()
        for t in thresholds {
            let i = sub.addItem(withTitle: "≥ \(t) overloads / \(Int(window))s", action: #selector(setThreshold(_:)), keyEquivalent: "")
            i.target = self; i.representedObject = t; i.state = t == threshold ? .on : .off
        }
        m.addItem(withTitle: "Pop threshold", action: nil, keyEquivalent: "").submenu = sub

        let pw = m.addItem(withTitle: passwordless ? "Remove passwordless restart" : "Enable passwordless restart…",
                           action: #selector(togglePasswordless), keyEquivalent: "")
        pw.target = self
        m.addItem(.separator())
        m.addItem(withTitle: "Show diagnostic reports", action: #selector(openLogs), keyEquivalent: "").target = self
        m.addItem(withTitle: "Report to Apple…", action: #selector(reportToApple), keyEquivalent: "").target = self
        m.addItem(.separator())
        m.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = m
    }

    @objc func restartNow() { restart(interactive: true, reason: "Manual restart") }
    @objc func toggleAuto() { autoRestart.toggle(); render() }
    @objc func setThreshold(_ s: NSMenuItem) {
        if let t = s.representedObject as? Int { threshold = t; render() }
    }
    @objc func togglePasswordless() {
        let enabled = passwordless
        queue.async { [self] in
            _ = enabled ? removeSudoersRule() : installSudoersRule()
            let v = passwordlessRestartEnabled()
            DispatchQueue.main.async { self.passwordless = v; self.render() }
        }
    }

    @objc func openLogs() { Report.revealLatest() }
    @objc func reportToApple() { Report.reportToApple() }
}

let app = NSApplication.shared
let delegate = App()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
