# Board-day observation runbook: candidate `0cf30051c`

Companion to `hardware-validation-candidate-0cf30051c.md`. This runbook maps
every observable kernel log marker for the USB (UE11 HCD) and PS/2
(`altera_ps2`) lanes to the exact source site at HEAD, so a captured serial
log can be interpreted without guessing. It is read-only analysis; it does not
change kernel behaviour or the board-bound artifact.

Reference tree: `drivers/usb/host/ue11-hcd.c`, `drivers/input/serio/altera_ps2.c`,
`arch/loongarch/loongson32/irq.c`, `arch/loongarch/boot/dts/loongson/loongson32_ls.dts`.

## IRQ wiring (what "works" on the fallback dispatcher)

`loongson32_ls.dts`:

- `ps2@1fe04000` (`altr,ps2-1.0`), reg `<0x1fe04000 0x8>`, interrupt `<7>`
- `usb0@1fe0c000` (`ultraembedded,usb-host-fs`), reg `<0x1fe0c000 0x1000>`, interrupt `<8>`

`arch/loongarch/loongson32/irq.c` `mach_irq_dispatch()`:

- `pending & ECFGF_IP5` (bit 5) -> `do_IRQ(LOONGSON_CPU_IRQ_BASE + ECFGB_IP5)` (`+7`)
- `pending & ECFGF_IP6` (bit 6) -> `do_IRQ(LOONGSON_CPU_IRQ_BASE + ECFGB_IP6)` (`+8`)

So DTS interrupt `7` = ESTAT bit 5 -> PS/2, interrupt `8` = ESTAT bit 6 -> USB.
The CPU is programmed for IP5/IP6 via the `cpuic` irqdomain; `arch_init_irq()`
masks everything then `setup_IRQ()` enables the domain. If a driver IRQ never
fires on the board, check that `dmesg | grep irq` shows both `ps2` and `ue11`
successfully `request_irq`-ed, and that no `mach_irq_dispatch` bit mapping
changed.

## Log-level gating: which prints actually exist in this kernel

`ue11-hcd.c:38-47` sets `USBLOG_LEVEL = USBLOG_ERR` (1). `USB_LOG(l, ...)`
prints only when `l <= USBLOG_LEVEL`, so **all `USBLOG_INFO(3)`, `USBLOG_REQ(2)`
and `USBLOG_DATA(4)` prints are compiled out**. Only `USBLOG_ERR` and the
unconditional `dev_info`/`dev_warn`/`pr_info` prints are present. Expecting a
print that is compiled out (e.g. `HW: Enable root hub`, `USB: URB queue`,
`Debug: SETUP PACKET`, `STAT:`/`RESP:`) is a false negative: do not mark the
lane failed just because those lines are absent.

## USB lane: marker -> source site

All `dev_`/`pr_` prints are unconditional; the `USB_LOG(USBLOG_ERR, ...)`
prints are present because `USBLOG_ERR` <= `USBLOG_LEVEL`.

### Boot / probe

| marker | source site | meaning |
|---|---|---|
| `ue11h_probe` registration | platform probe | device tree match OK |
| `V0.5 controller at %pa, IRQ %d; low-speed devices unsupported` | `ue11-hcd.c:1983` | probe success; `%pa` = `0x1fe0c000`, IRQ 8 |
| `USB: port power ON` | `ue11-hcd.c:455` `port_power()` | port power asserted; also `OFF` on power-down |
| `HW: Enter USB bus reset` | `ue11-hcd.c:378` `usbhw_hub_reset()` | bus reset entered |

### Enumeration (the fix `6832b1aa4` regression target)

Expected ordering after a Full-Speed receiver is attached:

| marker | source site | meaning |
|---|---|---|
| `USB: port power ON` | `ue11-hcd.c:455` | power asserted before reset |
| `HW: Enter USB bus reset` | `ue11-hcd.c:378` | reset drives SE0 |
| `USB: post-reset raw-linestate=0x%x` | `ue11-hcd.c:1623` | raw UTMI linestate after 3 samples; `1`=FS-J, `2`=FS-K |
| `Full-Speed device detected` | `ue11-hcd.c:947` | linestate FS-J, connection set, `LOW_SPEED` cleared |
| `Low-Speed device detected but unsupported by the SIE` | `ue11-hcd.c:952` | linestate FS-K (Low-Speed); device will fail to transfer |
| `USB: post-reset port=0x%x conn=%d enable=%d low_speed=%d` | `ue11-hcd.c:1644` | port state after recovery epoch; expect `conn=1 enable=1 low_speed=0` |
| `usb 1-1: new full-speed USB device number %d` | USB core | USB core enumerates |
| `usb 1-1: New USB device found, idVendor=...` | USB core | descriptor read completed |
| hub/USB core messages (`input: ... as ...`, `hid-generic`, `hidraw%d`) | USB core + HID | receiver bound to HID |

