# Optional NFS root for the NSCSCC experiment box

## Purpose

The experiment box has 128 MiB of DDR and no persistent mass-storage device
that is currently validated for Linux. Embedding the complete Buildroot
desktop in `vmlinux` consumes TFTP bandwidth and keeps a large initramfs in
memory. The optional NFS-root path keeps a small recovery initramfs in the
kernel, configures the validated DMFE interface, mounts a root filesystem from
the lab host, and calls BusyBox `switch_root`.

The normal initramfs boot remains the default. If the NFS argument is absent,
network setup fails, the export cannot be mounted, or the export has no
executable `/sbin/init`, boot continues in the recovery initramfs.
The initramfs and Buildroot network services detect any existing global IPv4
address before changing `eth0`. This preserves static configuration as well as
kernel DHCP or BOOTP configuration, so `switch_root` does not flush the address
used by the mounted NFS filesystem. An explicit network-service `restart`
still replaces the address with the value in `network.conf`.

## Kernel and initramfs support

`la32_defconfig` builds the IPv4 autoconfiguration, NFSv2/v3 client, SUNRPC,
lock manager, and NFS-root support into the kernel. NFSv4 remains disabled to
avoid code and authentication dependencies that are unnecessary on the
isolated experiment-box network.

The initramfs builder guarantees that `mount` and `switch_root` resolve to the
static BusyBox executable. Its `/init` accepts:

```text
nscscc.nfsroot=SERVER:/absolute/export/path
nscscc.nfsopts=vers=3,tcp
```

The options value is passed to `mount -t nfs`. Do not include spaces. The
default is `vers=3,tcp`.

## Server preparation

Export an extracted Buildroot target directory from a trusted host on the
dedicated experiment-box network. The exported directory must contain an
executable `/sbin/init`, `/dev`, `/proc`, `/run`, and `/sys`. Read-write mode
is useful during development; use a dedicated export rather than a host
system directory.

For the existing static network configuration, the server is `10.90.50.43`
and the board is `10.90.50.44/24`. The example kernel command is:

```text
bootelf -p 0xa3000000 g console=ttyS0,115200 rdinit=/init loglevel=8 nscscc.nfsroot=10.90.50.43:/srv/nscscc-root nscscc.nfsopts=vers=3,tcp
```

The `g` placeholder remains required by the current boot protocol. The NFS
arguments are additions to the existing verified `bootelf -p` command; they
do not change the TFTP address or kernel PT_LOAD destinations.

## Build and offline validation

Build the initramfs twice and require identical SHA256 values, then build the
kernel through `scripts/nscscc/build-kernel.sh`. Run:

```sh
scripts/nscscc/validate-nfs-root.sh \
  /absolute/kernel-build/.config \
  /absolute/artifacts/initramfs.cpio.gz \
  scripts/nscscc/busybox-1.33.config
```

This check requires the built-in NFS options, verifies the required applets
inside the compressed cpio, checks that BusyBox has NFS mount support, and
checks that the embedded BusyBox and configuration hashes are recorded in
`/etc/nscscc/build-info`. It also checks that `/init` contains the documented
arguments. It is intentionally an offline check.

The host-side service tests exercise the address-preservation and error paths,
as well as the success and failure results reported by `nscscc-check`:

```sh
scripts/nscscc/test-userspace-services.sh
```

These tests execute the actual shell scripts with temporary filesystem and
command mocks. They do not emulate LoongArch instructions, DMFE, or an NFS
server.

## Hardware validation still required

A future hardware run must preserve the complete serial log and demonstrate:

1. DMFE is configured with the expected static address and carrier is `1`.
2. The NFS export mounts successfully over TCP using NFSv3.
3. `switch_root` starts the exported `/sbin/init` as PID 1.
4. `/` reports filesystem type `nfs` and the expected server path.
5. A file can be created, read back, synchronized, and removed on the export.
6. The DMFE interrupt count increases while RX and TX error counters remain
   zero.
7. Omitting `nscscc.nfsroot` still reaches the recovery initramfs shell.

Until these checks are performed on an FPGA, the repository supports only the
claim that the NFS-root configuration, build, and recovery path passed offline
validation.
