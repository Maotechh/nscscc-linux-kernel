# Board Handoff Contract: candidate `426629c84`

> ## ⚠ KNOWN DEFECT IN THIS CANDIDATE (added 2026-08-01, checkpoint-045-048)
>
> **USB enumeration is guaranteed to fail on `vmlinux@426629c84`.** The
> regression `7407da63a` made the HCD reject the always-DATA1 control
> status stage against the pipe-keyed data toggle; because `SET_ADDRESS` is
> itself a zero-length (ZLP) control write whose OUT toggle slot stays 0, no
> USB device could enumerate between `7407da63a` and the fix `6832b1aa4`.
> Candidate `426629c84` is an ancestor of `7407da63a` and does **not**
> contain `6832b1aa4` (verified by `git merge-base --is-ancestor`).
>
> **Do not spend a board run on this triple expecting USB to work.** Until a
> rebuilt `vmlinux` containing `6832b1aa4` is released (artifacts pending
> refresh), treat **ask #1 as a serial-shell / PS-2 proof only** — boot the
> triple, confirm the `/ #` shell, capture `/proc/cmdline`, and run the PS/2
> checks. Any `lsusb` / `evtest` / USB-enumeration expectation on this
> candidate is void, and a USB failure here must be attributed to the known
> stale kernel bytes, NOT to the RTL or bitstream. The USB proof is deferred
> to the refreshed candidate containing `6832b1aa4`.

This document is the single handoff contract for evaluating kernel candidate
commit `426629c84` on the NSCSCC 实验箱. It supersedes
`hardware-validation-candidate-0de802777.md` (and in turn
`hardware-validation-candidate-40ed6223c.md`) for the USB/PS-2 lanes when the
on-board evidence below is captured and returned.

The handoff triple is `{bitstream, vmlinux@426629c84, initramfs}`: the board
run is only meaningful with all three bound together and hashed as recorded
below.

## Candidate identity and scope

- kernel_commit=`426629c84341021c5e00fbe0e11b8d6ed3e9507c`
- base=`aa3888d6a5c658d05da518a24c26a2fbe4b678c1`, 16 commits
- This candidate = `0de802777` + the host-compiler reproducibility fix
  (`608939906`) + the `ue11h_start` power-on serialization under `ue11->lock`
  (`426629c84`). It does NOT yet prove USB/PS-2 on hardware.
- Divergence from `0de802777`: entry moved `0xa0bb0270 -> 0xa0bb02e0` and the
  canonical artifact hash changed (see below) because `426629c84` adds the
  `ue11h_start` lock and because the embedded initramfs `build-info` now
  records `KERNEL_SOURCE_COMMIT=426629c84`. The verify-034 working-tree build
  (`46cba84d...`) was a pre-commit artifact and is NOT the handoff artifact.
- HEAD divergence note (checkpoint-037-040, Opus M2): the handoff triple is
  bound to `426629c84`. Since then the kernel lane advanced to integration
  HEAD `d00c32bb3`; the only kernel-source delta over that range is
  `83f53d429` (behavior-neutral `WARN_ON(timer_pending(&ue11->timer))` in
  `ue11h_start`, +8/-0, USB HCD compiled out of the QEMU lane). This does not
  change the handoff artifacts: `vmlinux@426629c84` hash
  `57423cb6...`/crc32 `55c70e55` and the embedded initramfs
  `0c18889c...` remain the binding triple for the board run.

## Artifacts to transfer (the triple)

Transfer exactly the artifact bytes in `vmlinux-426629c84.manifest`
(`Documentation/nscscc/evidence/`). Verify TFTP byte count and CRC32 before
`bootelf`:

```text
size=13550412
sha256=57423cb616358ee47822f99d67f238319fd3f09a0dfdeb960ecdfe4ba896cc32
crc32=55c70e55
entry=0xa0bb02e0
first_load=0xa0300000
tftp_address=0xa3000000
```

Source artifact paths (integration worktree, kept reproducible):

- `vmlinux-426629c84` (stripped, 13550412 bytes, sha256
  `57423cb616358ee47822f99d67f238319fd3f09a0dfdeb960ecdfe4ba896cc32`, crc32
  `55c70e55`)
