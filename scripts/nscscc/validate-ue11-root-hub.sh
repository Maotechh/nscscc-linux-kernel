#!/bin/sh
# SPDX-License-Identifier: GPL-2.0

set -eu

mode=${1:-}

usage()
{
	echo "usage: $0 no-device|full-speed|low-speed" >&2
	exit 2
}

downstream_devices()
{
	for path in /sys/bus/usb/devices/*-*; do
		[ -e "$path" ] || continue
		name=${path##*/}
		case "$name" in
		*:*)
			continue
			;;
		esac
		echo "$path"
	done
}

[ -n "$mode" ] || usage

case "$mode" in
no-device)
	sleep 1
	devices=$(downstream_devices)
	if [ -n "$devices" ]; then
		echo "FAIL: downstream USB device exists with no device attached" >&2
		echo "$devices" >&2
		exit 1
	fi
	if dmesg | grep -Eq \
		'Full-Speed device detected|Low-Speed device detected'; then
		echo "FAIL: driver reported a device in the no-device boot" >&2
		exit 1
	fi
	echo "PASS: no false root-hub attachment after one second"
	;;
full-speed)
	sleep 1
	devices=$(downstream_devices)
	device=$(printf '%s\n' "$devices" | sed -n '1p')
	[ -n "$device" ] || {
		echo "FAIL: no downstream USB device" >&2
		exit 1
	}
	[ "$(printf '%s\n' "$devices" | sed '/^$/d' | wc -l)" -eq 1 ] || {
		echo "FAIL: expected one downstream USB device" >&2
		echo "$devices" >&2
		exit 1
	}
	speed=$(cat "$device/speed")
	[ "$speed" = "12" ] || {
		echo "FAIL: expected Full-Speed 12 Mbit/s, got $speed" >&2
		exit 1
	}
	[ -r "$device/idVendor" ] && [ -r "$device/idProduct" ] || {
		echo "FAIL: USB descriptors are unavailable" >&2
		exit 1
	}
	awk '
		BEGIN { RS = ""; found = 0 }
		/P: Phys=usb-/ && /H: Handlers=.*mouse/ { found = 1 }
		END { exit !found }
	' /proc/bus/input/devices || {
		echo "FAIL: no USB-backed Linux mouse input device" >&2
		exit 1
	}
	printf 'PASS: Full-Speed USB %s:%s with mouse input\n' \
		"$(cat "$device/idVendor")" "$(cat "$device/idProduct")"
	;;
low-speed)
	sleep 1
	dmesg | grep -q 'Low-Speed device detected' || {
		echo "FAIL: no Low-Speed line-state report" >&2
		exit 1
	}
	devices=$(downstream_devices)
	if [ -n "$devices" ]; then
		echo "FAIL: unsupported Low-Speed device was enumerated" >&2
		echo "$devices" >&2
		exit 1
	fi
	echo "PASS: Low-Speed attachment was identified and rejected safely"
	;;
*)
	usage
	;;
esac
