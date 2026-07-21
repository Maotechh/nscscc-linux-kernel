#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0

set -euo pipefail

usage() {
	cat <<'EOF'
Usage: build-kernel.sh BASE_ROOTFS BUILD_DIR ARTIFACT_DIR

Run this script from the kernel source tree. CROSS_COMPILE must name the
LoongArch32 Reduced toolchain prefix.

Environment variables:
  ARCH                    Kernel architecture (default: loongarch)
  CROSS_COMPILE           Required toolchain prefix
  NSCSCC_DEFCONFIG        Kernel defconfig (default: la32_defconfig)
  NSCSCC_BUILD_JOBS       Parallel build jobs (default: nproc)
  NSCSCC_ARTIFACT_NAME    TFTP file name (default: vmlinux-<commit>)
  NSCSCC_EXPECT_LOAD      Expected first PT_LOAD address (default: 0xa0300000)
  NSCSCC_DDR_END          Exclusive cached DDR end (default: 0xa8000000)
  NSCSCC_TFTP_ADDRESS     TFTP download address (default: 0xa3000000)

The NSCSCC_AUTO_NET, NSCSCC_INTERFACE, NSCSCC_IP_CIDR and NSCSCC_SERVER_IP
variables and the optional NSCSCC_BUSYBOX path are forwarded to
build-initramfs.sh.
EOF
}

