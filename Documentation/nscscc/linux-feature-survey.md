# NSCSCC Linux feature survey and implementation order

## Contest requirements

The 2026 team competition rules assign 15 points to starting Linux and 20
points to starting Linux and completing the specified operations. The rules
list the following board resources: Artix-7 FPGA, 128 MiB DDR3, 4 MiB SPI
flash, one RS-232 UART, eight seven-segment digits, and eight switches. The
rules do not define the final specified Linux operations yet.

The implementation therefore needs a repeatable boot procedure and observable
operations on the board's actual devices. Features that require unrelated SoC
controllers are not part of the initial implementation.

## Public implementations

### NOP-Processor

NOP-Core, NOP-PMON and NOP-Linux were used for the 2023 team competition. The
published system includes precise exceptions, address translation, interrupts,
PMON boot, an initramfs, BusyBox, DMFE, NAND, PS/2 input and Xilinx display
drivers. Its root filesystem also contains `ip`, `ifconfig`, `route`, `ping`,
`udhcpc` and `tftp`.

The BusyBox and network setup are relevant here. NOP's PS/2, framebuffer and
NT35510 drivers depend on NOP-specific hardware and cannot be transferred to
the current SoC without adding the corresponding controllers.

### gmlayer0 and official la32r-Linux

The public history includes LA32 DMA support, DMFE fixes, LS1A NAND support,
cache maintenance, SoC UART and GMAC interrupt corrections, kernel modules,
loop devices, Btrfs, file locking, inotify and IKCONFIG. The current
`la32_defconfig` already contains the applicable features, including DMFE,
MII, LS1A NAND, modules, loop, Btrfs, file locking, inotify and IKCONFIG.
These changes should not be copied again.

### LainChip

LainChip demonstrates an ext4 root filesystem on SD, Xilinx framebuffer, USB,
I2S and ALSA audio. These features depend on LainSoC SD, video, USB and audio
controllers. They are useful references only if equivalent hardware is added
to the current FPGA design.

### DFPMTS ysyx-workbench la32r-linux

This branch is a CPU development workspace rather than a Linux kernel fork.
Its Linux work is mainly CPU support: CSR behavior, precise exceptions, MMU,
TLB and page-table walking, cache behavior, external interrupts, UART input
and FPGA integration. It does not provide a more complete Linux userspace or
additional drivers for the current experiment box.

DFPMTS also supplied separate Linux and Buildroot patches. Their kernel
menuconfig differs from `la32_defconfig` mainly by enabling PS/2 and framebuffer
support for custom controllers. Most of the additional behavior is implemented
by hardware-specific source changes. The Buildroot configuration provides a
richer local userspace, but contains non-portable paths and incompatible target
choices. See `dfpmts-linux-buildroot-analysis.md` for the exact comparison and
adoption decisions.

## Current hardware and software

The current Chiplab system integration contains DDR3, UART, DMFE Ethernet, SPI
flash, `confreg`, PS/2, an NT35510 data path, a framebuffer and one
UltraEmbedded Full-Speed USB host. `confreg` connects the switches, buttons,
LEDs and seven-segment display. The device tree contains nodes for these
implemented controllers. The NAND node remains disabled because Linux NAND
operation has not been validated on the selected FPGA system.

Kernel commit `db7abacb8820fd0ca5212e2930d74118be7d8a8e` has already reached a
BusyBox shell on the FPGA. The observed kernel reports 128 MiB DDR, `ttyS0`
and `eth0`. TFTP transfer and host-side CRC32 verification have also passed.
Linux network transmit and receive, DMFE interrupts, switches, buttons, LEDs,
the seven-segment display, and the migrated confreg platform driver have been
verified on the FPGA. Later recorded runs also verified the NT35510-sized write,
framebuffer ABI, X.Org, Fluxbox, XTerm and an idle PS/2 controller. These tests
do not prove physical LCD output or attached input events. See the
`hardware-validation-*.md` reports and their raw evidence files.

## DFPMTS migration result

Migrated and verified on the current bitstream:

* The confreg device-tree node at `0x1fd0e000`.
* A Kconfig-controlled `chiplab_confreg` platform driver.
* Character-device reads at register offsets and read-only protection for
  input registers.
* Sysfs attributes for individual registers, grouped LED and input views,
  device information, and driver version.
* `nscscc-board` sysfs access with a `devmem` compatibility fallback.

Later system-integration work added the hardware required for the following
parts, so they are no longer configuration-only proposals:

* The adapted NT35510 character driver and Xilinx framebuffer driver from the
  DFPMTS archive.
* A PS/2 APB controller compatible with the standard Altera PS/2 Linux driver.
* A Full-Speed UE11 USB host, Linux HCD, HID, hidraw and evdev userspace path.
* A portable Buildroot configuration with X.Org, fbdev, evdev, eudev, Fluxbox,
  XTerm, `usbutils` and `evtest` for the 128 MiB system.

Rejected from the DFPMTS material:

* The DFPMTS L2 cache operations, fixed cache geometry, and 50 MHz timer
  change.  They alter CPU implementation contracts and conflict with the
  current 100 MHz setup.
* The DFPMTS DMFE rewrite.  The current DMFE already passes independent
  transmit, receive, interrupt, and error-counter checks.

Still incomplete or awaiting hardware evidence:

* NFSv3 root is implemented and passes build and shell-path validation, but it
  still needs an FPGA run proving DMFE mount, `switch_root` and read-write file
  access.
* The physical LCD has no successful visual observation for the current
  framebuffer system, even though complete 768000-byte writes and the
  framebuffer userspace ABI have been verified.
* PS/2 key events and USB HID mouse events still require attached-device logs.
  The UE11 controller supports Full-Speed devices only.
* Reproducible CoreMark, Dhrystone and network measurements have not been
  defined as Linux functionality claims. CPU performance remains outside this
  Linux-only work.
* The competition committee has not published the exact operations required
  for the 20-point Linux item.

## Implementation order

1. Repeatable TFTP boot with a recorded SHA256, size and U-Boot CRC32.
2. BusyBox init with `/dev`, `/proc`, `/sys`, `/run` and a persistent serial
   shell.
3. Static `eth0` setup, host ping, packet counters and DMFE interrupt checks.
4. Linux access to switches, buttons, LEDs and the seven-segment display
   through the confreg platform driver.
5. Two consecutive complete boots with the same artifact.
6. A compact demonstration command that records kernel, memory, filesystem,
   network and interrupt information.

The scripts under `scripts/nscscc` implement items 1 through 6. A recorded
artifact completed two independent boots from FPGA programming through the
Linux checks. The BusyBox and initramfs inputs also completed byte-for-byte
rebuild checks. The current post-NFS revision has passed offline builds and
shell tests but has not replaced that earlier hardware evidence.

## Later features

The most useful additions that do not require new FPGA controllers are:

* Hardware validation of the existing NFS root, including recovery behavior
  when the server is unavailable.
* BusyBox `httpd` or a small TCP service as a visible bidirectional network
  demonstration.
* Reproducible CoreMark and memory/network measurements with raw logs and fixed
  build identifiers.
* Additional non-destructive self-tests for input devices, framebuffer state
  and optional controllers when the corresponding hardware is present.

SD storage and audio should be considered only together with a defined
hardware implementation and pin assignment. Adding kernel configuration
without that hardware provides no usable competition feature.
