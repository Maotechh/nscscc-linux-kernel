# Board Handoff Contract: candidate `0cf30051c`

> This is the operator-facing handoff for the **refreshed, fix-carrying**
> kernel candidate. It supersedes
> [`hardware-validation-candidate-426629c84.md`](hardware-validation-candidate-426629c84.md)
> for the USB/PS-2 lanes. Candidate `426629c84` carries the
> `7407da63a` USB-enumeration regression (USB guaranteed to fail there);
> candidate `0cf30051c` contains the fix `6832b1aa4` (ue11-hcd control
> status-stage DATAx verification), so **USB enumeration is expected to
> succeed on this triple**. Do not spend a board run on `426629c84` for a
> USB proof; use this contract.

This document is the single handoff contract for evaluating kernel candidate
commit `0cf30051c` on the NSCSCC 实验箱 for the USB/PS-2 lanes.

The handoff triple is `{bitstream, vmlinux@0cf30051c, initramfs}`: the board
run is only meaningful with all three bound together and hashed as recorded
below.

## Candidate identity and scope

- kernel_commit=`0cf30051c84872edcfba69b37e008d92c82cdf15`
- base=`aa3888d6a5c658d05da518a24c26a2fbe4b678c1`, 18 commits
- Contains fix `6832b1aa4`: ue11-hcd control status-stage DATAx verification
  (USB 2.0 8.5.3 status stage always DATA1). Pre-fix, `SET_ADDRESS` (a
  zero-length control write) was rejected on the always-DATA1 status stage and
  **no USB device could enumerate** between `7407da63a` and `6832b1aa4`.
- Contains docs `727caad04` (status-stage DATA1 toggle invariant) and
  `0cf30051c` (scope correction: enumeration-fatal framing, board ask
  re-scope). `1d0de354c` re-points the old contract's banner to this
  candidate.
- UTS version string: `5.14.0-rc2-g0cf30051c848`.
- This candidate does NOT yet prove USB/PS-2 on hardware; it is the kernel
  half of that proof.

## Artifacts to transfer (the triple)

Transfer exactly the artifact bytes in `vmlinux-0cf30051c.manifest`
(`.omo/verify-035/artifacts/`; committed contract is this file). Verify TFTP
byte count and CRC32 before `bootelf`:

```text
size=13550412
sha256=12943d1a253f3fe6e6ce6dc1af86fb59d574898115ffda2045eca81e573cedf5
crc32=24c89609
entry=0xa0bb02c0
first_load=0xa0300000
tftp_address=0xa3000000
```

Source artifact paths (integration worktree, kept reproducible; re-verified
2026-08-01 after rebuild):

- `vmlinux-0cf30051c` (stripped, 13550412 bytes, sha256
  `12943d1a253f3fe6e6ce6dc1af86fb59d574898115ffda2045eca81e573cedf5`, crc32
  `24c89609`)
- `vmlinux-0cf30051c-debug` (214030760 bytes, sha256
  `08d223bf47a4d70abfc9d28320f2e83d5e9363065d7ea5e2af5b71c7f02bb60f`)
- `initramfs-0cf30051c.cpio.gz` and `-repeat.cpio.gz` (sha256
  `b2cbb5f2d27b1ab377edb884893592d9a29d48bfe98fd3baca1631a5d260aa2b`, crc32
  `24e6a2c0`, reproducible=true, repeat byte-identical)

PATH-BOUND QUALIFIER (from the manifest): the recorded hashes are bound to the
build host compiler (`host_cc=/usr/bin/gcc`, sha256
`6cb2d84ccd9fd3485d4e47ba032e626be65692601c38fad46866a6b565f3100f`) and the
source-dir path of the verify-035 canonical clean build. A rebuild on a
different host/source path is not expected to reproduce these hashes
byte-for-byte.

## Bitstream pairing

The USB Full-Speed host requires the Chiplab bitstream that includes the UE11
controller and the UART/DMFE/confreg/NT35510/peripheral set. The only recorded
board-capable USB bitstream is `soc_top-ad6551-cpu40-uncore100.bit` (sha256
`5DF92D998E9528E90FBA3F1ED44EC47473CF0C869FB6C79CFDE75E0B13A2F2A0`,
`usb-hardware-20260722.manifest`: `feature_usb=true`, `usb_address=0x1fe0c000`,
`usb_soc_interrupt=6`, DRC 0, WNS +0.011456 ns) — it has **never** been
programmed to the board.

The desktop-run `soc_top-ad6551-cpu40-uncore100-lcd-cs-h18.bit` (sha256
`4152FEAB...`) does NOT contain the UE11 USB controller (its manifest has no
`feature_usb` and zero USB strings) and must not be used for the USB proof.

There is NO recorded bitstream containing the bidirectional PS/2 controller.
That remains a CPU-lane Vivado funnel item (`nscscc-fpga-evaluate`); the
kernel lane hands over vmlinux + initramfs and requests the paired bitstream
from the CPU lane. The USB result on the `5df92d99...` bitstream is not
confounded with the PS/2 result (that bitstream carries the pre-0724
receive-only PS/2, so `atkbd` reset failure is the expected result there).

