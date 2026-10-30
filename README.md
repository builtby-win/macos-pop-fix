# macos-pop-fix

Menu-bar app that watches `coreaudiod` CPU and restarts it when it spikes (the crackling/popping audio bug on recent macOS).

- Samples `coreaudiod` CPU every ~2s via `/usr/bin/top` (it runs as `_coreaudiod`, so unprivileged APIs can't read it).
- Fires after 3 consecutive samples ≥ threshold (default 30%, menu-configurable), then runs `killall coreaudiod` (30s cooldown).
- Restart needs root: uses `sudo -n` if you enabled **Enable passwordless restart…** (installs a sudoers rule for exactly `killall coreaudiod`), else prompts for admin password.
- Menu: live CPU, restart now, auto-restart toggle, threshold.

```sh
./build.sh && open PopFix.app
.build/release/PopFix --probe   # print 5 CPU readings, for tuning the threshold
```