- `vmlinux-426629c84-debug` (214029944 bytes, sha256
  `4616efcb3045a78e8129bf62aaca9a5eb7d63eb7cb19ac543bce466db7d87f99`)
- `initramfs-426629c84.cpio.gz` and `-repeat.cpio.gz` (sha256
  `0c18889c0e4f340cb754b49becdd8cecac6c2e9a1ba71752887016b74ddeb2c6`, crc32
  `4899a0b9`, reproducible=true)

PATH-BOUND QUALIFIER (from the manifest): the recorded hashes are bound to the
build host compiler (`host_cc=/usr/bin/gcc`, sha256
`6cb2d84ccd9fd3485d4e47ba032e626be65692601c38fad46866a6b565f3100f`) and the
source-dir path of the verify-035 canonical clean build. A rebuild on a
different host/source path is not expected to reproduce these hashes
byte-for-byte.

## Bitstream pairing (Opus finding B, unresolved)

The USB Full-Speed host requires the Chiplab bitstream that includes the UE11
controller and the UART/DMFE/confreg/NT35510/peripheral set. The only recorded
on-board bitstream lineage is the desktop run set, whose `soc_top-ad6551-
cpu40-uncore100-lcd-cs-h18.bit` (sha256 `4152FEAB85D893ACDE9B37004BE9E37DCF7
1562A58E93DCDCFB85FE2CA33E39D`) PREDATES the bidirectional PS/2 patch. There
is NO recorded bitstream containing the bidirectional PS/2 controller that was
simulated in the CPU lane. Until a bitstream with the UE11 controller AND the
bidirectional PS/2 controller is produced by the CPU lane
(`nscscc-fpga-evaluate`) and recorded in
`Documentation/nscscc/evidence/bitstream-sha256-*.txt`, this contract cannot
claim full USB+PS/2 on-board proof. The kernel lane hands over vmlinux +
initramfs and REQUESTS the paired bitstream from the CPU lane.

## U-Boot TFTP boot

Windows Tftpd32 root uses `10.90.50.43`; 实验箱 uses `10.90.50.44`. Only run
`bootelf` when TFTP byte count and CRC32 match the manifest:

```text
setenv ipaddr 10.90.50.44
setenv serverip 10.90.50.43
setenv netmask 255.255.255.0
setenv ethaddr 00:98:76:64:32:19
ping 10.90.50.43
tftpboot 0xa3000000 vmlinux-426629c84
crc32 0xa3000000 ${filesize}
bootelf -p 0xa3000000 g console=ttyS0,115200 rdinit=/init loglevel=8
```

Expected boot markers (serial, 115200 8N1):

- Linux version banner with `426629c84` in `Kernel command line`
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
- Regression target (the serialized start): after a port-power off/suspend/
  stop cycle, confirm `ue11h_start` re-arms under `ue11->lock` without
  racing the recovery timer, i.e. no unexpected USB writes to an
  unpowered/HALT port during re-enumeration and no lock-free concurrent
  `port_power` access.

### PS/2 keyboard and mouse

- `dmesg | grep -i ps2` and `dmesg | grep -i serio`: expect
  `altera_ps2` probe and serio registration.
- Keyboard: with `atkbd.reset=0`, expect `serio0: Fast keyboard connected` and
  a working `evtest` key event. Do NOT expect `0xaa BAT` unless the keyboard
  is actually reset (single-channel controller, bootargs keep reset disabled).
- Mouse: with `psmouse.proto=bare`, expect PS/2 mouse registration and
  pointer events.

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
campaign has no direct board-subnet path. Until real board logs are
returned, USB and PS/2 remain unfixed. This iteration's canonical clean
build at committed HEAD is recorded in
`Documentation/nscscc/evidence/vmlinux-426629c84.manifest`
(verify-035, sha256 `57423cb6...`, crc32 `55c70e55`).

## Operator action requested — escalation wave 1 of 2 (2026-08-01T03:10:21Z)

This contract is the single operator-facing handoff. Three asks are open; the
campaign will record a second wave, then PAUSE if none is satisfied.

