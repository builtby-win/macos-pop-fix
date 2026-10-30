<p align="center"><img src="Resources/AppIcon.png" width="128" alt="PopFix icon"></p>

# PopFix

A tiny macOS menu-bar app that detects the **crackling / popping audio bug** (`coreaudiod` missing I/O deadlines, seen on recent macOS betas and releases, e.g. [this thread](https://www.reddit.com/r/MacOSBeta/comments/1l7wg5z/cracking_popping_sound_during_audio_playback_on/)), restarts `coreaudiod` for you, and saves a diagnostic report you can attach to an Apple Feedback Assistant report.

Restarting `coreaudiod` (`sudo killall coreaudiod`) is the known workaround. PopFix just notices when you need it.

## How it works

- **Detection:** streams `coreaudiod`'s unified-log lines `Audio IO Overload thread: …` via `log stream`. Each line is one missed I/O deadline, i.e. one audible pop. No root, no private APIs, near-zero CPU. On an affected machine this logged ~10 overloads/s while popping and 0 when clean.
- **Trigger:** ≥ N overloads in a 10s window (default 10; menu: 3 / 10 / 30 / 100).
- **Not CPU-based:** `coreaudiod` CPU rises while popping, but it's a symptom of system load, so it's a poor trigger.
- **Restart:** `killall coreaudiod` needs root.
  - *Restart coreaudiod now* prompts for your admin password.
  - *Auto-restart on pops* (off by default) only uses passwordless `sudo -n` and never prompts. Enable it once via *Enable passwordless restart…*, which installs `/etc/sudoers.d/macos-pop-fix` allowing exactly `/usr/bin/killall coreaudiod` for your user (validated with `visudo -c`; removable from the same menu item). 30s cooldown.
- **Notification + report:** each restart posts a notification and writes `~/Library/Logs/PopFix/report-<timestamp>.txt` containing macOS/build/model, load average, memory pressure, top CPU processes, and a summary of the last 3 minutes of `coreaudiod` overload events (which client app was overloading, causes, sample lines). Clicking the notification reveals the file.
- **Reporting to Apple:** *Report to Apple…* opens Feedback Assistant and reveals the newest report to attach. PopFix never uploads anything itself; review the file first (it contains process names).

## Install

Needs macOS 13+. Download the signed, notarized `PopFix.zip` from [Releases](../../releases), unzip, move `PopFix.app` to `/Applications`, open it.

Or build from source (Swift toolchain / Xcode CLT):

```sh
./build.sh && open PopFix.app
```

To launch at login: System Settings → General → Login Items → add PopFix.

## Menu

| Item | |
| --- | --- |
| Audio overloads (last 10s) | live count; the icon shows ⚠︎ and the count while over the threshold |
| Restart coreaudiod now | manual restart (admin prompt unless passwordless is enabled) |
| Auto-restart on pops | restart automatically (needs passwordless restart) |
| Pop threshold | overloads per 10s that count as popping |
| Enable / Remove passwordless restart… | install/remove the sudoers rule |
| Show diagnostic reports / Report to Apple… | reveal latest report / open Feedback Assistant |

## CLI

```sh
PopFix.app/Contents/MacOS/PopFix --probe    # print the overload rate for 20s
PopFix.app/Contents/MacOS/PopFix --report   # write a diagnostic report now, no restart
```

## Release builds

```sh
./build.sh --sign "Developer ID Application: Name (TEAMID)" --notarize <notarytool-profile>
```

Signs with the hardened runtime, notarizes, staples, and produces `PopFix.zip`. Create the profile once with `xcrun notarytool store-credentials`. `scripts/make-icon.sh` regenerates the app icon.

## Caveats

- If the pops are caused by something starving the audio thread (heavy CPU/memory load), restarting `coreaudiod` clears the stuck state but the cause can bring it back. The report's "overloading clients" and top-process sections are there to help find it.
- Restarting `coreaudiod` briefly cuts audio for every app.

MIT licensed.
