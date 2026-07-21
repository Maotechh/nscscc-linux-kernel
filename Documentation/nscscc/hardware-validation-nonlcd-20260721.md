# Non-LCD Linux hardware validation, 2026-07-21

## Scope and identities

- GitHub main baseline: `4d7c9e9776106573df6fe736c8588f2a2529c407`.
- Kernel source: `556d59af05d75f05e3f4a080d61f70a19c030635`.
- CPU source: `ad6551afe009652b5562f200bd0d76f641d56a76`.
- The CPU remains pure SpinalHDL. The selected bitstream contains generated
  `mycpu_top.v` with SHA256
  `e2de0240d136f7f0d8097165b96cc919dddd4580fbacef2fafbaa7d96cb3f4b1`.
- Chiplab base: `a2e11b38bc5c85abb4408a8e0c0f5ce903c7ba31`.
- Kernel artifact: `vmlinux-556d59af0-nonlcd`, 16286568 bytes, SHA256
  `e69044c0b6ea577bc6e494a19107eafd7a83da32e16cb11ac58a52c299bf5342`,
  CRC32 `caf16247`.
- Bitstream: `soc_top-ad6551-cpu40-uncore100-display-ps2-final.bit`, 9730756
  bytes, SHA256
  `ceef87d7003d406c0d1e894ada46262940186de20191feda23124212bae8d38d`.

The complete identity set is in
`evidence/vmlinux-556d59af0-nonlcd.manifest`. The build used the official
x86-64 LoongArch32 Reduced GCC 8.3 toolchain. The debug ELF was preserved
separately with SHA256
`2bb3cc49b8e49cd1fd33fffec5d2d334f5f0d9533a1918526ad62a032cace26a`.

## Reproducible userspace

BusyBox commit `db726ae0c61ffec6b58e19749e0c63aaaf4f6989` produced the static
binary with SHA256
`72827c680b3b2afd73fd64d7ca99137e92019a6539527fa453c570ee616e1fff`.
The initramfs was built twice with `SOURCE_DATE_EPOCH=0`; both 4220071-byte
files had SHA256
`12bd089a0c156345c9afb2b9ced5ea7a0cecdfba2497adc709405990034c0fad`
and `cmp` returned zero. The bytes embedded in the kernel had the same hash.

## Windows preflight

- Ethernet link `Up` at 100 Mbps, interface index 3.
- Host address `10.90.50.43/24`.
- Tftpd32 bound to `10.90.50.43`, UDP port 69 listening.
- One Tftpd32 process, zero SecureCRT processes, and zero Vivado processes.
- Windows TFTP artifact size and SHA256 matched the manifest.
- The SecureCRT script passed VBScript syntax parsing after its two
  SecureCRT metadata lines were removed for `cscript.exe`.

## Hardware run 1

- Vivado 2023.2 exit `0`, FPGA startup status `HIGH`, and the expected
  `PROGRAMMED=` marker.
- U-Boot ping succeeded. TFTP transferred 16286568 bytes in 59 seconds with
  zero resent blocks. Board CRC32 was `caf16247`.
- Linux banner, initramfs `/init`, and the shell prompt appeared. Physical
  memory was reported as 131072K and `MemTotal` was 115596 kB.
- `/proc/cpuinfo` reported processor 0, the LoongArch32 Reduced ISA, PRID,
  address sizes, TLB information, and CPU features.
- DMFE carrier was 1, RX/TX error counters stayed zero, all three pings
  returned, and the DMFE interrupt count increased from 53 to 69.
- Confreg input reads, LED and seven-segment writes, and the character-device
  read completed successfully.
- Direct signal delivery and timer-driven signal return completed.
- With no PS/2 keyboard attached, the controller probed and its interrupt
  count stayed at zero. The kernel error scan found no panic, Oops, BUG, or
  call trace.
- Terminal status: `result=success`.

## Hardware run 2

- Vivado 2023.2 exit `0`, FPGA startup status `HIGH`, and the expected
  `PROGRAMMED=` marker.
- U-Boot ping succeeded. TFTP transferred 16286568 bytes in 59 seconds with
  zero resent blocks. Board CRC32 was `caf16247`.
- Linux banner, 128 MiB physical memory, initramfs `/init`, shell, build-info,
  and non-empty `/proc/cpuinfo` checks passed.
- DMFE carrier was 1, RX/TX error counters stayed zero, all three pings
  returned, and the DMFE interrupt count increased from 52 to 70.
- Confreg, signal, timer signal, idle PS/2, and kernel error checks passed.
- Terminal status: `result=success`.

The `check-linux-runs.py` validator accepted both status logs against the
final manifest. LCD operation was deliberately excluded from this validation.
No keyboard was attached, so PS/2 key events remain untested. The evidence
does not claim CPU performance, LCD output, persistent storage, USB, or audio
support.
