#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0

set -euo pipefail

usage() {
	cat <<'EOF'
Usage: validate-nfs-root.sh KERNEL_CONFIG INITRAMFS.cpio.gz BUSYBOX_CONFIG

Validate the kernel options and recovery initramfs required by the optional
NSCSCC NFS-root startup path. This is an offline check; it does not claim that
DMFE, the NFS server, or a hardware boot has been tested.
EOF
}

if [[ $# -ne 3 ]]; then
	usage >&2
	exit 2
fi

kernel_config=$1
initramfs=$2
busybox_config=$3

for path in "${kernel_config}" "${initramfs}" "${busybox_config}"; do
	if [[ ! -f ${path} ]]; then
		echo "Required file is missing: ${path}" >&2
		exit 1
	fi
done

for command in awk cpio grep gzip mktemp sha256sum; do
	if ! command -v "${command}" >/dev/null 2>&1; then
		echo "Required command not found: ${command}" >&2
		exit 1
	fi
done

required_busybox_options=(
	CONFIG_DD=y
	CONFIG_FEATURE_MOUNT_NFS=y
	CONFIG_IFCONFIG=y
	CONFIG_MKNOD=y
	CONFIG_PIDOF=y
	CONFIG_PS=y
	CONFIG_TIMEOUT=y
)
for option in "${required_busybox_options[@]}"; do
	if ! grep -Fqx "${option}" "${busybox_config}"; then
		echo "BusyBox configuration is missing ${option}" >&2
		exit 1
	fi
done

required_options=(
	CONFIG_IP_PNP=y
	CONFIG_IP_PNP_DHCP=y
	CONFIG_IP_PNP_BOOTP=y
	CONFIG_NFS_FS=y
	CONFIG_NFS_V3=y
	CONFIG_ROOT_NFS=y
)
for option in "${required_options[@]}"; do
	if ! grep -Fqx "${option}" "${kernel_config}"; then
		echo "Kernel configuration is missing ${option}" >&2
		exit 1
	fi
done

work_dir=$(mktemp -d)
trap 'rm -rf "${work_dir}"' EXIT
entries=${work_dir}/entries.txt
gzip -dc "${initramfs}" | cpio -it >"${entries}" 2>"${work_dir}/cpio.log"

required_entries=(
	bin/awk
	bin/busybox
	bin/dd
	bin/mknod
	bin/mount
	bin/switch_root
	bin/timeout
	etc/nscscc/build-info
	etc/init.d/S40network
	etc/init.d/S41nscscc-network
	init
	usr/bin/nscscc-board
	usr/bin/nscscc-check
	usr/bin/nscscc-demo
)
for entry in "${required_entries[@]}"; do
	if ! grep -Fqx "${entry}" "${entries}"; then
		echo "Initramfs is missing ${entry}" >&2
		exit 1
	fi
done

gzip -dc "${initramfs}" | cpio -i --quiet --to-stdout init >"${work_dir}/init"
for token in nscscc.nfsroot= nscscc.nfsopts= switch_root NFS_MOUNT_TIMEOUT; do
	if ! grep -Fq "${token}" "${work_dir}/init"; then
		echo "Initramfs /init is missing ${token}" >&2
		exit 1
	fi
done

gzip -dc "${initramfs}" | cpio -i --quiet --to-stdout etc/init.d/S41nscscc-network >"${work_dir}/S41nscscc-network"
for token in 'ip addr show dev' nscscc-network-ready; do
	if ! grep -Fq "${token}" "${work_dir}/S41nscscc-network"; then
		echo "Initramfs S41nscscc-network is missing ${token}" >&2
		exit 1
	fi
done

gzip -dc "${initramfs}" | cpio -i --quiet --to-stdout bin/busybox >"${work_dir}/busybox"
gzip -dc "${initramfs}" | cpio -i --quiet --to-stdout etc/nscscc/build-info >"${work_dir}/build-info"
embedded_busybox_sha256=$(sha256sum "${work_dir}/busybox" | awk '{print $1}')
recorded_busybox_sha256=$(awk -F= '$1 == "BUSYBOX_SHA256" {print substr($0, index($0, "=") + 1); exit}' "${work_dir}/build-info")
if [[ -z ${recorded_busybox_sha256} || ${embedded_busybox_sha256} != "${recorded_busybox_sha256}" ]]; then
	echo "Embedded BusyBox SHA256 does not match /etc/nscscc/build-info" >&2
	exit 1
fi

busybox_config_sha256=$(sha256sum "${busybox_config}" | awk '{print $1}')
recorded_config_sha256=$(awk -F= '$1 == "BUSYBOX_CONFIG_SHA256" {print substr($0, index($0, "=") + 1); exit}' "${work_dir}/build-info")
if [[ -z ${recorded_config_sha256} || ${busybox_config_sha256} != "${recorded_config_sha256}" ]]; then
	echo "BusyBox configuration SHA256 does not match /etc/nscscc/build-info" >&2
	exit 1
fi

echo "nfs_root_offline_validation=pass"
echo "kernel_config=${kernel_config}"
echo "initramfs=${initramfs}"
echo "busybox_config=${busybox_config}"
echo "busybox_sha256=${embedded_busybox_sha256}"
