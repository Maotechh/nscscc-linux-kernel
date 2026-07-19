# Display and PS/2 hardware validation, 2026-07-20

## Scope and identities

- Kernel source: `db7abacb8820fd0ca5212e2930d74118be7d8a8e`.
- CPU source: `ad6551afe009652b5562f200bd0d76f641d56a76`.
- The CPU is pure SpinalHDL. The Chiplab build used the generated
  `mycpu_top.v` with SHA256
  `e2de0240d136f7f0d8097165b96cc919dddd4580fbacef2fafbaa7d96cb3f4b1`.
- Chiplab base: `a2e11b38bc5c85abb4408a8e0c0f5ce903c7ba31`.
- Kernel artifact: `vmlinux-db7abacb8-display-ps2-evdev`, 16286576 bytes,
  SHA256 `68498149d0ede8840851804deb642592f04940d76c5d10ee2c0b605c15fca4b3`,
  CRC32 `d2b95f90`.
- Bitstream: `soc_top-ad6551-cpu40-uncore100-display-ps2-final.bit`,
  9730756 bytes, SHA256
  `ceef87d7003d406c0d1e894ada46262940186de20191feda23124212bae8d38d`.

The complete identity set is in
`evidence/vmlinux-db7abacb8-display-ps2-evdev.manifest`.
The six-file Chiplab integration patch is
`evidence/chiplab-display-ps2-20260720.patch`, with SHA256
`c45fd7b1468b8ec60c011418d878847482a71d63f0d0b81d87a512a97cc631ae`.
It passes `git apply --check` against the recorded Chiplab base commit.

## System integration

- PS/2 controller: APB `0x1fe04000`, SoC interrupt input 7, Linux IRQ 23.
- NT35510 parallel LCD adapter: APB `0x1fe08000`.
- NAND remains at `0x1fe78000`.
- CPU clock: 40 MHz. Uncore clock: 100 MHz.
- Vivado 2023.2, `xc7a200tfbg676-2`.
- Final implementation: WNS `0.063450 ns`, TNS `0`, DRC errors `0`.

The PS/2 RTL supports receive FIFO, odd parity checking, host-to-device
commands, and interrupts. The NT35510 adapter converts APB accesses to the
experiment-box parallel LCD interface. These are Chiplab peripherals and do
not add handwritten CPU RTL.

## Functional ELF

The official `nscscc_func` ELF was transferred through TFTP and started with
`bootelf -p`:

- size: 544264 bytes;
- SHA256: `c5482259e2f48c76b8a667de71af11b96bf73bbb4d0494ef379e86a79b4b984e`;
- host and board CRC32: `9c1eff19`.

The final result is reported only on the physical seven-segment display. No
panel observation was recorded, so this evidence proves that the ELF started
but does not claim that `3A00003A` was observed.

## Linux run 1

- FPGA startup status `HIGH`, programming exit `0`.
- TFTP: 16286576 bytes in 59 seconds, zero retransmitted blocks.
- Board CRC32: `d2b95f90`.
- Kernel banner and shell checks passed.
- `MemTotal`: 115596 kB from the 128 MiB physical DDR map.
- DMFE interrupt count increased from 29 to 49, with `ERR: 0`.
- `/dev/nt35510` was created; a 768000-byte write completed.
- PS/2 probed at IRQ 23. With no keyboard attached, the interrupt count
  remained zero before and after network traffic.
- Terminal status: `result=success`.

## Linux run 2

- FPGA startup status `HIGH`, programming exit `0`.
- TFTP: 16286576 bytes in 52 seconds, zero retransmitted blocks.
- Board CRC32: `d2b95f90`.
- Kernel banner and shell checks passed.
- `MemTotal`: 115596 kB.
- DMFE interrupt count increased from 25 to 36, with `ERR: 0`.
- `/dev/nt35510` was created; a 768000-byte write completed.
- PS/2 interrupt count remained zero without an attached keyboard.
- Terminal status: `result=success`.

The skill validator accepted both status logs against the final manifest.
Keyboard event input and a visual LCD image check remain attachment-dependent
tests.
