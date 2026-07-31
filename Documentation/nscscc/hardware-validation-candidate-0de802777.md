# Board Handoff Contract: candidate `0de802777`

This document is the single handoff contract for evaluating kernel candidate
commit `0de802777` on the NSCSCC 实验箱. It supersedes
`hardware-validation-candidate-40ed6223c.md` for the USB/PS-2 lanes only
when the on-board evidence below is captured and returned.

Candidate identity and scope:

- kernel_commit=`0de802777ff3729b486178e203b5ff6d48f28998`
- base=`aa3888d6a5c658d05da518a24c26a2fbe4b678c1`, 16 commits, kernel
  source diff 3 files (`ue11-hcd.c`, `altera_ps2.c`, `loongson32_ls.dts`),
  +165/-39
- This candidate = `40ed6223c` plus the stale-recovery-timer guard and PM
  `port_power` serialization (`f2e9458da`). It does NOT yet prove USB/PS-2
  on hardware.

## Artifacts to transfer

Transfer exactly the artifact bytes in `vmlinux-0de802777.manifest`
(`Documentation/nscscc/evidence/`). Verify TFTP byte count and CRC32 before
`bootelf`:

```text
size=13550412
sha256=6ceacb50e228c9fabe4d133484bbff824a690a3e4daa0d2a6b21cd65a70b469f
crc32=3e1d4b5c
entry=0xa0bb0270
first_load=0xa0300000
tftp_address=0xa3000000
```

Source artifact paths (integration worktree, kept reproducible):

- `vmlinux-0de802777` (stripped, 13550412 bytes)
- `vmlinux-0de802777-debug` (214028620 bytes, sha256
  `5c239d657d78d29a675ecf9b1f443294bbb4251eb2d266543480c0a464cbb567`)
- `initramfs-0de802777.cpio.gz` and `-repeat.cpio.gz` (sha256
  `9d04051239456c0169ae72d535dd60e7d4b53a3a8e78af749c5c2726beb14854`,
  reproducible=true)

## U-Boot TFTP boot

Windows Tftpd32 root uses `10.90.50.43`; 实验箱 uses `10.90.50.44`. Only run
`bootelf` when TFTP byte count and CRC32 match the manifest:

```text
setenv ipaddr 10.90.50.44
setenv serverip 10.90.50.43
setenv netmask 255.255.255.0
setenv ethaddr 00:98:76:64:32:19
ping 10.90.50.43
tftpboot 0xa3000000 vmlinux-0de802777
crc32 0xa3000000 ${filesize}
bootelf -p 0xa3000000 g console=ttyS0,115200 rdinit=/init loglevel=8
```

Expected boot markers (serial, 115200 8N1):

- Linux version banner with `0de802777` in `Kernel command line`
- `Memory: 128MiB available` region from the DTS
- initramfs unpack + `Freeing initrd memory` then BusyBox `/init`
- `/ #` prompt (login is root, no password)

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
- Regression target (the guard): after a port-power off/suspend/stop cycle,
  confirm no spurious `mod_timer`/recovery activity from a stale
  `ue11h_timer` epoch, i.e. no unexpected USB writes to an unpowered/HALT
  port after power-off.

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

## Board lane status on 2026-07-31

From the automation host, the board TFTP subnet (`10.90.50.43/44`) is not
directly reachable: TCP 22/80 time out and UDP 69 (TFTP RRQ probe) gets no
response, so on-board execution has to be run from the Windows desktop
(Tftpd32 + SecureCRT), or the board must be reachable from the automation
host. The automation host's eth0 is up (172.24.224.206) and the fpga-agent
SSH gateway (`10.20.213.157:22`) is reachable (OpenSSH for Windows 9.5) for
the CPU lane's serialized `nscscc-fpga-evaluate` workflow; this Linux
campaign has no direct board-subnet path. Until real board logs are
returned, USB and PS/2 remain unfixed per audit advice
`20260731T141815Z-5b0043f9`. The committed evidence set for this candidate
is `c036cdb91` (initramfs x2 + manifest + this contract) on top of
`0de802777`.
