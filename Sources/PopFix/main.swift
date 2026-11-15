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

/// Now Playing control through MediaRemote. macOS 15.4+ blocks third-party apps from the framework, but
/// Apple-signed /usr/bin/perl may use it, so (like FluidVoice) we run the mediaremote-adapter script under perl.
/// It sees any app that publishes Now Playing (Music, Spotify, browser tabs, VLC, …) and has explicit
/// pause/play, so there are no toggles and no Automation/Accessibility permissions.
enum NowPlaying {
    private struct Info: Decodable {
        struct Payload: Decodable { let isPlaying: Bool? }
        let payload: Payload
    }

    /// Wrapper that keeps the adapter's run loop alive through one query after a command so it can deliver.
    private static let wrapper = """
    my $script = shift @ARGV;
    my $command = $ARGV[1];
    do $script;
    die $@ if $@;
    main::get() if $command eq 'pause' || $command eq 'play';
    """

    private static func perl(_ command: String) -> (status: Int32, out: Data)? {
        guard let script = Bundle.main.path(forResource: "run", ofType: "pl"),
              let lib = Bundle.main.privateFrameworksPath.map({ $0 + "/libMediaRemoteAdapter.dylib" }) else { return nil }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        p.arguments = ["-e", wrapper, script, lib, command]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return nil }
        let kill = DispatchWorkItem { p.terminate() }
        DispatchQueue.global().asyncAfter(deadline: .now() + 3, execute: kill)   // a wedged helper must not stall the restart
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        kill.cancel()
        return (p.terminationStatus, data)
    }

    static func isPlaying() -> Bool {
        guard let r = perl("get"), r.status == 0 else { return false }
        return (try? JSONDecoder().decode(Info.self, from: r.out))?.payload.isPlaying == true
    }

    /// Pauses the current Now Playing app if it is playing; the returned closure resumes it.
    static func pause() -> () -> Void {
        guard isPlaying() else { return {} }
        _ = perl("pause")
        return { _ = perl("play") }
    }
}

