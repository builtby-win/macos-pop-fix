import AppKit

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

/// coreaudiod runs as _coreaudiod, so proc_pid_rusage/ps can't read it unprivileged.
/// /usr/bin/top is setuid and reports it; the first sample is a since-boot average, so take the second.
func coreaudiodCPU() -> Double? {
    let pid = run("/usr/bin/pgrep", ["-x", "coreaudiod"]).out
        .split(separator: "\n").first.map(String.init)
    guard let pid, Int(pid) != nil else { return nil }
    let out = run("/usr/bin/top", ["-l", "2", "-s", "1", "-pid", pid, "-stats", "cpu"]).out
    guard let last = out.split(separator: "\n").last else { return nil }
    return Double(last.trimmingCharacters(in: .whitespaces))
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

if CommandLine.arguments.contains("--probe") {
    for _ in 0..<5 {
        print(coreaudiodCPU().map { String(format: "%.1f%%", $0) } ?? "coreaudiod not found / unreadable")
    }
    exit(0)
}

// MARK: - App

final class App: NSObject, NSApplicationDelegate {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    let defaults = UserDefaults.standard
    let queue = DispatchQueue(label: "popfix.sampler")

    let thresholds: [Double] = [8, 10, 15, 30]
    let sustainedSamples = 5          // consecutive ~3s samples above threshold
    let cooldown: TimeInterval = 30   // after a restart

    var threshold: Double {
        get { defaults.object(forKey: "threshold") as? Double ?? 10 }
        set { defaults.set(newValue, forKey: "threshold") }
    }
    var autoRestart: Bool {
        get { defaults.object(forKey: "autoRestart") as? Bool ?? false }
        set { defaults.set(newValue, forKey: "autoRestart") }
    }

    // Touched only on `queue` unless noted.
    var over = 0
    var cooldownUntil = Date.distantPast
    // Touched only on main.
    var lastCPU: Double?
    var spiking = false
    var lastRestart: Date?
    var passwordless = false

    func applicationDidFinishLaunching(_ note: Notification) {
        refreshPasswordless()
        render()
        sample()
    }

    func sample() {
        queue.async { [self] in
            let cpu = coreaudiodCPU()
            var restartNow = false
            var isSpiking = false
            if let cpu, cpu >= threshold {
                over += 1
                isSpiking = over >= sustainedSamples
            } else {
                over = 0
            }
            if isSpiking && Date() >= cooldownUntil {
                if autoRestart { restartNow = true; cooldownUntil = Date().addingTimeInterval(cooldown) }
            }
            if restartNow {
                over = 0
                let ok = restartCoreaudiod(interactive: false)
                DispatchQueue.main.async { if ok { self.lastRestart = Date() }; self.spiking = !ok }
            }
            DispatchQueue.main.async {
                self.lastCPU = cpu
                if !restartNow { self.spiking = isSpiking }
                self.render()
            }
            Thread.sleep(forTimeInterval: 1)
            DispatchQueue.main.async { self.sample() }
        }
    }

    func refreshPasswordless() {
        queue.async { let v = passwordlessRestartEnabled(); DispatchQueue.main.async { self.passwordless = v } }
    }

    // MARK: UI

    func render() {
        let b = item.button
        b?.title = spiking ? " ⚠︎ \(Int(lastCPU ?? 0))%" : ""
        b?.image = NSImage(systemSymbolName: spiking ? "speaker.wave.3.fill" : "speaker.wave.2",
                           accessibilityDescription: "coreaudiod watcher")
        b?.imagePosition = .imageLeading

        let m = NSMenu()
        let status = lastCPU.map { String(format: "coreaudiod CPU: %.1f%%", $0) } ?? "coreaudiod: not found"
        m.addItem(withTitle: status, action: nil, keyEquivalent: "").isEnabled = false
        if let t = lastRestart {
            let f = DateFormatter(); f.timeStyle = .medium
            m.addItem(withTitle: "Last restart: \(f.string(from: t))", action: nil, keyEquivalent: "").isEnabled = false
        }
        m.addItem(.separator())
        m.addItem(withTitle: "Restart coreaudiod now", action: #selector(restartNow), keyEquivalent: "r").target = self

        let auto = m.addItem(withTitle: "Auto-restart on spike", action: #selector(toggleAuto), keyEquivalent: "")
        auto.target = self; auto.state = autoRestart ? .on : .off

        let sub = NSMenu()
        for t in thresholds {
            let i = sub.addItem(withTitle: "≥ \(Int(t))% for \(sustainedSamples) samples", action: #selector(setThreshold(_:)), keyEquivalent: "")
            i.target = self; i.representedObject = t; i.state = t == threshold ? .on : .off
        }
        m.addItem(withTitle: "Spike threshold", action: nil, keyEquivalent: "").submenu = sub

        let pw = m.addItem(withTitle: passwordless ? "Remove passwordless restart" : "Enable passwordless restart…",
                           action: #selector(togglePasswordless), keyEquivalent: "")
        pw.target = self
        m.addItem(.separator())
        m.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = m
    }

    @objc func restartNow() {
        queue.async { [self] in
            over = 0
            cooldownUntil = Date().addingTimeInterval(cooldown)
            let ok = restartCoreaudiod(interactive: true)
            DispatchQueue.main.async { if ok { self.lastRestart = Date() }; self.render() }
        }
    }
    @objc func toggleAuto() { autoRestart.toggle(); render() }
    @objc func setThreshold(_ s: NSMenuItem) {
        if let t = s.representedObject as? Double { threshold = t; render() }
    }
    @objc func togglePasswordless() {
        let enabled = passwordless
        queue.async { [self] in
            _ = enabled ? removeSudoersRule() : installSudoersRule()
            refreshPasswordless()
            let v = passwordlessRestartEnabled()
            DispatchQueue.main.async { self.passwordless = v; self.render() }
        }
    }
}

let app = NSApplication.shared
let delegate = App()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