## U-Boot TFTP boot

Windows Tftpd32 root uses `10.90.50.43`; 实验箱 uses `10.90.50.44`. Only run
`bootelf` when TFTP byte count and CRC32 match the manifest:

```text
setenv ipaddr 10.90.50.44
setenv serverip 10.90.50.43
setenv netmask 255.255.255.0
setenv ethaddr 00:98:76:64:32:19
ping 10.90.50.43
tftpboot 0xa3000000 vmlinux-0cf30051c
crc32 0xa3000000 ${filesize}
bootelf -p 0xa3000000 g console=ttyS0,115200 rdinit=/init loglevel=8
```

Expected boot markers (serial, 115200 8N1):

- Linux version banner with `5.14.0-rc2-g0cf30051c848` in the version string
- `Memory: 128MiB available` region from the DTS
- initramfs unpack + `Freeing initrd memory` then BusyBox `/init`
- `/ #` prompt (login is root, no password)

Command-line precedence (verified in `arch/loongarch/kernel/setup.c` +
`drivers/of/fdt.c`): `bootcmdline_init()` runs before `platform_init()`, and
`early_init_dt_scan_chosen()` then overwrites `boot_command_line` with the
DTS `chosen/bootargs`. So `/proc/cmdline` shows the DTS bootargs
`earlycon atkbd.reset=0 psmouse.proto=bare` and NOT the `bootelf` tail args.
The bootelf tail (`console=ttyS0,115200 rdinit=/init loglevel=8`) is still
consumed as `__setup` early params from the bootloader line (this is what
produced the working serial shell on 2026-07-22, whose log shows
`Kernel command line: earlycon`), while `atkbd.reset=0` and
`psmouse.proto=bare` are parsed from `saved_command_line` during initcalls
and therefore ARE active on board. Capture `cat /proc/cmdline` and confirm
it contains both PS/2 flags.

## Evidence to capture (per lane, separate files)

### USB enumeration and HID

- `dmesg | grep -i ue11` after boot: expect platform registration, root hub,
  and `USB: port power ON` lines (probe prints at `ue11-hcd.c` `port_power`,
  `usbhw_hub_reset`).
- With the Full-Speed mouse receiver attached: expect
  `USB device connected`, then linestate dispatch
  `Full-Speed device detected` / `Low-Speed device detected`, root-hub
  connect status, then hub/urb enumeration prints.
- `lsusb` should list the receiver; `evtest` should report the HID input
  device and move events.
- Pull the receiver: expect `USB device disconnected` + root-hub disconnect
  status. Re-attach and repeat to prove re-enumeration.
- Regression target (the fix `6832b1aa4`): the first control transfers
  (GET_DESCRIPTOR device, SET_ADDRESS ZLP, SET_CONFIGURATION ZLP) must not
  produce `-EPROTO` / DATAx mismatch strikes. A clean enumeration on this
  triple is the direct on-board evidence that the `7407da63a` regression is
  resolved.
- Regression target (serialized start, pre-existing): after a port-power
  off/suspend/stop cycle, confirm `ue11h_start` re-arms under `ue11->lock`
  without racing the recovery timer, i.e. no unexpected USB writes to an
  unpowered/HALT port during re-enumeration.

### PS/2 keyboard and mouse

- `dmesg | grep -i ps2` and `dmesg | grep -i serio`: expect
  `altera_ps2` probe and serio registration.
- Keyboard: with `atkbd.reset=0`, expect `serio0: Fast keyboard connected` and
  a working `evtest` key event. Do NOT expect `0xaa BAT` unless the keyboard
  is actually reset (single-channel controller, bootargs keep reset disabled).
- Mouse: with `psmouse.proto=bare`, expect PS/2 mouse registration and
  pointer events.

**Known-negative qualifier (Opus C2):** the only board-capable USB bitstream
`5df92d99...` carries the **pre-0724 receive-only** PS/2 controller, for which
the contract already predicts `atkbd` reset failure (the bidirectional PS/2
controller was added by `chiplab-ps2-bidirectional-20260724.patch`, which has
never been built into a routed bitstream).  On any run against `5df92d99...`,
an `atkbd` reset failure / no keyboard events is the **expected known-negative
result and NOT a kernel finding** — it is a bitstream-capability result.  PS/2
board proof is recorded as **BLOCKED-NO-BITSTREAM** (a CPU-lane Vivado funnel
item via `nscscc-fpga-evaluate`), not pending-operator.  Only `altera_ps2`
probe + serio registration are kernel-lane expectations on this triple; key and
pointer events additionally require the never-built paired bitstream.

## Pass / fail criteria

- PASS = each captured serial/status log matches the expected markers above
  AND the corresponding artifact byte count + CRC32 match the manifest.
- FAIL = missing boot markers, enumeration/HID/PS-2 failure, or CRC32
  mismatch; capture the failing log and return it unchanged.

Return evidence files into this repository's
`Documentation/nscscc/evidence/` following the
`tftp-linux-desktop-*-20260722.txt` naming pattern, and note which U-Boot
CRC32 value the board reported.