The fix `6832b1aa4` specifically protects the first control transfers
(GET_DESCRIPTOR, SET_ADDRESS ZLP, SET_CONFIGURATION ZLP). A clean
`new full-speed USB device` + `New USB device found` with **no** error markers
below is the direct on-board proof that the `7407da63a` regression is gone.

### Error markers (present at ERR level; their absence = good)

| marker | source site | meaning |
|---|---|---|
| `USB: DATAx mismatch ep=%02x exp=%d got=%d` | `ue11-hcd.c:1013` | control/data phase toggle error |
| `USB: STALL (sts=%x)!` | `ue11-hcd.c:1121` | device stalled the transfer |
| `USB: Timeout %d (sts=%x)!` | `ue11-hcd.c:1128,1139` | transaction timed out |
| `USB: Isochronous transfers not supported` | `ue11-hcd.c:1265` | reject isochronous (expected, unsupported) |
| `Low-Speed transfer rejected: controller SIE is Full-Speed only` | `ue11-hcd.c:1272` | a Low-Speed device was addressed (see below) |
| `ep %p not empty?` | `ue11-hcd.c:1485` | URB queued on non-empty endpoint |
| `USB: Giving up on transfer....` | `ue11-hcd.c:1448` | endpoint fault after error budget |

### hub_control feature prints (unconditional `pr_info`)

`ue11h_hub_control` prints each requested feature (lines 1703/1712/1754/1757/1769):
`USB_PORT_FEAT_ENABLE (DISABLE)`, `USB_PORT_FEAT_SUSPEND (RESUME)`,
`USB_PORT_FEAT_SUSPEND (SUSPEND)`, `USB_PORT_FEAT_POWER (power on)`,
`USB_PORT_FEAT_RESET`. Their presence shows USB core is driving root-hub
features; order should be power-on -> reset -> (suspend/resume during
re-enumeration cycles).

## PS/2 lane: marker -> source site

`altera_ps2.c` prints:

| marker | source site | meaning |
|---|---|---|
| probe `base %p, irq %d` | `altera_ps2.c` probe | platform match; `base`=`0x1fe04000`, IRQ 7 |
| `could not request IRQ %d` | `altera_ps2.c` probe | IRQ claim failed; check IP5 dispatch |
| `port opened` | `altera_ps2.c` port_open | serio opened by atkbd/psmouse |

Follow-up markers come from the serio/input layer, not the driver:
`serio0: Fast keyboard connected` (atkbd, requires `atkbd.reset=0` bootarg) and
`psmouse` registration (requires `psmouse.proto=bare` bootarg). Do NOT expect
`0xaa BAT`: bootargs keep reset disabled on the single-channel controller.

## Decision table for the operator

- PASS USB = `V0.5 controller at ...` + `port power ON` + `post-reset
  raw-linestate=0x1` + `Full-Speed device detected` + core
  `new full-speed USB device` + `New USB device found` + `lsusb` lists the
  receiver + `evtest` shows input events, with no `DATAx mismatch`/`STALL`/
  `Timeout` during enumeration.
- PASS PS/2 = `altera_ps2` probe + `serio0: Fast keyboard connected` /
  psmouse registration + `evtest` events.
- FAIL = missing boot markers, enumeration/HID/PS-2 failure, `-EPROTO`/DATAx
  strikes, or CRC32 mismatch. Capture the failing serial log unchanged into
  `Documentation/nscscc/evidence/` following the `tftp-linux-desktop-*-20260722.txt`
  naming pattern and note the U-Boot CRC32.
- False-negative trap: markers gated out by `USBLOG_LEVEL=ERR` (INFO/REQ/DATA
  level prints) are absent by construction and are NOT failures.

## Rebuild note (only if a code change is ever accepted)

If a future iteration needs the INFO/DATA prints for board triage, rebuild with
`USBLOG_LEVEL = USBLOG_INFO`/`USBLOG_DATA` at `ue11-hcd.c:45`, produce a new
artifact manifest, and re-enter the board funnel; the current triple is locked
to `USBLOG_ERR` and must not be silently rebuilt.
