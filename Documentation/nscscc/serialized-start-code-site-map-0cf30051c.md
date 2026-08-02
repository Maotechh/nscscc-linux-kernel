# Serialized-start regression target: code-site map (candidate `0cf30051c`)

Companion to `board-day-observation-runbook-0cf30051c.md` and
`hardware-validation-candidate-0cf30051c.md`.  Maps the serialized-start
regression target (contract "Regression target (serialized start,
pre-existing)") to exact source sites at HEAD `12cec7ed2` (line numbers below
match that commit).  Read-only analysis; no behaviour change.

Target in contract terms: after a port-power off / suspend / stop cycle,
confirm `ue11h_start` re-arms under `ue11->lock` without racing the recovery
timer, i.e. no unexpected USB writes to an unpowered/HALT port during
re-enumeration.

## The recovery timer and its epoch

- `struct ue11.timer` (`ue11-hcd.c:228`), armed with `mod_timer()` in two
  places: `ue11h_hub_control` `USB_PORT_FEAT_RESET` (50 ms, line 1776) and
  `ue11h_timer` Phase 1 re-arm (20 ms, line 1604).
- `ue11->reset_recovery` (`ue11-hcd.c:238`) gates the disconnect suppress
  inside `ue11_update_connection_locked` (`ue11-hcd.c:894`, reset_recovery use
  at line 920).

## Serialized-start invariant

`ue11h_start` (`ue11-hcd.c:1840`) asserts `WARN_ON(timer_pending(&ue11->timer))`
(line 1854) then runs `port_power(ue11, 1)` under `ue11->lock` (1856-1858).
The comment documents the invariant: first start runs right after
`timer_setup()` in probe (never armed); every restart is preceded by
`ue11h_stop()` / suspend, which both `del_timer_sync()`.

**Observation:** `ue11h_stop` (`ue11-hcd.c:1825`) does `del_timer_sync` on
both `hcd->rh_timer` and `ue11->timer` (1830-1831) BEFORE taking the lock and
calling `port_power(ue11, 0)` (1833-1835).  `ue11h_bus_suspend`
(`ue11-hcd.c:1800`) is a no-op: it only emits a debug log and returns 0.  It
does NOT `del_timer_sync`, does NOT clear `USB_PORT_STAT_POWER`, and does NOT
set `hcd->state = HC_STATE_HALT`.  Consequently, if the USB core ever calls
`bus_suspend` while the 50/20 ms recovery timer is armed, the callback still
runs — and because the port is still powered and the HCD still running, the
stale-timer guard below is NOT guaranteed to reject it (it may continue through
Phase 1/2).  The guard only guarantees suppression AFTER a transition has
cleared POWER or set HALT (port-power off, `ue11h_stop`, or the platform
suspend path); plain `ue11h_bus_suspend` currently does neither.

**Reachability scope (Opus checkpoint-053-056 C1, verified statically
2026-08-02):** this open question is **unreachable on the board-bound
candidate** and is retained only for a future `CONFIG_PM=y` configuration.
`ue11h_bus_suspend`/`ue11h_bus_resume` are inside `#ifdef CONFIG_PM`
(`ue11-hcd.c:1796-1821`); with `CONFIG_PM` unset the driver takes the `#else`
arm and defines them `NULL` (1818-1819), and `ue11h_suspend`/`ue11h_resume`
are likewise `NULL` (2057-2058).  `CONFIG_PM` is NOT set in the board-bound
build: the `.config` (sha256
`e4565246f1d3fb28a703bcaa22b4416bb27249802876b3cc292fa8f55135ff09`, matching
`kernel_config_sha256` in `vmlinux-0cf30051c.manifest`) has no `CONFIG_PM=y`,
no `CONFIG_SUSPEND`/`CONFIG_PM_SLEEP`/`CONFIG_HIBERNATION`; `CONFIG_PM` is
undefined in `autoconf.h`; and `nm vmlinux-0cf30051c-debug` shows zero
`ue11h_*suspend/resume` and zero `hcd_bus_suspend`/`hcd_bus_resume`/
`usb_remote_wakeup` symbols (USB-core PM compiled out too; sanity: 63828 total
symbols, 92 matching `suspend` elsewhere).  So on the board-bound triple the
USB core **cannot** invoke `ue11h_bus_suspend`, root-hub autosuspend is off
(`drivers/usb/core/hub.c:1830` tests `drv->bus_suspend && drv->bus_resume`,
both NULL), and no suspend path can execute.  The 056/057 analysis remains
correct at source level and is re-scoped here, not deleted.

## Stale-timer guard (the actual race stopper)

