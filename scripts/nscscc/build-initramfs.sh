#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0

set -euo pipefail

usage() {
	cat <<'EOF'
Usage: build-initramfs.sh BASE_ROOTFS OUTPUT.cpio.gz

Build an NSCSCC initramfs from an extracted LoongArch root filesystem.

Environment variables:
  NSCSCC_AUTO_NET       Configure eth0 during boot, 0 or 1 (default: 1)
  NSCSCC_INTERFACE      Network interface (default: eth0)
  NSCSCC_IP_CIDR        Static address (default: 10.90.50.44/24)
  NSCSCC_SERVER_IP      TFTP host and ping target (default: 10.90.50.43)
  NSCSCC_BUSYBOX        Optional replacement BusyBox executable
  SOURCE_DATE_EPOCH     Archive timestamp (default: 0)
EOF
}

if [[ $# -ne 2 ]]; then
	usage >&2
	exit 2
fi

base_rootfs=$1
output=$2
script_dir=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
overlay_dir=${script_dir}/initramfs-overlay

auto_net=${NSCSCC_AUTO_NET:-1}
interface=${NSCSCC_INTERFACE:-eth0}
ip_cidr=${NSCSCC_IP_CIDR:-10.90.50.44/24}
server_ip=${NSCSCC_SERVER_IP:-10.90.50.43}
busybox_override=${NSCSCC_BUSYBOX:-}
source_date_epoch=${SOURCE_DATE_EPOCH:-0}

if [[ ! -d ${base_rootfs} ]]; then
	echo "BASE_ROOTFS is not a directory: ${base_rootfs}" >&2
	exit 1
fi

for path in init etc/inittab etc/init.d/rcS etc/init.d/S40network; do
	if [[ ! -f ${overlay_dir}/${path} ]]; then
		echo "Initramfs overlay is missing ${path}: ${overlay_dir}/${path}" >&2
		exit 1
	fi
done

if [[ ${auto_net} != 0 && ${auto_net} != 1 ]]; then
	echo "NSCSCC_AUTO_NET must be 0 or 1" >&2
	exit 1
fi

if [[ -n ${busybox_override} && ! -f ${busybox_override} ]]; then
	echo "NSCSCC_BUSYBOX is not a file: ${busybox_override}" >&2
	exit 1
fi

for command in cpio find gzip sha256sum sort stat touch; do
	if ! command -v "${command}" >/dev/null 2>&1; then
		echo "Required command not found: ${command}" >&2
		exit 1
	fi
done

for path in bin/busybox bin/sh sbin/init sbin/ip sbin/devmem; do
	if [[ ! -e ${base_rootfs}/${path} ]]; then
		echo "BASE_ROOTFS is missing ${path}" >&2
		exit 1
	fi
done

work_dir=$(mktemp -d)
trap 'rm -rf "${work_dir}"' EXIT
rootfs=${work_dir}/rootfs
mkdir -p "${rootfs}"
cp -a "${base_rootfs}/." "${rootfs}/"
cp -a "${overlay_dir}/." "${rootfs}/"
if [[ -n ${busybox_override} ]]; then
	cp "${busybox_override}" "${rootfs}/bin/busybox"
	chmod 0755 "${rootfs}/bin/busybox"
fi
if [[ ! -e ${rootfs}/bin/ls ]]; then
	ln -s busybox "${rootfs}/bin/ls"
fi
if [[ ! -x ${rootfs}/bin/ls ]]; then
	echo "Initramfs /bin/ls is not executable" >&2
	exit 1
fi

mkdir -p \
	"${rootfs}/dev/pts" \
	"${rootfs}/dev/shm" \
	"${rootfs}/etc/nscscc" \
	"${rootfs}/proc" \
	"${rootfs}/run" \
	"${rootfs}/sys" \
	"${rootfs}/tmp" \
	"${rootfs}/usr/sbin" \
	"${rootfs}/var/log" \
	"${rootfs}/var/run"

cat >"${rootfs}/etc/nscscc/network.conf" <<EOF
AUTO_NET=${auto_net}
INTERFACE=${interface}
IP_CIDR=${ip_cidr}
SERVER_IP=${server_ip}
EOF

kernel_commit=unknown
if git -C "${script_dir}/../.." rev-parse --verify HEAD >/dev/null 2>&1; then
	kernel_commit=$(git -C "${script_dir}/../.." rev-parse HEAD)
fi
busybox_sha256=$(sha256sum "${rootfs}/bin/busybox" | awk '{print $1}')
busybox_origin=base-rootfs
if [[ -n ${busybox_override} ]]; then
	busybox_origin=override
fi

cat >"${rootfs}/etc/nscscc/build-info" <<EOF
KERNEL_SOURCE_COMMIT=${kernel_commit}
BUSYBOX_ORIGIN=${busybox_origin}
BUSYBOX_SHA256=${busybox_sha256}
SOURCE_DATE_EPOCH=${source_date_epoch}
EOF

chmod 0755 \
	"${rootfs}/init" \
	"${rootfs}/etc/init.d/rcS" \
	"${rootfs}/etc/init.d/S40network" \
	"${rootfs}/usr/bin/nscscc-board" \
	"${rootfs}/usr/bin/nscscc-check" \
	"${rootfs}/usr/sbin/nscscc-net"
chmod 0644 \
	"${rootfs}/etc/fstab" \
	"${rootfs}/etc/hostname" \
	"${rootfs}/etc/inittab" \
	"${rootfs}/etc/issue" \
	"${rootfs}/etc/os-release" \
	"${rootfs}/etc/profile" \
	"${rootfs}/etc/nscscc/build-info" \
	"${rootfs}/etc/nscscc/network.conf"

# A fixed timestamp and sorted input make byte-for-byte rebuilds possible.
find "${rootfs}" -exec touch -h -d "@${source_date_epoch}" {} +
mkdir -p "$(dirname -- "${output}")"
output=$(CDPATH= cd -- "$(dirname -- "${output}")" && pwd)/$(basename -- "${output}")

cpio_args=(--null --create --format=newc --owner=0:0)
if cpio --help 2>&1 | grep -q -- '--reproducible'; then
	cpio_args+=(--reproducible)
fi

(
	cd "${rootfs}"
	LC_ALL=C find . -print0 | LC_ALL=C sort -z | cpio "${cpio_args[@]}" 2>"${work_dir}/cpio.log"
) | gzip -9n >"${output}"

size=$(stat -c '%s' "${output}")
sha256=$(sha256sum "${output}" | awk '{print $1}')
crc32=unavailable
if command -v python3 >/dev/null 2>&1; then
	crc32=$(python3 - "${output}" <<'PY'
import pathlib
import sys
import zlib

data = pathlib.Path(sys.argv[1]).read_bytes()
print(f"{zlib.crc32(data) & 0xffffffff:08x}")
PY
	)
fi

echo "initramfs=${output}"
echo "size=${size}"
echo "sha256=${sha256}"
echo "crc32=${crc32}"
