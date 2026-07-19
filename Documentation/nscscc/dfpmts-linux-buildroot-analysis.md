# DFPMTS Linux and Buildroot patch analysis

## Source material

The archive supplied by DFPMTS is:

```text
show_software_la32r(1).tar.gz
SHA256 04ddbe3fab6ad9cf30171761179292beffde5420cacf2005343d3507b54b742a
```

It contains two Linux patches and one Buildroot patch. The Linux source patch
changes 16 files with 2470 insertions and 40 deletions. The second Linux patch
adds a complete generated kernel configuration. The Buildroot patch adds a
complete generated configuration, a five-line build script, a local libffi
source override, and an `lxdialog` compiler fix.

The `DFPMTS/ysyx-workbench` `la32r-linux` branch is not the source of these
Linux and Buildroot trees. It is an NEMU/AbstractMachine CPU development
workspace. The archive is the authoritative input for this analysis.

## Kernel menuconfig differences

Comparing the supplied `la32r-geekpie-kernel_config` with this repository's
`arch/loongarch/configs/la32_defconfig` gives the following functional
differences:

```text
CONFIG_FB_OPENCORES=y
CONFIG_FB_CFB_FILLRECT=y
CONFIG_FB_CFB_COPYAREA=y
CONFIG_FB_CFB_IMAGEBLIT=y
CONFIG_INPUT_EVDEV=y
CONFIG_SERIO_ALTERA_PS2=y
CONFIG_VGA_CONSOLE=y
CONFIG_INITRAMFS_SOURCE="${BR_BINARIES_DIR}/rootfs.cpio"
CONFIG_INITRAMFS_COMPRESSION_GZIP=y
```

The compiler identification string is also different, but it is generated
metadata rather than a feature choice. `CONFIG_INITRAMFS_ROOT_UID` and
`CONFIG_INITRAMFS_ROOT_GID` are generated after selecting an initramfs source.

This means the kernel menuconfig is not the main source of DFPMTS's additional
functionality. It enables the standard input and framebuffer subsystems needed
by custom hardware drivers in the source patch. The existing `la32_defconfig`
already enables the applicable general features, including networking, DMFE,
MII, modules, loop devices, Btrfs, file locking, inotify, devtmpfs, tmpfs, and
IKCONFIG.

## Linux source changes

### Hardware-specific additions

The patch adds three large drivers directly to Makefiles without Kconfig
controls:

* `drivers/char/chiplab_confreg.c`, 817 lines. It exposes switches, buttons,
  LEDs, seven-segment display, timer, and frequency registers through a
  character device and sysfs.
* `drivers/char/nt35510.c`, 727 lines. It drives an NT35510 LCD controller at
  `0x1fe90000`.
* `drivers/video/fbdev/xilinxfb_accl.c`, 802 lines. It drives a custom Xilinx
  framebuffer and DMA engines at `0x1d010000`, `0x1d050000`, and
  `0x1d060000`.

It also enables an Altera PS/2 controller at `0x1fea0000`, interrupt 5, and
adds debug changes to `atkbd`, `altera_ps2`, and `libps2`.

Only the confreg concept applies to the current experiment box. The LCD, PS/2,
and framebuffer nodes require controllers that are absent from the current
Chiplab loongson FPGA project. Enabling their menuconfig entries alone cannot
provide those features.

The supplied confreg node maps `0x1fd0e000` through `0x1fd0ffff`. This matches
the Chiplab loongson `IP/CONFREG/confreg_syn.v` instance used by the current
Linux bitstream. Its board registers are:

```text
LED       0x1fd0f000
LED_RG0   0x1fd0f004
LED_RG1   0x1fd0f008
NUM       0x1fd0f010
SWITCH    0x1fd0f020
BTN_KEY   0x1fd0f024
BTN_STEP  0x1fd0f028
FREQ      0x1fd0f030
TIMER     0x1fd0e000
```

These addresses differ from the `0x1faff...` registers in the
`nscscc-team` teaching SoC. The correct map must be selected from the FPGA
project that produced the active bitstream, not from the CPU repository alone.

### CPU and cache assumptions

The patch changes `calc_const_freq()` from 200 MHz to 50 MHz. The current
Linux system uses a 100 MHz uncore clock, so this change is incompatible.

The cache patch adds a new L2 CACOP operation, changes DMA maintenance from L1
operations to L2 operations, and hard-codes both instruction and data caches as
64-byte lines, 64 sets, and two ways. These values and CACOP semantics are CPU
implementation contracts. They must not be copied without checking the current
CPU cache geometry and running DMA tests.