1. **Board execution of the triple** `{bitstream, vmlinux@426629c84,
   initramfs}`. **RE-SCOPED (checkpoint-045-048): this candidate carries the
   known `7407da63a` USB-enumeration regression (see banner above), so this
   ask is a serial-shell / PS-2 proof only** — boot to `/ #`, capture
   `/proc/cmdline`, and capture the PS/2 checks below. Do not expect USB
   enumeration on this candidate. Either run the U-Boot TFTP boot above from
   the Windows desktop (Tftpd32 root `10.90.50.43`, board `10.90.50.44`) and
   return the serial log into `Documentation/nscscc/evidence/`, or provide a
   jump-host / credential path through the reachable fpga-agent SSH gateway
   (`10.20.213.157:22`, OpenSSH for Windows 9.5) so this host can reach the
   board subnet itself. The USB enumeration proof moves to the refreshed
   candidate containing `6832b1aa4` (rebuild in progress).
2. **Paired bitstream** containing the UE11 USB Full-Speed host AND the
   bidirectional PS/2 controller (`chiplab-usb-full-speed-20260722.patch` +
   `chiplab-ps2-bidirectional-20260724.patch` over the pinned base). No
   recorded `.bit` contains both; the CPU lane's Vivado 2023.2 funnel
   (`nscscc-fpga-evaluate`) owns this build. Record the `.bit` sha256 in
   `Documentation/nscscc/evidence/bitstream-sha256-*.txt` per that skill.
3. **USB-only partial path (cheaper intermediate, does not wait for the
   paired PS/2 bitstream):** the recorded USB-capable bitstream is
   `soc_top-ad6551-cpu40-uncore100.bit` (sha256
   `5DF92D998E9528E90FBA3F1ED44EC47473CF0C869FB6C79CFDE75E0B13A2F2A0`,
   `usb-hardware-20260722.manifest`: `feature_usb=true`, `usb_address=
   0x1fe0c000`, `usb_soc_interrupt=6`, DRC 0, WNS +0.011456 ns) — the ONLY
   recorded artifact containing the UE11 USB Full-Speed controller, and it
   has NEVER been programmed to the board. CORRECTION (checkpoint-037-040,
   Opus M1): the desktop-run `soc_top-ad6551-cpu40-uncore100-lcd-cs-h18.bit`
   (sha256 `4152FEAB...`) does NOT contain the UE11 USB controller — its
   manifest has no `feature_usb` and zero USB strings. Running the triple
   `{soc_top-ad6551-cpu40-uncore100.bit 5df92d99..., vmlinux@426629c84,
   initramfs}` and returning the serial log with `lsusb` / `evtest` evidence
   of a Full-Speed device would prove the USB HCD/HID path on hardware
   independently of PS/2. This satisfies the escalation's USB half without
   the paired bitstream; PS/2 then remains the sole outstanding board item,
   gated only on the paired bitstream. Note: that bitstream carries the
   pre-0724 receive-only PS/2 (atkbd reset failure is the expected result
   there), so the USB result is not confounded with the PS/2 result.

PAUSE trigger: after two waves with neither a bitstream nor an operator
response, the campaign pauses and waits for operator direction.

## Delivery-evidence guard (iteration 046, closes checkpoint-037-040 / DS
## checkpoint-041-044 #1)

Only a DELIVERED wave counts toward the two-wave PAUSE trigger. "Delivered"
means this host recorded an `escalation_wave_delivered` event in
`events.jsonl` with a delivery timestamp when the wave was written to the
operator-facing contract (not merely when the campaign asked itself).

- Each wave increments the count only after `escalation_wave_delivered` is
  recorded with `at`, `wave` (1 or 2), `ask_count`, and `reply_window_expires_at`.
- Reply window: the operator has until `reply_window_expires_at` (set at
  delivery, default 72h from delivery timestamp) to satisfy or decline any
  ask. An undelivered or unacknowledged wave does not advance the PAUSE count.
- The campaign does not PAUSE on its own filing cabinet: if the two recorded
  waves are undelivered (no delivery events), the escalation is re-sent (new
  delivery timestamp) instead of pausing.
- A new escalation (fresh wave numbering) is opened if the operator changes
  the asks or the contract content; prior delivered waves still count unless
  explicitly reset in the same event stream.
- Operator responses are recorded as `escalation_wave_satisfied` (with the
  satisfied ask id and returned evidence path) or `escalation_declined`; a
  satisfied or declined ask reduces the open-ask count and is not re-sent.
