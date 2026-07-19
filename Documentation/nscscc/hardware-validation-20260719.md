# NSCSCC Linux hardware validation, 2026-07-19

## Result

The final kernel artifact, built with reproducible BusyBox and initramfs
inputs, completed two independent FPGA boot runs. Each run began by
programming the FPGA, downloaded the kernel through TFTP, checked the image
CRC32 in U-Boot, entered the initramfs shell, and completed the Linux hardware
checks. Both status logs end with `result=success`.

## Artifacts

FPGA configuration:

* CPU source commit: `ad6551afe009652b5562f200bd0d76f641d56a76`
* Bitstream: `soc_top-ad6551-cpu40-uncore100-spi25-final.bit`
* Bitstream SHA256:
  `9dc36fa4803f12dab16999f2afd7ea8d6731e54d8415a878335535478e3bff45`
* Vivado 2023.2 reported startup status `HIGH` and the expected programmed
  file name.

Bootloader source:

* `la32r-uboot` commit:
  `1b96e814fc158eed611d95795e6c26b812ae6f40`
* The bootloader in SPI provided the `u-boot@LoongsonSoC#` prompt at 115200
  baud in both runs.

Userspace:

* BusyBox source commit:
  `db726ae0c61ffec6b58e19749e0c63aaaf4f6989`
* BusyBox config SHA256:
  `71f6ee381f177f4722c522753f79095a571ec22637ee222d0ca9219b0b5f9975`
* BusyBox binary size: `2305144`
* BusyBox binary SHA256:
  `72827c680b3b2afd73fd64d7ca99137e92019a6539527fa453c570ee616e1fff`
* Two clean BusyBox builds were byte-for-byte identical.
* Initramfs SHA256:
  `16f278d2abbb933661032f333250752a1c4291a08c21bafbed84bb0667b52b16`
* Two initramfs builds were byte-for-byte identical.

Kernel:

* Source commit: `db7abacb8820fd0ca5212e2930d74118be7d8a8e`
* TFTP file: `vmlinux-db7abacb8-repro`
* Size: `16252992`
* SHA256:
  `b0571e60b8860fabdfa0bbdd41f2d3c7269083e71bb09ccc3b392e3f1769f6ae`
* CRC32: `424073b5`
* ELF: ELF32 LoongArch
* Entry and `kernel_entry`: `0xa0b84c70`
* First PT_LOAD: `0xa0300000`
* PT_LOAD end: `0xa12fc284`
* TFTP buffer: `0xa3000000` through `0xa3f8003f`
* Exclusive DDR end: `0xa8000000`
* EPYC2 path:
  `/home/geekpie/work/linux-bringup-db7abacb-20260719/artifacts/nscscc-repro/vmlinux-db7abacb8-repro`
* Windows TFTP path:
  `C:\Users\Henry\fpga-lab\diagnostic\linux\tftp-root\vmlinux-db7abacb8-repro`

## Host configuration

The experiment-box Ethernet interface was connected directly to Windows. The
Windows interface used `10.90.50.43/24`, reported `Up` at 100 Mbps, and kept
the Wi-Fi interface available for SSH. Tftpd32 4.50 listened on UDP port 69 at
`10.90.50.43`. The board used `10.90.50.44/24`.

The Tftpd32 log records the two final requests:

* Run 1: `16252992` bytes in 59 seconds, `0 blk resent`.
* Run 2: `16252992` bytes in 60 seconds, `0 blk resent`.

U-Boot reported the same byte count and calculated CRC32 `424073b5` over
`0xa3000000 ... 0xa3f8003f` in both runs.

## Linux observations

Both runs reported:

* `Linux nscscc-la32r 5.14.0-rc2-gdb7abacb8820`.
* `131072K` physical memory and `MemTotal: 115628 kB` after reservations.
* `/init` executed from the embedded initramfs.
* `eth0` was `UP,LOWER_UP` with `10.90.50.44/24` and carrier `1`.
* Initial network counters were RX `15`, TX `8`, RX errors `0`, TX errors `0`.
* Three ICMP packets were transmitted and received, with 0 percent loss.
* The `eth0` interrupt counter increased from `20` to `41` during the network
  test, and the global interrupt error count remained `0`.
