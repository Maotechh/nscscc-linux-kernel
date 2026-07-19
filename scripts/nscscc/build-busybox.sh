#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0

set -euo pipefail

usage() {
	cat <<'EOF'
Usage: build-busybox.sh BUSYBOX_SOURCE BUILD_DIR OUTPUT

Build the static BusyBox used by the NSCSCC initramfs. CROSS_COMPILE must
name the LoongArch32 Reduced toolchain prefix.

Environment variables:
  CROSS_COMPILE              Required toolchain prefix
  NSCSCC_BUILD_JOBS          Parallel build jobs (default: nproc)
  NSCSCC_BUSYBOX_COMMIT      Required source commit
  NSCSCC_BUSYBOX_CONFIG      Configuration file
EOF
}

if [[ $# -ne 3 ]]; then
	usage >&2
	exit 2
fi

source_dir=$1
build_dir=$2
output=$3
script_dir=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
cross_compile=${CROSS_COMPILE:-}
build_jobs=${NSCSCC_BUILD_JOBS:-$(nproc)}
expected_commit=${NSCSCC_BUSYBOX_COMMIT:-db726ae0c61ffec6b58e19749e0c63aaaf4f6989}
config=${NSCSCC_BUSYBOX_CONFIG:-${script_dir}/busybox-1.33.config}
expected_config_sha256=71f6ee381f177f4722c522753f79095a571ec22637ee222d0ca9219b0b5f9975

if [[ -z ${cross_compile} ]]; then
	echo "CROSS_COMPILE is required" >&2
	exit 1
fi

for command in file git make nproc sha256sum stat strings; do
	if ! command -v "${command}" >/dev/null 2>&1; then
		echo "Required command not found: ${command}" >&2
		exit 1
	fi
done
for tool in gcc readelf; do
	if ! command -v "${cross_compile}${tool}" >/dev/null 2>&1; then
		echo "Toolchain command not found: ${cross_compile}${tool}" >&2
		exit 1
	fi
done

if [[ ! -f ${source_dir}/Makefile ]]; then
	echo "BusyBox source Makefile not found: ${source_dir}/Makefile" >&2
	exit 1
fi
if [[ -e ${source_dir}/.config ]]; then
	echo "BusyBox source contains an in-tree .config; use a clean clone or worktree" >&2
	exit 1
fi
if [[ ! -f ${config} ]]; then
	echo "BusyBox configuration not found: ${config}" >&2
	exit 1
fi

source_dir=$(CDPATH= cd -- "${source_dir}" && pwd)
config=$(CDPATH= cd -- "$(dirname -- "${config}")" && pwd)/$(basename -- "${config}")
commit=$(git -C "${source_dir}" rev-parse HEAD)
if [[ ${commit} != "${expected_commit}" ]]; then
	echo "BusyBox commit ${commit} does not match ${expected_commit}" >&2
	exit 1
fi

config_sha256=$(sha256sum "${config}" | awk '{print $1}')
if [[ ${config_sha256} != "${expected_config_sha256}" ]]; then
	echo "BusyBox config SHA256 ${config_sha256} does not match ${expected_config_sha256}" >&2
	exit 1
fi

if [[ -e ${build_dir} ]] && find "${build_dir}" -mindepth 1 -print -quit | grep -q .; then
	echo "BUILD_DIR must be absent or empty: ${build_dir}" >&2
	exit 1
fi
mkdir -p "${build_dir}" "$(dirname -- "${output}")"
build_dir=$(CDPATH= cd -- "${build_dir}" && pwd)
output=$(CDPATH= cd -- "$(dirname -- "${output}")" && pwd)/$(basename -- "${output}")

cp "${config}" "${build_dir}/.config"
make -C "${source_dir}" O="${build_dir}" \
	KCONFIG_NOTIMESTAMP=1 CROSS_COMPILE="${cross_compile}" oldconfig </dev/null
make -C "${source_dir}" O="${build_dir}" \
	KCONFIG_NOTIMESTAMP=1 CROSS_COMPILE="${cross_compile}" \
	-j"${build_jobs}" busybox
cp "${build_dir}/busybox" "${output}"
chmod 0755 "${output}"

elf_class=$("${cross_compile}readelf" -h "${output}" | awk -F: '/Class:/{gsub(/^[[:space:]]+/, "", $2); print $2}')
elf_machine=$("${cross_compile}readelf" -h "${output}" | awk -F: '/Machine:/{gsub(/^[[:space:]]+/, "", $2); print $2}')
file_description=$(file -b "${output}")
if [[ ${elf_class} != ELF32 ]]; then
	echo "Expected ELF32, got ${elf_class}" >&2
	exit 1
fi
if [[ ${elf_machine} != LoongArch ]]; then
	echo "Expected LoongArch, got ${elf_machine}" >&2
	exit 1
fi
if [[ ${file_description} != *"statically linked"* || ${file_description} != *"stripped"* ]]; then
	echo "Expected a stripped, statically linked binary, got: ${file_description}" >&2
	exit 1
fi

size=$(stat -c '%s' "${output}")
sha256=$(sha256sum "${output}" | awk '{print $1}')
banner=$(strings "${output}" | awk '/^BusyBox v/ && value == "" {value = $0} END {print value}')
toolchain_version=$("${cross_compile}gcc" -dumpfullversion -dumpversion)

cat >"${output}.manifest" <<EOF
busybox_commit=${commit}
config=${config}
config_sha256=${config_sha256}
toolchain=${toolchain_version}
artifact=${output}
size=${size}
sha256=${sha256}
banner=${banner}
elf_class=${elf_class}
elf_machine=${elf_machine}
file=${file_description}
EOF

cat "${output}.manifest"