## Board lane status on 2026-08-01

From the automation host, the board TFTP subnet (`10.90.50.43/44`) is not
directly reachable: TCP 22/80 time out and UDP 69 (TFTP RRQ probe) gets no
response, so on-board execution has to be run from the Windows desktop
(Tftpd32 + SecureCRT), or the board must be reachable from the automation
host. The automation host's eth0 is up (172.24.224.206) and the fpga-agent
SSH gateway (`10.20.213.157:22`) is reachable (OpenSSH for Windows 9.5) for
the CPU lane's serialized `nscscc-fpga-evaluate` workflow; this Linux
campaign has no direct board-subnet path. Until real board logs are returned,
USB and PS/2 remain unproven on hardware.

## Operator action requested — escalation (wave 1 delivered 2026-08-01, reply
## window to 2026-08-04T18:32:30Z)

This contract is the operator-facing handoff for the **USB proof on the
refreshed kernel**. The asks are:

1. **Board execution of the refreshed triple** `{bitstream, vmlinux@0cf30051c,
   initramfs}` — boot to `/ #`, capture `/proc/cmdline`, then run the USB
   enumeration + HID checks AND the PS/2 checks above. This is the direct
   on-board evidence that fix `6832b1aa4` resolves USB enumeration. Either
   run the U-Boot TFTP boot above from the Windows desktop (Tftpd32 root
   `10.90.50.43`, board `10.90.50.44`) and return the serial log into
   `Documentation/nscscc/evidence/`, or provide a jump-host / credential path
   through the reachable fpga-agent SSH gateway (`10.20.213.157:22`) so this
   host can reach the board subnet itself.
2. **Paired bitstream** containing the UE11 USB Full-Speed host AND the
   bidirectional PS/2 controller (`chiplab-usb-full-speed-20260722.patch` +
   `chiplab-ps2-bidirectional-20260724.patch` over the pinned base). No
   recorded `.bit` contains both; the CPU lane's Vivado 2023.2 funnel
   (`nscscc-fpga-evaluate`) owns this build. Record the `.bit` sha256 in
   `Documentation/nscscc/evidence/bitstream-sha256-*.txt` per that skill.
3. **USB-only partial path (cheaper intermediate, does not wait for the
   paired PS/2 bitstream):** program `soc_top-ad6551-cpu40-uncore100.bit`
   (sha256 `5DF92D998E9528E90FBA3F1ED44EC47473CF0C869FB6C79CFDE75E0B13A2F2A0`,
   `feature_usb=true`, WNS +0.011456 ns) and run the triple with `vmlinux-
   0cf30051c`; returning the serial log with `lsusb` / `evtest` evidence of a
   Full-Speed device proves the USB HCD/HID path on hardware independently of
   PS/2. PS/2 then remains the sole outstanding board item, gated only on the
   paired bitstream.

PAUSE trigger: after two delivered waves with neither a bitstream nor an
operator response, the campaign pauses and waits for operator direction
(delivery-evidence guard, iteration 046: only DELIVERED waves count).

## 08-04 decision table (written 2026-08-02, Opus checkpoint-053-056 C2)

Executed mechanically at `2026-08-04T18:32:30Z` (wave-1 reply-window expiry);
no fresh deliberation needed at the deadline:

| At 08-04 18:32:30Z | Action |
|---|---|
| Wave-1 answered (board log / bitstream returned) | Board lane resumes; interpret the returned serial log against `board-day-observation-runbook-0cf30051c.md` (corrected per C1: no suspend path). Escalation clock stops. |
| Wave-1 unanswered | Deliver **wave 2 = ONE narrowed USB ask**: program `soc_top-ad6551-cpu40-uncore100.bit` (`5DF92D99...`, `feature_usb=true`, DRC 0, WNS +0.011456 ns), TFTP-boot the `0cf30051c` triple, return the serial log (with `lsusb`/`evtest`). One bitstream, one boot, one file back. Set a fresh reply window. **Do NOT re-ask the operator for the paired PS/2 bitstream** — it cannot be produced by any operator reply. |
| Wave-2 lapses | **PAUSE the board lane only** (`board_lane_paused` control-plane event): stop re-asking, mark the lane `BLOCKED-AWAITING-OPERATOR` (USB) / `BLOCKED-NO-BITSTREAM` (PS/2), with no further waves. Local lanes continue. |

**PAUSE semantics (defined 2026-08-02, pre-deadline):** PAUSE means *board-lane
pause*, not campaign stop.  It does not contradict the campaign objective: it
stops re-asking an unresponsive operator and marks the board lane
`BLOCKED-AWAITING-OPERATOR` (USB proof, operator action) and
`BLOCKED-NO-BITSTREAM` (PS/2 proof, CPU-lane Vivado build), while local lanes
with real verification capability continue.  The two blockers behind
"USB/PS-2 board proof" are NOT the same blocker: USB is operator-blocked against
an existing never-programmed DRC-clean bitstream; PS/2 is blocked on a bitstream
that has never been built and must be re-routed to the CPU-lane
`$nscscc-fpga-evaluate` Vivado funnel (different queue, different owner,
different skill).
