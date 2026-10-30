import AppKit
import UserNotifications

/// Diagnostics saved at each restart, meant to be attached to an Apple Feedback Assistant report.
/// Nothing is uploaded; the user reviews and submits it.
enum Report {
    static let dir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/PopFix", isDirectory: true)
    static let feedbackAssistant = URL(fileURLWithPath: "/System/Library/CoreServices/Applications/Feedback Assistant.app")

    static func newURL() -> URL {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        return dir.appendingPathComponent("report-\(f.string(from: Date())).txt")
    }

    private static func out(_ path: String, _ args: [String]) -> String {
        run(path, args).out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Cheap system state. Capture BEFORE restarting so it reflects what the user was hearing.
    static func snapshot() -> String {
        let pressure = ["1": "normal", "2": "warn", "4": "critical"]
        let level = out("/usr/sbin/sysctl", ["-n", "kern.memorystatus_vm_pressure_level"])
        let top = run("/bin/ps", ["-Aro", "pid,%cpu,%mem,comm"]).out.split(separator: "\n").prefix(16)
        return [
            "macOS: \(out("/usr/bin/sw_vers", ["-productVersion"])) (\(out("/usr/bin/sw_vers", ["-buildVersion"])))",
            "model: \(out("/usr/sbin/sysctl", ["-n", "hw.model"]))",
            "loadavg: \(out("/usr/sbin/sysctl", ["-n", "vm.loadavg"]))",
            "memory pressure: \(pressure[level] ?? level)",
            "top processes by CPU:",
        ].joined(separator: "\n") + "\n" + top.joined(separator: "\n")
    }

    private static func tally(_ lines: [Substring], pattern: String) -> String {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return "" }
        var counts: [String: Int] = [:]
        for l in lines {
            let s = String(l)
            if let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
               let r = Range(m.range(at: 1), in: s) {
                counts[String(s[r]), default: 0] += 1
            }
        }
        return counts.sorted { $0.value > $1.value }.prefix(8).map { "  \($0.value)x \($0.key)" }.joined(separator: "\n")
    }

    /// Slow (seconds): reads the unified log, so run after the restart.
    static func write(to url: URL, reason: String, count: Int, action: String, snapshot: String) {
        let pred = "process == \"coreaudiod\" AND (eventMessage CONTAINS \"Audio IO Overload\" OR eventMessage CONTAINS \"HostApplicationDisplayID\")"
        let log = run("/usr/bin/log", ["show", "--last", "3m", "--style", "compact", "--predicate", pred]).out
            .split(separator: "\n", omittingEmptySubsequences: true)
        let overloads = log.filter { $0.contains(OverloadWatcher.marker) }
        let analytics = log.filter { $0.contains("HostApplicationDisplayID") }
        let f = ISO8601DateFormatter()

        var s = """
        PopFix report \(f.string(from: Date()))
        Trigger: \(reason); \(count) coreaudiod IO overloads in the last \(Int(window))s at capture time.
        Action: \(action)

        Review before sharing. PopFix never uploads this. To report: open Feedback Assistant
        (Menu > Report to Apple…), choose Sound/Audio, and attach this file.

        == System ==
        \(snapshot)

        == coreaudiod log, last 3 min (restart does not clear it) ==
        overload events: \(overloads.count)
        overloading clients (HostApplicationDisplayID):
        \(tally(analytics, pattern: "\"HostApplicationDisplayID\": ([^,\"]+)"))
        causes:
        \(tally(analytics, pattern: "\"cause\": ([A-Za-z,]+)"))

        """
        if let one = analytics.first { s += "\nsample analytics message:\n\(one)\n" }
        s += "\nfirst overload events:\n" + overloads.prefix(15).joined(separator: "\n")
        s += "\n\nlast overload events:\n" + overloads.suffix(15).joined(separator: "\n") + "\n"

        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? s.write(to: url, atomically: true, encoding: .utf8)
    }

    static func latest() -> URL? {
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.lastPathComponent.hasPrefix("report-") }.max { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// Opens Feedback Assistant and reveals the newest report to drag in.
    static func reportToApple() {
        NSWorkspace.shared.open(feedbackAssistant)
        revealLatest()
    }

    static func revealLatest() {
        if let u = latest() { NSWorkspace.shared.activateFileViewerSelecting([u]) }
        else { try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true); NSWorkspace.shared.open(dir) }
    }
}

enum Notifier {
    static func authorize() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func post(_ title: String, _ body: String, reveal: URL? = nil) {
        let c = UNMutableNotificationContent()
        c.title = title
        c.body = body
        if let reveal { c.userInfo = ["report": reveal.path] }
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
    }
}
