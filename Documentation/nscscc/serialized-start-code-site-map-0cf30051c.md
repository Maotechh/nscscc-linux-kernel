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
(`ue11-hcd.c:1800`) is a no-op (SOFs off only, returns 0) — it does NOT
`del_timer_sync`.  If the USB core ever calls `bus_suspend` while the 50/20 ms
recovery timer is armed, the timer callback still runs; it is protected only by
the stale-timer guard below, not by timer cancellation.  Worth checking whether
the core actually issues `bus_suspend` with a pending reset on this stack.

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

This is the guard that makes a late armed timer benign after a power-off /
suspend / stop cycle: it clears `reset_recovery` and returns without any
register write, so no USB write reaches an unpowered/HALT port.

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
- `USB: port power OFF` (power-off/suspend/stop) followed by a second
  `USB: port power ON` (re-arm) is the serialized-start cycle to script on the
  board (e.g. `echo suspend >/sys/.../usb_hcd`, power-cycle the receiver, or
  unplug/replug).

## Conclusion

The serialized-start invariant is structurally sound at HEAD: `ue11h_stop`
cancels the timer, `ue11h_start` WARNs on a pending timer, `port_power` clears
`reset_recovery` on every transition, and the timer callback re-validates
power/HALT state before any register write.  The single open question is
whether `ue11h_bus_suspend` (no `del_timer_sync`) can be invoked with a pending
recovery timer on this stack; that is a board-observable scenario, not a
static defect.
