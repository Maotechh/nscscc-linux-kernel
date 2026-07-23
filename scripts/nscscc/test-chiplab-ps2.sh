#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0

set -euo pipefail

usage() {
	cat <<'EOF'
Usage: test-chiplab-ps2.sh CHIPLAB_REPOSITORY

Apply the existing display/PS2 integration patch and the bidirectional PS/2
update to their exact Chiplab base commit in a temporary worktree, then check
the Linux contract and run the PS/2 protocol simulation, Verilator lint, and
Yosys synthesis checks. The input repository is not modified.
EOF
}

if [[ $# -ne 1 ]]; then
	usage >&2
	exit 2
fi

chiplab_repo=$1
script_dir=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
kernel_root=$(CDPATH= cd -- "${script_dir}/../.." && pwd)
base_patch=${kernel_root}/Documentation/nscscc/evidence/chiplab-display-ps2-20260720.patch
ps2_patch=${kernel_root}/Documentation/nscscc/evidence/chiplab-ps2-bidirectional-20260724.patch
chiplab_base=a2e11b38bc5c85abb4408a8e0c0f5ce903c7ba31
expected_base_patch_sha256=c45fd7b1468b8ec60c011418d878847482a71d63f0d0b81d87a512a97cc631ae
expected_ps2_patch_sha256=f6382fd503524eeca5b65fc036685ddf3b7e6840807513b6704cc1ed235d0853
expected_ps2_sha256=5320f273c20f92ee5fc009b0c89514ea4c5a5f1e10934ddb4422bac291a03ed8

for command in git grep iverilog mktemp rm sha256sum verilator vvp yosys; do
	if ! command -v "${command}" >/dev/null 2>&1; then
		echo "Required command not found: ${command}" >&2
		exit 1
	fi
done

if [[ ! -d ${chiplab_repo} ]]; then
	echo "Chiplab repository is not a directory: ${chiplab_repo}" >&2
	exit 1
fi
for patch in "${base_patch}" "${ps2_patch}"; do
	if [[ ! -f ${patch} ]]; then
		echo "Recorded Chiplab patch is missing: ${patch}" >&2
		exit 1
	fi
done
if ! git -C "${chiplab_repo}" cat-file -e "${chiplab_base}^{commit}"; then
	echo "Chiplab base commit is unavailable: ${chiplab_base}" >&2
	exit 1
fi

actual_base_patch_sha256=$(sha256sum "${base_patch}" | awk '{print $1}')
if [[ ${actual_base_patch_sha256} != "${expected_base_patch_sha256}" ]]; then
	echo "Base Chiplab patch SHA256 mismatch: ${actual_base_patch_sha256}" >&2
	exit 1
fi
actual_ps2_patch_sha256=$(sha256sum "${ps2_patch}" | awk '{print $1}')
if [[ ${actual_ps2_patch_sha256} != "${expected_ps2_patch_sha256}" ]]; then
	echo "PS/2 patch SHA256 mismatch: ${actual_ps2_patch_sha256}" >&2
	exit 1
fi

work_dir=$(mktemp -d)
chiplab_tree=${work_dir}/chiplab
cleanup() {
	if [[ -e ${chiplab_tree}/.git ]]; then
		git -C "${chiplab_repo}" worktree remove --force \
			"${chiplab_tree}" >/dev/null 2>&1 || true
	fi
	rm -rf "${work_dir}"
}
trap cleanup EXIT

git -C "${chiplab_repo}" worktree add --detach \
	"${chiplab_tree}" "${chiplab_base}"
git -C "${chiplab_tree}" apply --check "${base_patch}"
git -C "${chiplab_tree}" apply "${base_patch}"
git -C "${chiplab_tree}" apply --check "${ps2_patch}"
git -C "${chiplab_tree}" apply "${ps2_patch}"

actual_ps2_sha256=$(
	sha256sum "${chiplab_tree}/IP/APB_DEV/bytestream_ps2.v" |
		awk '{print $1}'
)
if [[ ${actual_ps2_sha256} != "${expected_ps2_sha256}" ]]; then
	echo "Imported bytestream_ps2.v SHA256 mismatch: ${actual_ps2_sha256}" >&2
	exit 1
fi

for source in bytestream_ps2.v chiplab_ps2_rx.v; do
	grep -Fq "../../../IP/APB_DEV/${source}" \
		"${chiplab_tree}/fpga/loongson/2023.2/system_run.xpr"
done
grep -Fq "set_property PACKAGE_PIN Y2  [get_ports PS2_clk]" \
	"${chiplab_tree}/fpga/loongson/soc_up.xdc"
grep -Fq "set_property PACKAGE_PIN AD1 [get_ports PS2_dat]" \
	"${chiplab_tree}/fpga/loongson/soc_up.xdc"

iverilog -g2012 -Wall -s chiplab_ps2_rx_tb \
	-o "${work_dir}/chiplab_ps2_rx_tb.vvp" \
	"${chiplab_tree}/IP/APB_DEV/bytestream_ps2.v" \
	"${chiplab_tree}/IP/APB_DEV/chiplab_ps2_rx.v" \
	"${chiplab_tree}/IP/APB_DEV/sim/chiplab_ps2_rx_tb.v"
vvp "${work_dir}/chiplab_ps2_rx_tb.vvp"

verilator --lint-only --timing -Wall -Wno-fatal \
	--top-module chiplab_ps2_rx \
	"${chiplab_tree}/IP/APB_DEV/bytestream_ps2.v" \
	"${chiplab_tree}/IP/APB_DEV/chiplab_ps2_rx.v"

yosys -q -p \
	"read_verilog -sv \
${chiplab_tree}/IP/APB_DEV/bytestream_ps2.v \
${chiplab_tree}/IP/APB_DEV/chiplab_ps2_rx.v; \
hierarchy -check -top chiplab_ps2_rx; proc; opt; check -assert; stat"

grep -Fqx 'CONFIG_INPUT_EVDEV=y' \
	"${kernel_root}/arch/loongarch/configs/la32_defconfig"
grep -Fqx 'CONFIG_KEYBOARD_ATKBD=y' \
	"${kernel_root}/arch/loongarch/configs/la32_defconfig"
grep -Fqx 'CONFIG_SERIO_LIBPS2=y' \
	"${kernel_root}/arch/loongarch/configs/la32_defconfig"
grep -Fqx 'CONFIG_SERIO_ALTERA_PS2=y' \
	"${kernel_root}/arch/loongarch/configs/la32_defconfig"
grep -Fq 'compatible = "altr,ps2-1.0";' \
	"${kernel_root}/arch/loongarch/boot/dts/loongson/loongson32_ls.dts"
grep -Fq 'reg = <0x1fe04000 0x8>;' \
	"${kernel_root}/arch/loongarch/boot/dts/loongson/loongson32_ls.dts"
grep -Fq 'interrupts = <7>;' \
	"${kernel_root}/arch/loongarch/boot/dts/loongson/loongson32_ls.dts"

echo "PASSED: Chiplab patch, PS/2 protocol, synthesis, and Linux contract"