if [[ $# -ne 3 ]]; then
	usage >&2
	exit 2
fi

source_dir=$(pwd)
base_rootfs=$1
build_dir=$2
artifact_dir=$3
arch=${ARCH:-loongarch}
cross_compile=${CROSS_COMPILE:-}
defconfig=${NSCSCC_DEFCONFIG:-la32_defconfig}
build_jobs=${NSCSCC_BUILD_JOBS:-$(nproc)}
expect_load=${NSCSCC_EXPECT_LOAD:-0xa0300000}
ddr_end=${NSCSCC_DDR_END:-0xa8000000}
tftp_address=${NSCSCC_TFTP_ADDRESS:-0xa3000000}

if [[ -z ${cross_compile} ]]; then
	echo "CROSS_COMPILE is required" >&2
	exit 1
fi

for tool in gcc nm readelf strip; do
	if ! command -v "${cross_compile}${tool}" >/dev/null 2>&1; then
		echo "Toolchain command not found: ${cross_compile}${tool}" >&2
		exit 1
	fi
done
for command in cmp du install python3 sha256sum stat; do
	if ! command -v "${command}" >/dev/null 2>&1; then
		echo "Required command not found: ${command}" >&2
		exit 1
	fi
done

for path in Makefile scripts/config scripts/nscscc/build-initramfs.sh; do
	if [[ ! -e ${source_dir}/${path} ]]; then
		echo "Run from an NSCSCC kernel source tree; missing ${path}" >&2
		exit 1
	fi
done

mkdir -p "${build_dir}" "${artifact_dir}"
build_dir=$(CDPATH= cd -- "${build_dir}" && pwd)
artifact_dir=$(CDPATH= cd -- "${artifact_dir}" && pwd)

commit=$(git -C "${source_dir}" rev-parse HEAD 2>/dev/null || echo unknown)
short_commit=${commit:0:9}
artifact_name=${NSCSCC_ARTIFACT_NAME:-vmlinux-${short_commit}}
initramfs=${artifact_dir}/initramfs-${short_commit}.cpio.gz
initramfs_repeat=${artifact_dir}/initramfs-${short_commit}-repeat.cpio.gz
initramfs_config_source=nscscc-initramfs-${short_commit}.cpio.gz
kernel_initramfs=${build_dir}/${initramfs_config_source}

"${source_dir}/scripts/nscscc/build-initramfs.sh" "${base_rootfs}" "${initramfs}"
"${source_dir}/scripts/nscscc/build-initramfs.sh" "${base_rootfs}" "${initramfs_repeat}"
if ! cmp -s "${initramfs}" "${initramfs_repeat}"; then
	echo "Repeated initramfs builds are not byte-for-byte identical" >&2
	exit 1
fi
install -m 0644 "${initramfs}" "${kernel_initramfs}"

make -C "${source_dir}" O="${build_dir}" ARCH="${arch}" \
	CROSS_COMPILE="${cross_compile}" "${defconfig}"
"${source_dir}/scripts/config" --file "${build_dir}/.config" \
	--set-str INITRAMFS_SOURCE "${initramfs_config_source}"
make -C "${source_dir}" O="${build_dir}" ARCH="${arch}" \
	CROSS_COMPILE="${cross_compile}" olddefconfig
make -C "${source_dir}" O="${build_dir}" ARCH="${arch}" \
	CROSS_COMPILE="${cross_compile}" -j"${build_jobs}" vmlinux

debug_artifact=${artifact_dir}/${artifact_name}-debug
tftp_artifact=${artifact_dir}/${artifact_name}
cp "${build_dir}/vmlinux" "${debug_artifact}"
cp "${build_dir}/vmlinux" "${tftp_artifact}"
"${cross_compile}strip" --strip-all "${tftp_artifact}"

elf_class=$("${cross_compile}readelf" -h "${tftp_artifact}" | awk -F: '/Class:/{gsub(/^[[:space:]]+/, "", $2); print $2}')
elf_machine=$("${cross_compile}readelf" -h "${tftp_artifact}" | awk -F: '/Machine:/{gsub(/^[[:space:]]+/, "", $2); print $2}')
elf_entry=$("${cross_compile}readelf" -h "${tftp_artifact}" | awk '/Entry point address:/{print $4}')
kernel_entry=$("${cross_compile}nm" -n "${debug_artifact}" | awk '$3 == "kernel_entry" {value = "0x" $1} END {print value}')
load_rows=$("${cross_compile}readelf" -lW "${tftp_artifact}" | awk '$1 == "LOAD" {print $3, $6}')
first_load=$(awk 'NR == 1 {print $1}' <<<"${load_rows}")
load_memsz=$(awk 'NR == 1 {print $2}' <<<"${load_rows}")
load_count=$(awk 'NF == 2 {count++} END {print count + 0}' <<<"${load_rows}")

if [[ ${elf_class} != ELF32 ]]; then
	echo "Expected ELF32, got ${elf_class}" >&2
	exit 1
fi
if [[ ${elf_machine} != LoongArch ]]; then
	echo "Expected LoongArch, got ${elf_machine}" >&2
	exit 1
fi
if [[ -z ${elf_entry} || -z ${kernel_entry} ]]; then
	echo "ELF entry or kernel_entry symbol is missing" >&2
	exit 1
fi
if [[ -z ${first_load} || -z ${load_memsz} || ${load_count} -eq 0 ]]; then
	echo "ELF PT_LOAD program header is missing" >&2
	exit 1
fi
if (( elf_entry != kernel_entry )); then
	echo "ELF entry ${elf_entry} does not match kernel_entry ${kernel_entry}" >&2
	exit 1
fi
if (( first_load != expect_load )); then
	echo "First PT_LOAD ${first_load} does not match ${expect_load}" >&2
	exit 1
fi

load_end=0
while read -r load_address load_size; do
	segment_end=$((load_address + load_size))
	if (( segment_end > load_end )); then
		load_end=${segment_end}
	fi
done <<<"${load_rows}"
artifact_size=$(stat -c '%s' "${tftp_artifact}")
tftp_end=$((tftp_address + artifact_size))
if (( load_end > ddr_end )); then
	printf 'PT_LOAD end 0x%x exceeds DDR end 0x%x\n' "${load_end}" "${ddr_end}" >&2
	exit 1
fi
if (( tftp_end > ddr_end )); then
	printf 'TFTP buffer end 0x%x exceeds DDR end 0x%x\n' "${tftp_end}" "${ddr_end}" >&2
	exit 1
fi
if (( tftp_address < load_end && tftp_end > first_load )); then
	printf 'TFTP buffer 0x%x..0x%x overlaps PT_LOAD range 0x%x..0x%x\n' \
		"${tftp_address}" "${tftp_end}" "${first_load}" "${load_end}" >&2
	exit 1
fi

sha256=$(sha256sum "${tftp_artifact}" | awk '{print $1}')
debug_size=$(stat -c '%s' "${debug_artifact}")
debug_sha256=$(sha256sum "${debug_artifact}" | awk '{print $1}')
kernel_config_sha256=$(sha256sum "${build_dir}/.config" | awk '{print $1}')
initramfs_size=$(stat -c '%s' "${initramfs}")
initramfs_sha256=$(sha256sum "${initramfs}" | awk '{print $1}')
base_rootfs_bytes=$(du -sb "${base_rootfs}" | awk '{print $1}')
busybox_size=$(stat -c '%s' "${base_rootfs}/bin/busybox")
busybox_sha256=$(sha256sum "${base_rootfs}/bin/busybox" | awk '{print $1}')
desktop_build_info=${base_rootfs}/etc/nscscc/desktop-build-info
desktop_build_info_sha256=unavailable
if [[ -f ${desktop_build_info} ]]; then
	desktop_build_info_sha256=$(sha256sum "${desktop_build_info}" | awk '{print $1}')
fi
toolchain_version=$("${cross_compile}gcc" -dumpfullversion -dumpversion)
toolchain_gcc_sha256=$(sha256sum "$(command -v "${cross_compile}gcc")" | awk '{print $1}')
crc32=$(python3 - "${tftp_artifact}" <<'PY'
import pathlib
import sys
import zlib

data = pathlib.Path(sys.argv[1]).read_bytes()
print(f"{zlib.crc32(data) & 0xffffffff:08x}")
PY
)
initramfs_crc32=$(python3 - "${initramfs}" <<'PY'
import pathlib
import sys
import zlib

data = pathlib.Path(sys.argv[1]).read_bytes()
print(f"{zlib.crc32(data) & 0xffffffff:08x}")
PY
)

cat >"${artifact_dir}/${artifact_name}.manifest" <<EOF
kernel_commit=${commit}
artifact=${tftp_artifact}
debug_artifact=${debug_artifact}
debug_size=${debug_size}
debug_sha256=${debug_sha256}
kernel_config_sha256=${kernel_config_sha256}
base_rootfs=${base_rootfs}
base_rootfs_bytes=${base_rootfs_bytes}
busybox_size=${busybox_size}
busybox_sha256=${busybox_sha256}
desktop_build_info_sha256=${desktop_build_info_sha256}
initramfs=${initramfs}
initramfs_repeat=${initramfs_repeat}
initramfs_config_source=${initramfs_config_source}
initramfs_size=${initramfs_size}
initramfs_sha256=${initramfs_sha256}
initramfs_crc32=${initramfs_crc32}
initramfs_reproducible=true
toolchain_version=${toolchain_version}
toolchain_gcc_sha256=${toolchain_gcc_sha256}
size=${artifact_size}
sha256=${sha256}
crc32=${crc32}
elf_class=${elf_class}
elf_machine=${elf_machine}
entry=${elf_entry}
kernel_entry=${kernel_entry}
first_load=${first_load}
load_memsz=${load_memsz}
load_count=${load_count}
load_end=$(printf '0x%x' "${load_end}")
tftp_address=${tftp_address}
tftp_end=$(printf '0x%x' "${tftp_end}")
ddr_end=${ddr_end}
EOF

cat "${artifact_dir}/${artifact_name}.manifest"
