# macos-pop-fix

Menu-bar app that watches `coreaudiod` CPU and restarts it when it spikes (the crackling/popping audio bug on recent macOS).

- Samples `coreaudiod` CPU every ~3s via `/usr/bin/top` (it runs as `_coreaudiod`, so unprivileged APIs can't read it).
- Flags a spike after 5 consecutive samples ≥ threshold (default 10%; menu: 8/10/15/30). Measured on an affected MBP: ~20% sustained while popping. `kAudioDeviceProcessorOverload` did not fire.
- Auto-restart is off by default. When on, it only uses passwordless `sudo -n killall coreaudiod` (30s cooldown) and never prompts. "Restart now" prompts for admin if needed. **Enable passwordless restart…** installs a sudoers rule for exactly `killall coreaudiod`.
- Menu: live CPU, restart now, auto-restart toggle, threshold.

```sh
./build.sh && open PopFix.app
.build/release/PopFix --probe   # print 5 CPU readings, for tuning the threshold
```