* The DMFE driver reported 100 Mbps full duplex.
* The board utility read switches `0x000000F6`, buttons `0x00000000`, and step
  buttons `0x00000000`.
* LED write `0x0000a55a` and seven-segment write `0x20260719` succeeded.

Run 1 ping RTT min/avg/max was `2.053/2.756/4.120 ms`. Run 2 was
`2.076/2.786/3.983 ms`.

## Evidence

Final run 1:

* `evidence/tftp-linux-net-status-20260719-195619.txt`
* `evidence/tftp-linux-net-serial-20260719-195619.txt`

Final run 2:

* `evidence/tftp-linux-net-status-20260719-200205.txt`
* `evidence/tftp-linux-net-serial-20260719-200205.txt`

Supporting evidence:

* `evidence/tftpd32-transfer-20260719.log`
* `evidence/vivado-program-final-second-20260719.txt`
* `evidence/busybox-repro-c.manifest`
* `evidence/initramfs-repro-repeat.log`
* `evidence/vmlinux-db7abacb8-repro.manifest`

The VBScript Boolean value `True` is written as `-1`; therefore
`linux_banner=-1` and `linux_shell=-1` in the status files are successful
checks.

## Confreg migration validation

The portable part of the DFPMTS patch was integrated as a device-tree platform
driver instead of a forced `obj-y` object.  The driver is selected by
`CONFIG_CHIPLAB_CONFREG=y` and provides the original character device plus
sysfs attributes for the LED, RGB LED, seven-segment display, switches,
buttons, timer, frequency, and grouped register views.  The initramfs
`nscscc-board` command uses these sysfs attributes and falls back to `devmem`
when the driver is absent.

The migration artifact was built from the same kernel commit in a separate
EPYC2 worktree:

* TFTP file: `vmlinux-db7abacb8-confreg`
* Size: `16232468`
* SHA256:
  `83d5b557105d5c515218c5cdcf2e9c04a39600591491ba31b8e6c1196a386f83`
* CRC32: `e62f945e`
* Initramfs SHA256:
  `4e9b1747813660e1ef315f240d587a1d8a6f71baeec9e919a0c7f1959468b03e`
* Entry and `kernel_entry`: `0xa0b859f0`
* First PT_LOAD: `0xa0300000`
* PT_LOAD end: `0xa12fc284`
* TFTP buffer end: `0xa3f7b014`

The first migration boot reached Linux and verified the driver, but the
existing three-packet BusyBox ping command was terminated by `Alarm clock`
after one reply.  The follow-up diagnostic run passed three independent
single-packet pings.  After changing the automation to three single-packet
checks, two independent runs from FPGA reprogramming through TFTP and Linux
ended with `result=success`.  The successful migration checks observed:

* `/sys/class/chiplab_confreg/chiplab_confreg/device_info` reported physical
  base `0x1fd0e000` and character device `249:0`.
* `all_inputs` reported switches `0xf6`, buttons `0x0000`, step `0x00`, and
  the hardware frequency register `33000000Hz`.
* `nscscc-board led 0x0000a55a` and `nscscc-board display 0x20260719`
  returned successfully; sysfs readback was `0xa55a` and `0x20260719`.
* `dd if=/dev/chiplab_confreg bs=4 skip=1024 count=1` read back `0000a55a`.
* `eth0` counters had zero RX and TX errors, and the DMFE interrupt count
  increased during the network checks.

Migration evidence:

* `evidence/tftp-linux-net-status-20260719-223956.txt`
* `evidence/tftp-linux-net-serial-20260719-223956.txt`
* `evidence/tftp-linux-net-status-20260719-225109.txt`
* `evidence/tftp-linux-net-serial-20260719-225109.txt`
* `evidence/tftp-linux-net-status-20260719-230409.txt`
* `evidence/tftp-linux-net-serial-20260719-230409.txt`
* `evidence/linux-diagnostic-status-20260719-224526.txt`
* `evidence/linux-diagnostic-serial-20260719-224526.txt`
* `evidence/vmlinux-db7abacb8-confreg.manifest`
* `evidence/chiplab-confreg-compile.log`
* `evidence/vivado-program-confreg-second-20260719.txt`
* `evidence/vivado-program-confreg-second-exit-20260719.txt`
