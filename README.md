<p align="center"><img src="Resources/AppIcon.png" width="128" alt="PopFix icon"></p>

<h1 align="center">PopFix</h1>

<p align="center">
  Fixes the macOS crackling / popping audio bug automatically.<br>
  A free, tiny menu-bar app. Signed, notarized, MIT licensed.
</p>

<p align="center">
  <a href="https://github.com/builtby-win/macos-pop-fix/releases/latest/download/PopFix.zip"><b>⬇ Download PopFix.zip</b></a>
  &nbsp;·&nbsp; macOS 13+ &nbsp;·&nbsp; Apple Silicon
</p>

---

## The problem

On recent macOS releases and betas, audio randomly starts crackling because `coreaudiod` misses I/O deadlines ([example thread](https://www.reddit.com/r/MacOSBeta/comments/1l7wg5z/cracking_popping_sound_during_audio_playback_on/)). The known workaround is `sudo killall coreaudiod`. PopFix notices the problem and does that for you.

## Install

**Homebrew:**

```sh
brew install --cask builtby-win/tap/popfix
```

**Or manually:**

1. [Download PopFix.zip](https://github.com/builtby-win/macos-pop-fix/releases/latest/download/PopFix.zip) and unzip.
2. Drag `PopFix.app` to `/Applications` and open it.
3. Optional: System Settings → General → Login Items → add PopFix.

## Features

- **Detects pops:** counts `coreaudiod` "Audio IO Overload" log lines. No root, no private APIs, near-zero CPU.
- **Auto-restarts `coreaudiod`** when overloads cross a threshold (3 / 10 / 30 / 100 per 10s; default 10), with a 30s cooldown.
- **Pauses and resumes media** around the restart: whatever is in Now Playing (Music, Spotify, browser tabs, VLC, …) is paused, then resumed after `coreaudiod` is back.
- **Saves a diagnostic report** for every restart, ready to attach to an Apple Feedback Assistant report. Nothing is uploaded by PopFix.

## Menu

| Item | |
| --- | --- |
| Audio overloads (last 10s) | Live count; the icon shows ⚠︎ while over the threshold |
| Restart coreaudiod now | Manual restart (admin prompt unless passwordless is enabled) |
| Auto-restart on pops | Restart automatically (needs passwordless restart) |
| Pop threshold | Overloads per 10s that count as popping |
| Enable / Remove passwordless restart… | Install/remove the sudoers rule |
| Show diagnostic reports / Report to Apple… | Reveal the latest report / open Feedback Assistant |

## Privacy and permissions

- **Passwordless restart (optional):** installs `/etc/sudoers.d/macos-pop-fix`, allowing exactly `/usr/bin/killall coreaudiod` for your user (validated with `visudo -c`, removable from the same menu item). Auto-restart only ever uses `sudo -n` and never prompts for a password.
- **Now Playing:** to pause and resume media, PopFix runs a bundled [mediaremote-adapter](https://github.com/ejbills/mediaremote-adapter) helper under `/usr/bin/perl`. It needs no Automation or Accessibility permission, and Apple Silicon only.
- **Reports** are saved to `~/Library/Logs/PopFix/report-<timestamp>.txt`: macOS/build/model, load, memory pressure, top processes, and the last 3 minutes of overload events. They contain process names, so review before sharing.

## Caveats

- If something is starving the audio thread (heavy CPU/memory load), a restart clears the stuck state but the cause can bring it back. The report's "overloading clients" and top-process sections help find it.
- A restart briefly cuts audio for every app.

<details>
<summary>CLI, building from source, releasing</summary>

```sh
PopFix.app/Contents/MacOS/PopFix --probe    # print the overload rate for 20s
PopFix.app/Contents/MacOS/PopFix --report   # write a diagnostic report now, no restart
```

Build (Swift toolchain / Xcode CLT):

```sh
./build.sh && open PopFix.app
```

Signed release (hardened runtime, notarized, stapled, produces `PopFix.zip`):

```sh
./build.sh --sign "Developer ID Application: Name (TEAMID)" --notarize <notarytool-profile>
```

Create the profile once with `xcrun notarytool store-credentials`. `scripts/make-icon.sh` regenerates the app icon.

</details>

---

<p align="center">
  Built by <a href="https://github.com/builtby-win">builtby.win</a> · media control via <a href="https://github.com/ejbills/mediaremote-adapter">mediaremote-adapter</a> (BSD-3-Clause) · <a href="LICENSE">MIT</a>
</p>
