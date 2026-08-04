#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0

set -euo pipefail

usage() {
	cat <<'EOF'
Usage: buildroot-desktop.sh WORK_DIR TOOLCHAIN_DIR ARTIFACT_DIR

Build the pinned NSCSCC LA32R Xorg/Fluxbox root filesystem. WORK_DIR is a
dedicated directory used for Buildroot source, downloads, output, and a copy
of the rootfs overlay. TOOLCHAIN_DIR must contain bin/loongarch32r-linux-
gnusf-gcc. ARTIFACT_DIR receives rootfs archives and a manifest.

Environment variables:
  NSCSCC_BUILD_JOBS         Parallel build jobs (default: nproc)
  NSCSCC_TOOLCHAIN_ARCHIVE  Optional original toolchain archive to hash
  NSCSCC_REUSE_OUTPUT       Reuse an already completed clean output (0 or 1)
EOF
}

if [[ $# -ne 3 ]]; then
	usage >&2
	exit 2
fi

work_dir=$1
toolchain_dir=$2
artifact_dir=$3
jobs=${NSCSCC_BUILD_JOBS:-$(nproc)}
toolchain_archive=${NSCSCC_TOOLCHAIN_ARCHIVE:-}
reuse_output=${NSCSCC_REUSE_OUTPUT:-0}
script_dir=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
config_dir=${script_dir}/buildroot
defconfig=${config_dir}/nscscc_desktop_defconfig
overlay_source=${config_dir}/rootfs-overlay
post_build_script=${config_dir}/post-build-desktop.sh
wallpaper_relative=usr/share/backgrounds/nscscc-hatsune-miku.jpg
wallpaper_source=${overlay_source}/${wallpaper_relative}
wallpaper_original_sha256=55167d74d99e7d78f9c9ae4b2445ac180af7eecc3ba5f1d89c7083f43e172cf4
wallpaper_expected_sha256=d358f208dbe0af79e6ecd9f30839a68c5a7bb912922b9b2ff1f0344cc32cff30

buildroot_commit=3ebc7c69d56430c34eba4c869d1d4fe4d1e8de55
patch_repo_commit=5b73cf2f9247502fc16835f14c6a4c3edc0e88e9
patched_buildroot_tree=ba583e6a067a16316aaaff1d6a084a56b548d359
busybox_version=1.36.1
usbutils_version=017
usbutils_conf_env='LIBS="-lusb-1.0 -ludev"'

patch_names=(
	0001-loongarch-add-arch-support-for-LoongArch-32bit-Reduc.patch
	0002-package-temporarily-disable-the-gcc-wrappers-prefix-.patch
	0007-libpng-disable-the-vector-insn-of-loongarch-platform.patch
)
patch_hashes=(
	13d70982554aee709d70b7bd18ef624c1e445bb2faa7c49fa9309b7a56b9ec46
	7866fa2cce4bcb56abc852456f0136046335de307bb943ee85cedb746b526acd
	a75db4a3530c3d06a6d1ae124420d28135b01cbe2415ca1ad9cd817cb806ed55
)

for command in git make python3 sha256sum stat tar uname; do
	if ! command -v "${command}" >/dev/null 2>&1; then
		echo "Required command not found: ${command}" >&2
		exit 1
	fi
done
if [[ -n ${toolchain_archive} && ! -f ${toolchain_archive} ]]; then
	echo "Toolchain archive is not a file: ${toolchain_archive}" >&2
	exit 1
fi
if [[ ${reuse_output} != 0 && ${reuse_output} != 1 ]]; then
	echo "NSCSCC_REUSE_OUTPUT must be 0 or 1" >&2
	exit 1
fi
for path in "${defconfig}" "${overlay_source}" "${post_build_script}" \
	"${wallpaper_source}"; do
	if [[ ! -e ${path} ]]; then
		echo "Required desktop input is missing: ${path}" >&2
		exit 1
	fi
done
actual_wallpaper_sha256=$(sha256sum "${wallpaper_source}" | awk '{print $1}')
if [[ ${actual_wallpaper_sha256} != "${wallpaper_expected_sha256}" ]]; then
	echo "Wallpaper hash mismatch: ${wallpaper_source}" >&2
	exit 1
fi

cross_compile=${toolchain_dir}/bin/loongarch32r-linux-gnusf-
for tool in gcc readelf strip; do
	if [[ ! -x ${cross_compile}${tool} ]]; then
		echo "Toolchain command not found: ${cross_compile}${tool}" >&2
		exit 1
	fi
done

mkdir -p "${work_dir}" "${artifact_dir}"
work_dir=$(CDPATH= cd -- "${work_dir}" && pwd)
artifact_dir=$(CDPATH= cd -- "${artifact_dir}" && pwd)
toolchain_dir=$(CDPATH= cd -- "${toolchain_dir}" && pwd)
source_dir=${work_dir}/buildroot-source
patch_dir=${work_dir}/jit-thu-patches
output_dir=${work_dir}/output
overlay_dir=${work_dir}/rootfs-overlay

if [[ ! -d ${patch_dir}/.git ]]; then
	git clone --filter=blob:none \
		https://github.com/nscscc24-jit-thu/Buildroot.git "${patch_dir}"
fi
git -C "${patch_dir}" checkout --detach "${patch_repo_commit}"

for i in "${!patch_names[@]}"; do
	patch=${patch_dir}/${patch_names[$i]}
	actual=$(sha256sum "${patch}" | awk '{print $1}')
	if [[ ${actual} != "${patch_hashes[$i]}" ]]; then
		echo "Patch hash mismatch: ${patch}" >&2
		exit 1
	fi
done

if [[ ! -d ${source_dir}/.git ]]; then
	git clone --filter=blob:none https://github.com/buildroot/buildroot.git \
		"${source_dir}"
	git -C "${source_dir}" checkout --detach "${buildroot_commit}"
	git -C "${source_dir}" am \
		"${patch_dir}/${patch_names[0]}" \
		"${patch_dir}/${patch_names[1]}" \
		"${patch_dir}/${patch_names[2]}"
fi

actual_source_commit=$(git -C "${source_dir}" rev-parse HEAD)
actual_source_tree=$(git -C "${source_dir}" rev-parse 'HEAD^{tree}')
if [[ ${actual_source_tree} != "${patched_buildroot_tree}" ]]; then
	echo "Unexpected patched Buildroot tree: ${actual_source_tree}" >&2
	exit 1
fi
if ! git -C "${source_dir}" diff --quiet --ignore-submodules --; then
	echo "Buildroot source contains tracked changes: ${source_dir}" >&2
	exit 1
fi

if [[ ${reuse_output} == 0 ]]; then
	rm -rf "${output_dir}" "${overlay_dir}"
	mkdir -p "${output_dir}" "${overlay_dir}"
	cp -a "${overlay_source}/." "${overlay_dir}/"
	mkdir -p "${overlay_dir}/etc/nscscc"
	wallpaper_size=$(stat -c '%s' "${wallpaper_source}")
	wallpaper_sha256=$(sha256sum "${wallpaper_source}" | awk '{print $1}')
	cat >"${overlay_dir}/etc/nscscc/desktop-build-info" <<EOF
BUILDROOT_COMMIT=${buildroot_commit}
PATCHED_BUILDROOT_TREE=${patched_buildroot_tree}
JIT_THU_PATCH_REPO_COMMIT=${patch_repo_commit}
DESKTOP_STACK=Xorg-fbdev-evdev-Fluxbox-XTerm-Feh
WALLPAPER=/${wallpaper_relative}
WALLPAPER_SIZE=${wallpaper_size}
WALLPAPER_SHA256=${wallpaper_sha256}
WALLPAPER_ORIGINAL_SHA256=${wallpaper_original_sha256}
USBUTILS_LINK_LIBRARIES=libusb-1.0,libudev
EOF
	chmod 0755 \
		"${overlay_dir}/etc/init.d/S41nscscc-network" \
		"${overlay_dir}/etc/init.d/S99nscscc-desktop" \
		"${overlay_dir}/root/.xinitrc"
	chmod 0644 "${overlay_dir}/etc/nscscc/desktop-build-info"

	make -C "${source_dir}" O="${output_dir}" \
		BR2_DEFCONFIG="${defconfig}" defconfig
	"${source_dir}/utils/config" --file "${output_dir}/.config" \
		--set-str BR2_TOOLCHAIN_EXTERNAL_PATH "${toolchain_dir}"
	"${source_dir}/utils/config" --file "${output_dir}/.config" \
		--set-str BR2_ROOTFS_OVERLAY "${overlay_dir}"
	"${source_dir}/utils/config" --file "${output_dir}/.config" \
		--set-str BR2_ROOTFS_POST_BUILD_SCRIPT "${post_build_script}"
	"${source_dir}/utils/config" --file "${output_dir}/.config" \
		--set-str BR2_ROOTFS_POST_FAKEROOT_SCRIPT "${post_build_script}"
	make -C "${source_dir}" O="${output_dir}" olddefconfig
	# The external LA32R linker does not follow libusb's libudev dependency
	# from sysroot/lib unless usbutils names both shared libraries.
	make -C "${source_dir}" O="${output_dir}" \
		USBUTILS_CONF_ENV="${usbutils_conf_env}" -j"${jobs}"
elif [[ ! -d ${output_dir}/target ]]; then
	echo "Cannot reuse missing output directory: ${output_dir}" >&2
	exit 1
fi

rootfs_cpio=${output_dir}/images/rootfs.cpio.gz
rootfs_tar=${output_dir}/images/rootfs.tar
target_dir=${output_dir}/target
busybox_build_dir=${output_dir}/build/busybox-${busybox_version}
busybox_source=${source_dir}/dl/busybox/busybox-${busybox_version}.tar.bz2
for path in "${rootfs_cpio}" "${rootfs_tar}" \
	"${busybox_build_dir}/.config" "${busybox_source}" \
	"${target_dir}/bin/busybox" \
	"${target_dir}/usr/bin/lsusb" \
	"${target_dir}/usr/bin/Xorg" "${target_dir}/usr/bin/xinit" \
	"${target_dir}/usr/bin/fluxbox" "${target_dir}/usr/bin/xterm" \
	"${target_dir}/usr/bin/feh" \
	"${target_dir}/usr/lib/libImlib2.so.1" \
	"${target_dir}/usr/lib/imlib2/loaders/jpeg.so" \
	"${target_dir}/usr/lib/xorg/modules/drivers/fbdev_drv.so" \
	"${target_dir}/usr/lib/xorg/modules/input/evdev_drv.so" \
	"${target_dir}/usr/lib/xorg/modules/libfbdevhw.so" \
	"${target_dir}/usr/lib/xorg/modules/libshadow.so" \
	"${target_dir}/${wallpaper_relative}" \
	"${target_dir}/etc/nscscc/desktop-build-info"; do
	if [[ ! -e ${path} ]]; then
		echo "Desktop build output is missing: ${path}" >&2
		exit 1
	fi
done

# host-eudev can rebuild hwdb.bin in a target-finalize hook after the normal
# post-build hook.  The post-fakeroot hook cleans the image copy; repeat the
# same cleanup on target/ because build-kernel.sh consumes that directory.
"${post_build_script}" "${target_dir}"

unwanted_runtime=()
if [[ -e ${target_dir}/etc/udev/hwdb.bin ]]; then
	unwanted_runtime+=("${target_dir}/etc/udev/hwdb.bin")
fi
if [[ -e ${target_dir}/etc/init.d/S40xorg ]]; then
	unwanted_runtime+=("${target_dir}/etc/init.d/S40xorg")
fi
shopt -s nullglob
unwanted_runtime+=(
	"${target_dir}"/lib/libgfortran.so*
	"${target_dir}"/usr/lib/libgfortran.so*
	"${target_dir}"/lib/libgomp.so*
	"${target_dir}"/usr/lib/libgomp.so*
	"${target_dir}"/etc/udev/hwdb.d/*.hwdb
)
shopt -u nullglob
if (( ${#unwanted_runtime[@]} != 0 )); then
	echo "Unexpected unused desktop runtime files:" >&2
	printf '  %s\n' "${unwanted_runtime[@]}" >&2
	exit 1
fi

runtime_paths=(
	"${target_dir}/usr/bin/Xorg"
	"${target_dir}/usr/bin/evtest"
	"${target_dir}/usr/bin/lsusb"
	"${target_dir}/usr/bin/fluxbox"
	"${target_dir}/usr/bin/xterm"
	"${target_dir}/usr/bin/feh"
	"${target_dir}/usr/lib/libImlib2.so.1"
	"${target_dir}/usr/lib/imlib2/loaders/jpeg.so"
	"${target_dir}/usr/lib/xorg/modules/drivers/fbdev_drv.so"
	"${target_dir}/usr/lib/xorg/modules/input/evdev_drv.so"
	"${target_dir}/usr/lib/xorg/modules/libfbdevhw.so"
	"${target_dir}/usr/lib/xorg/modules/libshadow.so"
)
for path in "${runtime_paths[@]}"; do
	while read -r needed; do
		if [[ ! -e ${target_dir}/usr/lib/${needed} ]]; then
			echo "Runtime dependency is outside the loader search path: ${path}: ${needed}" >&2
			exit 1
		fi
	done < <("${cross_compile}readelf" -d "${path}" |
		awk -F'[][]' '/NEEDED/{print $2}')
done
if ! grep -Fq 'Load "fbdevhw"' "${target_dir}/etc/X11/xorg.conf" ||
	! grep -Fq 'Load "shadow"' "${target_dir}/etc/X11/xorg.conf"; then
	echo "Xorg config must preload fbdevhw and shadow before fbdev_drv.so" >&2
	exit 1
fi

name=nscscc-desktop-${buildroot_commit:0:10}
cpio_artifact=${artifact_dir}/${name}.cpio.gz
tar_artifact=${artifact_dir}/${name}.tar
install -m 0644 "${rootfs_cpio}" "${cpio_artifact}"
install -m 0644 "${rootfs_tar}" "${tar_artifact}"

cpio_size=$(stat -c '%s' "${cpio_artifact}")
tar_size=$(stat -c '%s' "${tar_artifact}")
cpio_sha256=$(sha256sum "${cpio_artifact}" | awk '{print $1}')
tar_sha256=$(sha256sum "${tar_artifact}" | awk '{print $1}')
cpio_crc32=$(python3 - "${cpio_artifact}" <<'PY'
import pathlib
import sys
import zlib

data = pathlib.Path(sys.argv[1]).read_bytes()
print(f"{zlib.crc32(data) & 0xffffffff:08x}")
PY
)
tar_crc32=$(python3 - "${tar_artifact}" <<'PY'
import pathlib
import sys
import zlib

data = pathlib.Path(sys.argv[1]).read_bytes()
print(f"{zlib.crc32(data) & 0xffffffff:08x}")
PY
)
target_bytes=$(du -sb "${target_dir}" | awk '{print $1}')
toolchain_version=$("${cross_compile}gcc" -dumpfullversion -dumpversion)
toolchain_gcc_sha256=$(sha256sum "${cross_compile}gcc" | awk '{print $1}')
toolchain_archive_size=unavailable
toolchain_archive_sha256=unavailable
if [[ -n ${toolchain_archive} ]]; then
	toolchain_archive=$(CDPATH= cd -- "$(dirname -- "${toolchain_archive}")" && pwd)/$(basename -- "${toolchain_archive}")
	toolchain_archive_size=$(stat -c '%s' "${toolchain_archive}")
	toolchain_archive_sha256=$(sha256sum "${toolchain_archive}" | awk '{print $1}')
fi
defconfig_sha256=$(sha256sum "${defconfig}" | awk '{print $1}')
post_build_sha256=$(sha256sum "${post_build_script}" | awk '{print $1}')
overlay_sha256=$(tar --sort=name --mtime=@0 --owner=0 --group=0 \
	--numeric-owner -C "${overlay_dir}" -cf - . | sha256sum | awk '{print $1}')
busybox_source_sha256=$(sha256sum "${busybox_source}" | awk '{print $1}')
busybox_config_sha256=$(sha256sum "${busybox_build_dir}/.config" | awk '{print $1}')
busybox_size=$(stat -c '%s' "${target_dir}/bin/busybox")
wallpaper_path=${target_dir}/${wallpaper_relative}
wallpaper_size=$(stat -c '%s' "${wallpaper_path}")
wallpaper_sha256=$(sha256sum "${wallpaper_path}" | awk '{print $1}')
component_names=(busybox xorg evtest lsusb fluxbox xterm feh imlib2 imlib2_jpeg fbdev evdev fbdevhw shadow)
component_paths=(
	"${target_dir}/bin/busybox"
	"${target_dir}/usr/bin/Xorg"
	"${target_dir}/usr/bin/evtest"
	"${target_dir}/usr/bin/lsusb"
	"${target_dir}/usr/bin/fluxbox"
	"${target_dir}/usr/bin/xterm"
	"${target_dir}/usr/bin/feh"
	"${target_dir}/usr/lib/libImlib2.so.1"
	"${target_dir}/usr/lib/imlib2/loaders/jpeg.so"
	"${target_dir}/usr/lib/xorg/modules/drivers/fbdev_drv.so"
	"${target_dir}/usr/lib/xorg/modules/input/evdev_drv.so"
	"${target_dir}/usr/lib/xorg/modules/libfbdevhw.so"
	"${target_dir}/usr/lib/xorg/modules/libshadow.so"
)
for i in "${!component_names[@]}"; do
	component=${component_names[$i]}
	path=${component_paths[$i]}
	class=$("${cross_compile}readelf" -h "${path}" |
		awk -F: '/Class:/{gsub(/^[[:space:]]+/, "", $2); print $2}')
	machine=$("${cross_compile}readelf" -h "${path}" |
		awk -F: '/Machine:/{gsub(/^[[:space:]]+/, "", $2); print $2}')
	digest=$(sha256sum "${path}" | awk '{print $1}')
	if [[ ${class} != ELF32 || ${machine} != LoongArch ]]; then
		echo "Unexpected ${component} ELF identity: ${class} ${machine}" >&2
		exit 1
	fi
	printf -v "${component}_class" '%s' "${class}"
	printf -v "${component}_machine" '%s' "${machine}"
	printf -v "${component}_sha256" '%s' "${digest}"
done

manifest=${artifact_dir}/${name}.manifest
cat >"${manifest}" <<EOF
buildroot_commit=${buildroot_commit}
patched_buildroot_commit=${actual_source_commit}
patched_buildroot_tree=${patched_buildroot_tree}
jit_thu_patch_repo_commit=${patch_repo_commit}
patch_0001_sha256=${patch_hashes[0]}
patch_0002_sha256=${patch_hashes[1]}
patch_0007_sha256=${patch_hashes[2]}
defconfig=${defconfig}
defconfig_sha256=${defconfig_sha256}
post_build_script=${post_build_script}
post_build_script_sha256=${post_build_sha256}
overlay=${overlay_source}
overlay_sha256=${overlay_sha256}
busybox_version=${busybox_version}
busybox_source=${busybox_source}
busybox_source_sha256=${busybox_source_sha256}
busybox_config=${busybox_build_dir}/.config
busybox_config_sha256=${busybox_config_sha256}
busybox_size=${busybox_size}
busybox_elf_class=${busybox_class}
busybox_elf_machine=${busybox_machine}
busybox_sha256=${busybox_sha256}
usbutils_version=${usbutils_version}
usbutils_link_libraries=libusb-1.0,libudev
wallpaper=/${wallpaper_relative}
wallpaper_size=${wallpaper_size}
wallpaper_sha256=${wallpaper_sha256}
wallpaper_original_sha256=${wallpaper_original_sha256}
wallpaper_source_sha256=${wallpaper_expected_sha256}
build_host_arch=$(uname -m)
toolchain=${toolchain_dir}
toolchain_version=${toolchain_version}
toolchain_gcc_sha256=${toolchain_gcc_sha256}
toolchain_archive=${toolchain_archive:-unavailable}
toolchain_archive_size=${toolchain_archive_size}
toolchain_archive_sha256=${toolchain_archive_sha256}
target_uncompressed_bytes=${target_bytes}
cpio=${cpio_artifact}
cpio_size=${cpio_size}
cpio_sha256=${cpio_sha256}
cpio_crc32=${cpio_crc32}
tar=${tar_artifact}
tar_size=${tar_size}
tar_sha256=${tar_sha256}
tar_crc32=${tar_crc32}
xorg_elf_class=${xorg_class}
xorg_elf_machine=${xorg_machine}
xorg_sha256=${xorg_sha256}
evtest_elf_class=${evtest_class}
evtest_elf_machine=${evtest_machine}
evtest_sha256=${evtest_sha256}
lsusb_elf_class=${lsusb_class}
lsusb_elf_machine=${lsusb_machine}
lsusb_sha256=${lsusb_sha256}
fluxbox_elf_class=${fluxbox_class}
fluxbox_elf_machine=${fluxbox_machine}
fluxbox_sha256=${fluxbox_sha256}
xterm_elf_class=${xterm_class}
xterm_elf_machine=${xterm_machine}
xterm_sha256=${xterm_sha256}
feh_elf_class=${feh_class}
feh_elf_machine=${feh_machine}
feh_sha256=${feh_sha256}
imlib2_elf_class=${imlib2_class}
imlib2_elf_machine=${imlib2_machine}
imlib2_sha256=${imlib2_sha256}
imlib2_jpeg_elf_class=${imlib2_jpeg_class}
imlib2_jpeg_elf_machine=${imlib2_jpeg_machine}
imlib2_jpeg_sha256=${imlib2_jpeg_sha256}
fbdev_elf_class=${fbdev_class}
fbdev_elf_machine=${fbdev_machine}
fbdev_sha256=${fbdev_sha256}
evdev_elf_class=${evdev_class}
evdev_elf_machine=${evdev_machine}
evdev_sha256=${evdev_sha256}
fbdevhw_elf_class=${fbdevhw_class}
fbdevhw_elf_machine=${fbdevhw_machine}
fbdevhw_sha256=${fbdevhw_sha256}
shadow_elf_class=${shadow_class}
shadow_elf_machine=${shadow_machine}
shadow_sha256=${shadow_sha256}
EOF

cat "${manifest}"
