#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0

set -euo pipefail

script_dir=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
initramfs_network=${script_dir}/initramfs-overlay/etc/init.d/S40network
buildroot_network=${script_dir}/buildroot/rootfs-overlay/etc/init.d/S41nscscc-network
nscscc_check=${script_dir}/initramfs-overlay/usr/bin/nscscc-check

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
[[ ${1:-} == read ]]
echo 'switches=0x00000000'
echo 'buttons=0x00000000'
echo 'step_buttons=0x00000000'
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
	if [[ ${name} == initramfs ]]; then
		assert_not_contains "${mock_log}" 'ip addr flush dev eth0'
	fi

	rm -f "${ready}"
	: >"${mock_log}"
	MOCK_LOG=${mock_log} MOCK_INTERFACE_STATE=existing \
		NSCSCC_ROOT=${root} NSCSCC_PATH=${mock_bin}:/usr/bin:/bin \
		"${service}" start >"${output}" 2>&1
	[[ -e ${ready} ]] || fail "${name} did not record an existing address"
	assert_contains "${output}" 'Preserving existing IPv4 configuration on eth0.'
	assert_not_contains "${mock_log}" 'ip addr flush dev eth0'
	assert_not_contains "${mock_log}" 'ip addr add 10.90.50.44/24 dev eth0'

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
	mkdir -p "${root}/proc" "${root}/sys/class/net/eth0/statistics"
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
	echo 1 >"${root}/sys/class/net/eth0/carrier"
	for statistic in rx_packets tx_packets rx_bytes tx_bytes rx_errors tx_errors; do
		echo 0 >"${root}/sys/class/net/eth0/statistics/${statistic}"
	done
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

for path in "${initramfs_network}" "${buildroot_network}" "${nscscc_check}"; do
	[[ -x ${path} ]] || fail "required executable is missing: ${path}"
	dash -n "${path}"
done

run_network_tests "${initramfs_network}" initramfs
run_network_tests "${buildroot_network}" buildroot
run_check_tests
echo 'userspace_service_tests=pass'