`ue11h_timer` (`ue11-hcd.c:1555`) re-validates port state under the lock before
touching the controller (1573-1578):

```c
if (!(ue11->port1 & USB_PORT_STAT_POWER) ||
    hcd->state == HC_STATE_HALT) {
    ue11->reset_recovery = 0;
    spin_unlock_irqrestore(&ue11->lock, flags);
    return;
}
```

This is the guard that makes a late armed timer benign after a transition has
cleared POWER or set HALT (port-power off, `ue11h_stop`, or the platform
suspend path): it clears `reset_recovery` and returns without any register
write, so no USB write reaches an unpowered/HALT port.  A pending timer across
plain `ue11h_bus_suspend` is NOT covered, because that callback leaves POWER
set and `hcd->state` running.

## port_power transition handling

`port_power` (`ue11-hcd.c:451`):

- Power-on transition (460-474): no-op if already powered (protects an
  in-epoch redundant `SetPortFeature(POWER)`); on genuine transition clears
  `reset_recovery`, resets `port1 = USB_PORT_STAT_POWER`, `irq_enable = 0`.
- Power-off (475-486): clears `reset_recovery`, `port1 = 0`,
  `irq_enable = 0`, `hcd->state = HC_STATE_HALT`.
- Both branches `mdelay(20)` (488) then `usbhw_hub_enable(ue11, 1, 0)` /
  `usbhw_hub_reset(ue11)` (490-498) and write `USB_IRQ_MASK` (500).

## Timer phases in ue11h_timer

- Phase 1 (1580-1608): `USB_PORT_STAT_RESET` still set → de-assert SE0,
  present ENABLE early, clear RESET, set `reset_recovery = 1`, re-arm 20 ms.
- Phase 2 (1610-1662): drive HiZ + SOF gated per 7.1.7.5, sample raw
  linestate, run `ue11_update_connection_locked`, set/clear ENABLE, set
  `C_RESET`, clear `reset_recovery`, write `USB_IRQ_MASK`, then
  `usb_hcd_poll_rh_status`.
- The `mod_timer` re-arm (1604) uses `msecs_to_jiffies(20)` (5 jiffies at
  CONFIG_HZ=250) to guarantee the 10 ms 7.1.7.5 floor.

## URB guard

`ue11h_urb_enqueue` (`ue11-hcd.c:1246`) rejects with `-ENODEV` when
`!(port1 & USB_PORT_STAT_ENABLE) || !HC_IS_RUNNING(hcd->state)` (1286-1293),
so URBs cannot reach an unpowered/HALT port either.

## Observable markers for the board lane (serialized-start)

- `ue11h_stop` / `ue11h_start` lifecycle produces `USB: port power OFF` /
`USB: port power ON` (line 456) via `port_power`.
- A stray armed timer after a power-off would hit the guard silently (no print);
  absence of a WARN is the expected good signal.  A
  `WARN_ON(timer_pending(&ue11->timer))` firing at `ue11h_start` would print a
  stack trace — that is the direct failure signature to capture.
- `USB: post-reset raw-linestate=0x%x` / `post-reset port=...` (1623/1644)
  confirm Phase 2 ran against a powered port.
- `USB: port power OFF` (power-off/stop) followed by a second
  `USB: port power ON` (re-arm) is the serialized-start cycle to script on the
  board (e.g. power-cycle the receiver, or unplug/replug).
- **NOT a board signature on this candidate (C1):** there is no suspend path to
  observe — `CONFIG_PM` is unset, `ue11h_bus_suspend`/`ue11h_bus_resume`/
  `ue11h_suspend`/`ue11h_resume` are all `NULL` in the image, and root-hub
  autosuspend is disabled.  Do NOT script `echo suspend >/sys/.../usb_hcd` or
  watch for a WARN at restart after suspend; that expectation was dropped from
  the board-day runbook.  The serialized-start cycle on this triple is limited
  to power-off/stop (disconnect/reconnect or driver unbind/rebind).

## Conclusion

The serialized-start invariant is structurally sound at HEAD: `ue11h_stop`
cancels the timer, `ue11h_start` WARNs on a pending timer, `port_power` clears
`reset_recovery` on every transition, and the timer callback re-validates
power/HALT state before any register write.  The former open question
(whether `ue11h_bus_suspend`, which does no `del_timer_sync`, can be invoked
with a pending recovery timer) is **unreachable on this candidate**: `CONFIG_PM`
is unset in the board-bound config, all four suspend/resume callbacks are `NULL`
in the image, and root-hub autosuspend is off.  The analysis is retained,
re-scoped to a future `CONFIG_PM=y` configuration.
