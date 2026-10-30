# macos-pop-fix

Menu-bar app that detects the coreaudiod crackling/popping bug on recent macOS and restarts coreaudiod.

- Watches coreaudiod's `Audio IO Overload` log lines (one per missed I/O deadline, i.e. an audible pop) via `log stream`; no root needed. During a real popping episode: ~10 overloads/s, ~600/min, vs 0 when clean.
- Flags pops at >= N overloads per 10s (default 10; menu: 3/10/30/100). CPU is not used: coreaudiod sat ~20% while popping but that is a side effect of system load.
- Auto-restart is off by default. When on, it only uses passwordless `sudo -n killall coreaudiod` (30s cooldown) and never prompts. "Restart now" prompts for admin if needed. **Enable passwordless restart…** installs a sudoers rule for exactly `killall coreaudiod`.
- Menu: live overload count, restart now, auto-restart toggle, threshold.
- `.build/release/PopFix --probe` prints the overload rate for 20s.

```sh
./build.sh && open PopFix.app
.build/release/PopFix --probe   # print 5 CPU readings, for tuning the threshold
```
