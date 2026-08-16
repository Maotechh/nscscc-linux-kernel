#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0

set -euo pipefail

script_dir=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
initramfs_network=${script_dir}/initramfs-overlay/etc/init.d/S40network
buildroot_network=${script_dir}/buildroot/rootfs-overlay/etc/init.d/S41nscscc-network
nscscc_check=${script_dir}/initramfs-overlay/usr/bin/nscscc-check
nscscc_demo=${script_dir}/initramfs-overlay/usr/bin/nscscc-demo
init=${script_dir}/initramfs-overlay/init
rcs=${script_dir}/initramfs-overlay/etc/init.d/rcS

work_dir=$(mktemp -d)
trap 'rm -rf "${work_dir}"' EXIT
mock_bin=${work_dir}/mock-bin
mock_log=${work_dir}/mock.log
mkdir -p "${mock_bin}"
: >"${mock_log}"

fail()
{
	echo "FAIL: $*" >&2
	exit 1
}

assert_contains()
{
	grep -Fq -- "$2" "$1" || fail "$1 does not contain: $2"
}

assert_not_contains()
{
	if grep -Fq -- "$2" "$1"; then
		fail "$1 unexpectedly contains: $2"
	fi
}

cat >"${mock_bin}/ip" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'ip' >>"${MOCK_LOG}"
printf ' %s' "$@" >>"${MOCK_LOG}"
printf '\n' >>"${MOCK_LOG}"

if [[ ${1:-} == link && ${2:-} == show ]]; then
	[[ ${MOCK_INTERFACE_STATE:-none} != missing ]]
	exit
fi

if [[ ${1:-} == addr && ${2:-} == show ]]; then
	if [[ ${MOCK_INTERFACE_STATE:-none} == existing ]]; then
		printf '2: eth0: <UP,LOWER_UP>\n'
		printf '    inet 192.0.2.44/24 scope global eth0\n'
	fi
	exit
fi

if [[ ${1:-} == addr && ${2:-} == add && ${MOCK_IP_FAIL_ADD:-0} == 1 ]]; then
	exit 1
fi
EOF

cat >"${mock_bin}/ping" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'ping' >>"${MOCK_LOG}"
printf ' %s' "$@" >>"${MOCK_LOG}"
printf '\n' >>"${MOCK_LOG}"
if [[ ${MOCK_PING_FAIL:-0} == 1 ]]; then
	exit 1
fi
cat >"${MOCK_ROOT}/proc/interrupts" <<'DATA'
           CPU0
 18:         13  LoongArch   2  eth0
DATA
echo '3 packets transmitted, 3 packets received, 0% packet loss'
EOF

cat >"${mock_bin}/mount" <<'EOF'
#!/usr/bin/env bash
echo 'rootfs on / type rootfs (rw)'
EOF

cat >"${mock_bin}/nscscc-board" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
	read)
		echo 'switches=0x00000000'
		echo 'buttons=0x00000000'
		echo 'step_buttons=0x00000000'
		;;
	led|display|clear)
		exit 0
		;;
	*)
		exit 2
		;;
esac
EOF

cat >"${mock_bin}/pidof" <<'EOF'
#!/usr/bin/env bash
echo 42
EOF

cat >"${mock_bin}/ifconfig" <<'EOF'
#!/usr/bin/env bash
echo 'eth0      Link encap:Ethernet  HWaddr 00:00:00:00:00:00'
echo '          inet addr:192.0.2.44  Bcast:192.0.2.255  Mask:255.255.255.0'
EOF

cat >"${mock_bin}/ps" <<'EOF'
#!/usr/bin/env bash
echo '  PID  USER     TIME   COMMAND'
echo '    1  root     0:00   /sbin/init'
echo '   42  root     0:00   /bin/sh'
EOF

cat >"${mock_bin}/df" <<'EOF'
#!/usr/bin/env bash
echo 'Filesystem           1K-blocks      Used Available Use% Mounted on'
echo 'rootfs                   120000     20000    100000  17% /'
EOF

