#!/usr/bin/env bash
# Iteration-033/042/044: run the official NSCSCC la32r QEMU via the noble
# rootfs loader, against a kernel built from the committed integration head.
#
# This script is committed so the QEMU boot lane can be re-run after a host
# reboot.  The paths below are the two host-local external inputs required
# (the QEMU binary and its shared-library closure inside the noble rootfs);
# the kernel/initramfs are the committed artifacts referenced in
# qemu-boot-manifest-608939906.txt.
#
# Usage:
#   ./run-qemu32.sh -kernel <kbuild-O>/vmlinux \
#                   -initrd <kbuild-O>/usr/initramfs_inc_data \
#                   -nographic -m 128M -M ls3a5k32
#
# (vmlinux is emitted at the top of the O= build dir, not under
# arch/loongarch/boot/.)
#
# QEMU exits after a boot-timeout via -no-reboot; terminate with timeout(1).
set -u
SCR=${SCR:-/tmp/opencode/la32r-qemu}
LD=/nscscc-noble-rootfs/lib/x86_64-linux-gnu/ld-linux-x86-64.so.2
QEMU=/nscscc-noble-rootfs/opt/chiplab-tools/root/la32r-QEMU-x86_64-ubuntu-22.04/qemu-system-loongarch32
LPCAP=$SCR/libs/usr/lib/x86_64-linux-gnu
CAP=$SCR/libcapstone4-extracted/usr/lib/x86_64-linux-gnu
SUB=$(find "$LPCAP" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | tr '\n' ':')
ROOTLIBS=/nscscc-noble-rootfs/lib/x86_64-linux-gnu:/nscscc-noble-rootfs/usr/lib/x86_64-linux-gnu
exec $LD --library-path "$LPCAP:$CAP:$SUB$ROOTLIBS" $QEMU "$@"
