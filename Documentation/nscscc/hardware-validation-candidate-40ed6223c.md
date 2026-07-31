# Board Handoff Contract: candidate `40ed6223c`

This document is the single handoff contract for evaluating kernel candidate
commit `40ed6223c` on the NSCSCC 实验箱. It supersedes the "未连接实验箱"
caveat for the USB/PS-2 lanes only when the on-board evidence below is
captured and returned.

Candidate identity and scope:

- kernel_commit=`40ed6223c66b0ff8ab24ab8db27da8302db0abac`
- base=`aa3888d6a5c658d05da518a24c26a2fbe4b678c1`, 13 commits, diff 3 files
  (`ue11-hcd.c`, `altera_ps2.c`, `loongson32_ls.dts`), +109/-12
- Relevant bootargs in `arch/loongarch/boot/dts/loongson/loongson32_ls.dts`:
  `earlycon atkbd.reset=0 psmouse.proto=bare`
- This candidate adds the `atkbd.reset=0` flag (readiness: resolved per
  Opus review C1) and normalizes ue11-hcd tab indentation. It does NOT yet
  prove USB/PS-2 on hardware.

## Artifacts to transfer

Transfer exactly the artifact bytes in `vmlinux-40ed6223c.manifest`
(`Documentation/nscscc/evidence/`). Verify TFTP byte count and CRC32 before
`bootelf`:

```text
size=13550412
sha256=b565fda1137328ff6f85eec5a0653932d140d48b1f0101c80aa1f1faeaf40382
crc32=b63f1d89
entry=0xa0bb0250
first_load=0xa0300000
tftp_address=0xa3000000
```

Source artifact paths (integration worktree, kept reproducible):

- `vmlinux-40ed6223c` (stripped, 13550412 bytes)
- `vmlinux-40ed6223c-debug` (214027964 bytes, sha256
  `fc2009c0a992c62b13f4b8eefba58ffccbbee74f224eec2629e3ec334575978c`)
- `initramfs-40ed6223c.cpio.gz` and `-repeat.cpio.gz` (sha256
  `82b5e4f7cc4d54b038941d335354a1f010398e303acbf63ee15189e793f87215`,
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
tftpboot 0xa3000000 vmlinux-40ed6223c
crc32 0xa3000000 ${filesize}
bootelf -p 0xa3000000 g console=ttyS0,115200 rdinit=/init loglevel=8
```

Expected boot markers (serial, 115200 8N1):

- Linux version banner with `40ed6223c` in `Kernel command line`
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

From the automation host, TFTP probe of `10.90.50.43/44:69` got no response
and ARP has no entry for the board subnet; only `169.254.1.1` and
`10.15.166.34` are visible. On-board execution therefore has to be run from
the Windows desktop (Tftpd32 + SecureCRT), or the board must be reachable
from the automation host. Until real board logs are returned, USB and PS/2
remain unfixed per audit advice `20260731T141815Z-5b0043f9`.
