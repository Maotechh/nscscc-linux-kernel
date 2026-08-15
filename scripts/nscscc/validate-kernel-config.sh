#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0

set -euo pipefail

if [[ $# -ne 1 ]]; then
	echo "Usage: validate-kernel-config.sh KERNEL_CONFIG" >&2
	exit 2
fi

config=$1
if [[ ! -f ${config} ]]; then
	echo "Kernel config not found: ${config}" >&2
	exit 1
fi

required_y=(
	CONFIG_32BIT
	CONFIG_MACH_LOONGSON_32
	CONFIG_LS_SOC
	CONFIG_PREEMPT
	CONFIG_NO_HZ_IDLE
	CONFIG_HZ_250
	CONFIG_DEVTMPFS
	CONFIG_DEVTMPFS_MOUNT
	CONFIG_INET
	CONFIG_IP_PNP
	CONFIG_NFS_FS
	CONFIG_NFS_V3
	CONFIG_ROOT_NFS
	CONFIG_DMFE_MAC
	CONFIG_INPUT_EVDEV
	CONFIG_SERIO_ALTERA_PS2
	CONFIG_USB
	CONFIG_USB_UE11_HCD
	CONFIG_USB_HID
	CONFIG_USB_STORAGE
	CONFIG_SCSI
	CONFIG_BLK_DEV_SD
	CONFIG_FB
	CONFIG_CHIPLAB_CONFREG
	CONFIG_CHIPLAB_NT35510
	CONFIG_EXT4_FS
	CONFIG_FAT_FS
	CONFIG_VFAT_FS
)

forbidden=(
	CONFIG_ATA
	CONFIG_BTRFS_FS
	CONFIG_DUMMY
	CONFIG_FB_XILINX_ACCL
	CONFIG_HW_RANDOM
	CONFIG_INPUT_MOUSEDEV
	CONFIG_IPMI_HANDLER
	CONFIG_IP_SCTP
	CONFIG_KEYBOARD_XTKBD
	CONFIG_MEDIA_SUPPORT
	CONFIG_MOUSE_SERIAL
	CONFIG_MTD_CFI
	CONFIG_NTFS_FS
	CONFIG_PCCARD
	CONFIG_PPS
	CONFIG_POWER_SUPPLY
	CONFIG_RAID6_PQ_BENCHMARK
	CONFIG_RC_CORE
	CONFIG_SERIAL_NONSTANDARD
	CONFIG_STMMAC_ETH
	CONFIG_TUN
	CONFIG_WIRELESS
	CONFIG_WLAN
	CONFIG_XFS_FS
)

failed=0
for symbol in "${required_y[@]}"; do
	if ! grep -qxF "${symbol}=y" "${config}"; then
		echo "Required kernel option is not built in: ${symbol}" >&2
		failed=1
	fi
done

for symbol in "${forbidden[@]}"; do
	if grep -Eq "^${symbol}=(y|m)$" "${config}"; then
		echo "Unused kernel option is enabled: ${symbol}" >&2
		failed=1
	fi
done

if (( failed != 0 )); then
	exit 1
fi

echo "NSCSCC kernel configuration validated: ${config}"
