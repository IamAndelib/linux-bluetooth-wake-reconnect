# Linux Bluetooth Wake Reconnect

Fixes Bluetooth audio devices that reconnect after a restart but not after
waking from sleep, on KDE Plasma.

## Install

```bash
git clone https://github.com/IamAndelib/linux-bluetooth-wake-reconnect.git
cd linux-bluetooth-wake-reconnect
./install.sh
```

Run it as your normal user, without `sudo`. Then connect your device, put the
PC to sleep and wake it. The device should reconnect within a few seconds.

To remove it, run `./uninstall.sh`.

## Do you have this bug?

You probably do if all of these are true:

- You use KDE Plasma, which manages Bluetooth through bluedevil.
- Your device reconnects at login but not after sleep.
- Your adapter gets re-initialized on every wake. USB adapters are the usual
  case. Check by running this right after a wake:

  ```bash
  journalctl --user -b -g 'Reached target bluetooth.target' -n 5
  ```

  You should see a new entry at the time of the wake.

If your adapter isn't re-initialized on wake, this fix never runs after a wake,
so it won't help. Installing it is still harmless.

## The cause

Before sleep, bluedevil saves the list of connected devices. On wake it tries
to reconnect them. On affected systems, the adapter is gone at that moment:

```
14:29:41.615  bluetoothd tears down the adapter
14:29:41.622  USB reset of the adapter
14:29:41.648  "resume" signal arrives, which triggers bluedevil's reconnect
14:29:42.205  adapter is back, too late
```

Bluedevil finds no matching device, skips it and never retries. When the adapter
returns, it only restores the power state, not connections. BlueZ settings like
`ResumeDelay` don't help because the adapter itself was re-created.

At login the adapter is already running, which is why restarts work.

## The fix

A systemd user service runs each time `bluetooth.target` is reached, which
happens when the adapter comes back. It waits for the adapter to power on, then
connects the devices on bluedevil's saved list, retrying up to 5 times each.

| Situation | What it does |
|---|---|
| Device already connected | Nothing |
| You disconnected the device before sleep | Leaves it disconnected |
| Bluetooth is turned off | Nothing |
| Device off or out of range | Gives up after about 2 minutes and logs a failure |

It also runs at login alongside bluedevil. They read the same list, and if they
overlap you may see a harmless `br-connection-busy` line in the log. If you've
set bluedevil's login behaviour to something other than "Remember", it only acts
once the machine has slept since booting. The exception is logging out and back
in after a sleep: at that point it may reconnect from the list saved at that sleep.

It only works on KDE Plasma because it relies on bluedevil's saved list.

## Troubleshooting

```bash
journalctl --user -u bt-reconnect -b
```

A line ending in `connected` means it worked, and any `busy` lines before it are
fine. `could not be reconnected` means the device didn't respond, which is
expected if it was off or out of range.

## What gets installed

- `~/.local/bin/bt-reconnect`
- `~/.config/systemd/user/bt-reconnect.service`

No root access, background process or system-wide changes.

## Tests

```bash
./tests/test_bt_reconnect.sh
```

The tests use a fake `bluetoothctl`, so they don't touch your Bluetooth devices.

## Related

[linux-suspend-instant-wake-fix](https://github.com/IamAndelib/linux-suspend-instant-wake-fix)
fixes a different sleep problem: the machine waking up right after going to sleep.

## License

MIT. See [LICENSE](LICENSE).