The DMFE patch changes allocation padding and explicitly writes back descriptor
and buffer regions. It may be relevant if the current DMFE driver can transmit
but receives stale descriptors or data. It should be evaluated only after
recording ping results, packet counters, interrupts, DMA addresses, and cache
behavior on the current CPU. Applying it before that evidence would combine a
driver problem with a CPU cache-coherency problem.

### Code quality and integration concerns

The added drivers are forced on with `obj-y`, lack Kconfig descriptions, and
contain debug prints and commented-out experiments. The patch also has 115
lines with trailing whitespace. The confreg implementation is much larger than
needed for the competition operations and should not be copied unchanged.

A current implementation should use a small device-tree platform driver with
Kconfig controls. Read-only registers should be exposed read-only, output
registers should use explicit write permissions, and resource bounds should be
checked. The NSCSCC port now follows this integration: it keeps the senior
character-device interface for compatibility, adds grouped sysfs views, and
checks the resource size before mapping it. The active initramfs command uses
sysfs first and retains `devmem` only as a compatibility fallback.

## Buildroot menuconfig

### System and toolchain

The supplied configuration selects:

* LoongArch32, LP32/ILP32S, MMU, little endian.
* An external GCC 8.3 glibc toolchain with Linux 5.14 headers.
* BusyBox init, devtmpfs, an empty root password, and a console getty.
* A gzip-compressed CPIO initramfs, a tar archive, and a 1 GiB ext4 image.
* The kernel as a local tar archive, using `la32_defconfig`, with `vmlinux`
  output and the Buildroot CPIO embedded into the kernel.

The external toolchain and kernel archive paths are absolute paths in DFPMTS's
home directory. The build script also copies a stripped kernel to the fixed
path `/srv/tftpboot/vmlinux-3`. None of these paths are portable.

The configuration selects both LSX and LASX even though the target is LA32R.
Those extensions must be disabled unless the current CPU and toolchain both
implement them. The 1 GiB ext4 image is not usable with the supplied kernel
configuration because `CONFIG_EXT4_FS` is disabled, and it does not fit the
128 MiB DDR as an initramfs.

### Selected user-space functionality

The useful intentional selections are:

```text
BusyBox and SysV init
iproute2 and ifupdown scripts
CoreMark and Dhrystone
bash, nano, file, and neofetch
Lua 5.4 and MicroPython
kmod and util-linux
cpio, gzip, bzip2, zip, and unzip
DBus, parted, libcap, libffi, ncurses, readline, and timezone data
```

The configuration does not enable Dropbear, OpenSSH, ethtool, strace, NFS,
an HTTP server, or Python 3. It therefore provides a richer local serial
environment, but not remote login or a more complete network demonstration.

The patched libffi package uses a private local directory. MicroPython and
other libffi consumers are consequently not reproducible from the archive
alone. The `lxdialog` change from implicit `main()` to `int main()` is a valid
host-compiler compatibility fix, but modern Buildroot versions already contain
an equivalent declaration.

## Adoption decisions

Use now:

1. Keep the current kernel configuration and embed a reproducible BusyBox CPIO.
2. Verify DMFE ping, TX/RX counters, and interrupts before changing cache or
   DMA code.
3. Provide board register access for the active Chiplab loongson bitstream.
4. Add CoreMark and Dhrystone only after the basic boot and network checks are
   repeatable.

Adapt after basic validation:

1. Replace `/dev/mem` access with a small confreg platform driver.
2. Create a portable Buildroot defconfig for the exact custom Buildroot fork
   and external LA32R toolchain used on EPYC2.
3. Add `ethtool` and `strace`; add BusyBox `httpd` or another small TCP service
   after bidirectional DMFE traffic is reliable.
4. Consider NFS root only after enabling the required kernel options and
   demonstrating reliable sustained network traffic.

Do not adopt for the current FPGA system:

1. The 50 MHz timer change.
2. LSX and LASX selections.
3. NT35510, PS/2, or Xilinx framebuffer configuration without matching RTL and
   pin assignments.
4. Hard-coded cache geometry and L2 CACOP behavior.
5. The private libffi path, local kernel tar path, fixed TFTP path, or 1 GiB
   ext4 image.

## Immediate validation order

1. Rebuild the existing compact initramfs with the corrected Chiplab loongson
   confreg addresses.
2. Program the commit-bound `ad6551afe009652b5562f200bd0d76f641d56a76`
   Linux bitstream and record the Vivado programming result.
3. Boot kernel commit `db7abacb8820fd0ca5212e2930d74118be7d8a8e` by TFTP.
4. Run the network and board checks twice from fresh resets.
5. Classify any DMFE failure before applying cache or driver changes.
6. Generate a minimal Buildroot defconfig from a known source commit using
   `make savedefconfig`; do not treat the supplied 4452-line `.config` as a
   portable defconfig.