/// `sudo -n -l <cmd>` exits 0 for any allowed command, password-protected or not, so inspect the full
/// listing for a NOPASSWD entry that covers it.
func passwordlessRestartEnabled() -> Bool {
    run("/usr/bin/sudo", ["-n", "-l"]).out.split(separator: "\n").contains {
        $0.contains("NOPASSWD:") && ($0.contains("/usr/bin/killall coreaudiod") || $0.contains("NOPASSWD: ALL"))
    }
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

// One-time admin approval for passwordless auto-restart, without needing the menu bar item.
if CommandLine.arguments.contains("--enable-passwordless") {
    let ok = passwordlessRestartEnabled() || installSudoersRule()
    print(ok ? "passwordless restart enabled" : "failed")
    exit(ok ? 0 : 1)
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
        get { defaults.object(forKey: "autoRestart") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "autoRestart") }
    }

    var count = 0
    var spiking = false
    var restarting = false
    var cooldownUntil = Date.distantPast
    var lastRestart: Date?
    var passwordless = false
    var failureNotified = false
    var spikeLogged = false   // one detection report per spike episode

    func applicationDidFinishLaunching(_ note: Notification) {
        UNUserNotificationCenter.current().delegate = self
        Notifier.authorize { [self] in warnNotificationsBlocked() }
        watcher.start()
        queue.async {
            let v = passwordlessRestartEnabled()
            DispatchQueue.main.async { self.passwordless = v; if !v { self.promptPasswordlessSetup() } }
        }
        // .common so detection keeps ticking while the first-launch alert's modal loop is open.
        RunLoop.main.add(Timer(timeInterval: 1, repeats: true) { [self] _ in tick() }, forMode: .common)
        render()
    }

    func applicationWillTerminate(_ note: Notification) { watcher.stop() }

    func userNotificationCenter(_ c: UNUserNotificationCenter, willPresent n: UNNotification,
                                withCompletionHandler done: @escaping (UNNotificationPresentationOptions) -> Void) {
        done([.banner, .sound])
    }

    func userNotificationCenter(_ c: UNUserNotificationCenter, didReceive r: UNNotificationResponse,
                                withCompletionHandler done: @escaping () -> Void) {
        let info = r.notification.request.content.userInfo
        if r.actionIdentifier == Notifier.restartAction
            || (r.actionIdentifier == UNNotificationDefaultActionIdentifier && info["kind"] as? String == "detect") {
            DispatchQueue.main.async { [self] in
                if !restarting { restart(interactive: true, reason: "Restart from notification") }
            }
        } else if let path = info["report"] as? String {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
        }
        done()
    }

    func tick() {
        count = watcher.count(within: window)
        spiking = count >= threshold
        if !spiking { failureNotified = false; spikeLogged = false }
        if spiking && !restarting {
            if autoRestart && passwordless {
                if Date() >= cooldownUntil {
                    restart(interactive: false, reason: "Auto-restart (\(count) overloads/\(Int(window))s)")
                }
            } else if !spikeLogged {
                spikeLogged = true
                logDetection(why: autoRestart ? "passwordless restart isn't set up" : "auto-restart is off")
            }
        }
        render()
    }

    /// Spike seen but no restart happened: tell the user right away (with a restart button) and save a report.
    func logDetection(why: String) {
        let n = count
        let url = Report.newURL()
        Notifier.post("Audio popping detected",
                      "\(n) overloads/\(Int(window))s; not restarted automatically (\(why)). Click \"Restart audio now\" to fix it.",
                      reveal: url, offerRestart: true)
        queue.async {
            let snap = Report.snapshot()
            Report.write(to: url, reason: "Pop detected, not restarted: \(why) (\(n) overloads/\(Int(window))s)", count: n, action: "none (detected only)", snapshot: snap)
        }
    }

    /// macOS blocks PopFix banners (denied, or alerts set to None): nothing would be visible, so say so at launch.
    func warnNotificationsBlocked() {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = "PopFix notifications are turned off"
        a.informativeText = "You won't see a banner when audio pops are detected or coreaudiod is restarted. Turn on Allow Notifications and set the alert style to Banners or Alerts for PopFix."
        a.addButton(withTitle: "Open Notification Settings")
        a.addButton(withTitle: "Later")
        if a.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Explains and installs the passwordless restart rule, then turns auto-restart on. Shown once at launch
    /// when the rule is missing, and whenever the user re-enrolls from the menu (`force`).
    func promptPasswordlessSetup(force: Bool = false) {
        guard force || (autoRestart && !defaults.bool(forKey: "passwordlessPrompted")) else { return }
        defaults.set(true, forKey: "passwordlessPrompted")
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = "Enable automatic restart?"
        a.informativeText = "PopFix restarts coreaudiod when audio pops, but that needs a one-time admin approval. It installs a rule allowing only `killall coreaudiod` without a password. Until then PopFix only logs pops."
        a.addButton(withTitle: "Enable…")
        a.addButton(withTitle: "Not now")
        guard a.runModal() == .alertFirstButtonReturn else { return }
        autoRestart = true
        queue.async { [self] in
            _ = installSudoersRule()
            let v = passwordlessRestartEnabled()
            DispatchQueue.main.async { self.passwordless = v; self.render() }
        }
    }

    func restart(interactive: Bool, reason: String) {
        restarting = true
        cooldownUntil = Date().addingTimeInterval(cooldown)
        let n = count
        let url = Report.newURL()
        let restartID = "restart-\(url.lastPathComponent)"
        if !interactive {
            Notifier.post("Audio popping detected", "\(n) overloads/\(Int(window))s. Restarting audio automatically…", id: restartID)
        }
        queue.async { [self] in
            let snap = Report.snapshot()
            let resume = NowPlaying.pause()
            let ok = restartCoreaudiod(interactive: interactive)
            if ok { Thread.sleep(forTimeInterval: 2) }  // let coreaudiod come back before resuming
            resume()
            DispatchQueue.main.async {
                self.restarting = false
                if ok { self.lastRestart = Date() }
                if !ok && !interactive && !self.failureNotified {
                    self.failureNotified = true
                    self.logDetection(why: "restart failed")
                }
            }
            guard ok else { return }
            // Clear the "Restarting…" notification; the result is posted as a new one so it alerts on its own.
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [restartID])
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
        b?.imagePosition = spiking ? .imageLeading : .imageOnly

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

        let pw = m.addItem(withTitle: passwordless ? "Remove automatic restart" : "Set up automatic restart…",
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
    /// Turning it on without the sudoers rule would be a silent half-enrolled state, so go through setup instead.
    @objc func toggleAuto() {
        if !autoRestart && !passwordless { promptPasswordlessSetup(force: true); return }
        autoRestart.toggle()
        render()
    }
    @objc func setThreshold(_ s: NSMenuItem) {
        if let t = s.representedObject as? Int { threshold = t; render() }
    }
    /// Enrolled: remove the sudoers rule and stop auto-restarting. Not enrolled: show the setup dialog again.
    @objc func togglePasswordless() {
        guard passwordless else { promptPasswordlessSetup(force: true); return }
        queue.async { [self] in
            _ = removeSudoersRule()
            let v = passwordlessRestartEnabled()
            DispatchQueue.main.async {
                self.passwordless = v
                if !v { self.autoRestart = false }
                self.render()
            }
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