cat >"${mock_bin}/dd" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
of=
bs=
count=
for arg in "$@"; do
	case "${arg}" in
		of=*) of=${arg#of=} ;;
		bs=*) bs=${arg#bs=} ;;
		count=*) count=${arg#count=} ;;
	esac
done
[[ -n ${of} ]] || exit 1
/bin/dd if=/dev/zero of="${of}" bs="${bs}" count="${count}" 2>/dev/null
EOF

cat >"${mock_bin}/dmesg" <<'EOF'
#!/usr/bin/env bash
echo '[    0.000000] Linux version test'
echo '[    1.000000] dmfe: Change Speed to 100Mhz full duplex'
EOF

chmod 0755 "${mock_bin}"/*

new_network_root()
{
	local root=$1
	mkdir -p "${root}/etc/nscscc" "${root}/run"
	cat >"${root}/etc/nscscc/network.conf" <<'EOF'
AUTO_NET=1
INTERFACE=eth0
IP_CIDR=10.90.50.44/24
SERVER_IP=10.90.50.43
EOF
}

run_network_tests()
{
	local service=$1
	local name=$2
	local root=${work_dir}/${name}-root
	local output=${work_dir}/${name}.out
	local ready=${root}/run/nscscc-network-ready

	new_network_root "${root}"
	: >"${mock_log}"
	MOCK_LOG=${mock_log} MOCK_INTERFACE_STATE=none \
		NSCSCC_ROOT=${root} NSCSCC_PATH=${mock_bin}:/usr/bin:/bin \
		"${service}" start >"${output}" 2>&1
	[[ -e ${ready} ]] || fail "${name} did not create the ready marker"
	assert_contains "${mock_log}" 'ip addr flush dev eth0'
	assert_contains "${mock_log}" 'ip addr add 10.90.50.44/24 dev eth0'

	: >"${mock_log}"
	MOCK_LOG=${mock_log} MOCK_INTERFACE_STATE=none \
		NSCSCC_ROOT=${root} NSCSCC_PATH=${mock_bin}:/usr/bin:/bin \
		"${service}" start >"${output}" 2>&1
	assert_not_contains "${mock_log}" 'ip addr flush dev eth0'

	rm -f "${ready}"
	: >"${mock_log}"
	MOCK_LOG=${mock_log} MOCK_INTERFACE_STATE=existing \
		NSCSCC_ROOT=${root} NSCSCC_PATH=${mock_bin}:/usr/bin:/bin \
		"${service}" start >"${output}" 2>&1
	[[ -e ${ready} ]] || fail "${name} did not record an existing address"
	assert_contains "${output}" 'Preserving existing IPv4 configuration on eth0.'
	assert_not_contains "${mock_log}" 'ip addr flush dev eth0'
	assert_not_contains "${mock_log}" 'ip addr add 10.90.50.44/24 dev eth0'

	: >"${mock_log}"
	MOCK_LOG=${mock_log} MOCK_INTERFACE_STATE=existing \
		NSCSCC_ROOT=${root} NSCSCC_PATH=${mock_bin}:/usr/bin:/bin \
		"${service}" status >"${output}" 2>&1
	assert_contains "${mock_log}" 'ip addr show eth0'

	rm -f "${ready}"
	: >"${mock_log}"
	if MOCK_LOG=${mock_log} MOCK_INTERFACE_STATE=missing \
		NSCSCC_ROOT=${root} NSCSCC_PATH=${mock_bin}:/usr/bin:/bin \
		"${service}" start >"${output}" 2>&1; then
		fail "${name} accepted a missing network interface"
	fi
	[[ ! -e ${ready} ]] || fail "${name} marked a missing interface ready"
	assert_contains "${output}" 'Network interface not found: eth0'

	: >"${mock_log}"
	if MOCK_LOG=${mock_log} MOCK_INTERFACE_STATE=none MOCK_IP_FAIL_ADD=1 \
		NSCSCC_ROOT=${root} NSCSCC_PATH=${mock_bin}:/usr/bin:/bin \
		"${service}" start >"${output}" 2>&1; then
		fail "${name} ignored an address configuration failure"
	fi
	[[ ! -e ${ready} ]] || fail "${name} marked a failed configuration ready"

	echo "network_service_${name}=pass"
}

new_check_root()
{
	local root=$1
	local statistic

	new_network_root "${root}"
	mkdir -p \
		"${root}/proc/bus/input" \
		"${root}/sys/class/input" \
		"${root}/sys/class/net/eth0/statistics" \
		"${root}/dev/input"
	cat >"${root}/etc/nscscc/build-info" <<'EOF'
KERNEL_SOURCE_COMMIT=0123456789abcdef
BUSYBOX_SHA256=abcdef0123456789
EOF
	cat >"${root}/proc/meminfo" <<'EOF'
MemTotal:         115596 kB
MemFree:           64000 kB
MemAvailable:      72000 kB
EOF
	cat >"${root}/proc/interrupts" <<'EOF'
           CPU0
 18:         10  LoongArch   2  eth0
EOF
	cat >"${root}/proc/cpuinfo" <<'EOF'
system type             : loongson,nscscc-la32r
processor               : 0
EOF
	cat >"${root}/proc/cmdline" <<'EOF'
console=ttyS0,115200 rdinit=/init nscscc.autorun=nscscc-demo
EOF
	cat >"${root}/proc/uptime" <<'EOF'
120.00 240.00
EOF
	cat >"${root}/proc/filesystems" <<'EOF'
nodev	sysfs
nodev	proc
EOF
	cat >"${root}/proc/devices" <<'EOF'
Character devices:
  1 mem
  4 ttyS
  5 /dev/tty
EOF
	cat >"${root}/proc/bus/input/devices" <<'EOF'
I: Bus=0011 Vendor=0001 Product=0001 Version=ab41
N: Name="AT Translated Set 2 keyboard"
H: Handlers=sysrq kbd event0
EOF
	echo 1 >"${root}/sys/class/net/eth0/carrier"
	for statistic in rx_packets tx_packets rx_bytes tx_bytes rx_errors tx_errors; do
		echo 0 >"${root}/sys/class/net/eth0/statistics/${statistic}"
	done
	: >"${root}/dev/input/event0"
	: >"${root}/dev/fb0"
	: >"${root}/dev/nt35510"
}

run_check_tests()
{
	local root=${work_dir}/check-root
	local output=${work_dir}/check.out

	new_check_root "${root}"
	: >"${mock_log}"
	MOCK_LOG=${mock_log} MOCK_ROOT=${root} MOCK_INTERFACE_STATE=existing \
		NSCSCC_ROOT=${root} NSCSCC_PATH=${mock_bin}:/usr/bin:/bin \
		"${nscscc_check}" >"${output}" 2>&1
	assert_contains "${output}" 'PASS: MemTotal is consistent with 128 MiB DDR'
	assert_contains "${output}" 'PASS: eth0 interrupt counter increased from 10 to 13'
	assert_contains "${output}" 'nscscc_check=pass'

	cat >"${root}/proc/interrupts" <<'EOF'
           CPU0
 18:         10  LoongArch   2  eth0
EOF
	echo 0 >"${root}/sys/class/net/eth0/carrier"
	if MOCK_LOG=${mock_log} MOCK_ROOT=${root} MOCK_INTERFACE_STATE=existing \
		MOCK_PING_FAIL=1 NSCSCC_ROOT=${root} \
		NSCSCC_PATH=${mock_bin}:/usr/bin:/bin \
		"${nscscc_check}" >"${output}" 2>&1; then
		fail 'nscscc-check accepted carrier and ping failures'
	fi
	assert_contains "${output}" 'FAIL: eth0 carrier is not 1'
	assert_contains "${output}" 'FAIL: ping 10.90.50.43'
	assert_contains "${output}" 'FAIL: eth0 interrupt counter did not increase: 10 to 10'
	assert_contains "${output}" 'nscscc_check=fail failures=3'

	echo 'nscscc_check_tests=pass'
}

for path in \
	"${initramfs_network}" \
	"${buildroot_network}" \
	"${nscscc_check}" \
	"${nscscc_demo}" \
	"${init}" \
	"${rcs}" \
	"${script_dir}/initramfs-overlay/usr/bin/nscscc-board"; do
	[[ -e ${path} ]] || fail "required executable is missing: ${path}"
	dash -n "${path}"
done

[[ -L ${nscscc_demo} ]] || fail 'nscscc-demo is not a symlink to nscscc-check'

run_boot_script_checks()
{
	assert_contains "${init}" 'NFS_MOUNT_TIMEOUT=15'
	assert_contains "${init}" 'mount_devtmpfs'
	assert_contains "${init}" 'timeout "${NFS_MOUNT_TIMEOUT}" mount -t nfs'
	assert_contains "${rcs}" 'drain_console_input'
	assert_contains "${rcs}" 'nscscc.autorun=nscscc-demo'
	assert_contains "${rcs}" 'nscscc.autorun=nscscc-check'
	echo 'boot_script_checks=pass'
}

run_boot_script_checks
run_network_tests "${initramfs_network}" initramfs
run_network_tests "${buildroot_network}" buildroot
run_check_tests
echo 'userspace_service_tests=pass'
