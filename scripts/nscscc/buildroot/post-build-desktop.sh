#!/bin/sh

set -eu

target_dir=${1:?target directory is required}

# The external compiler must advertise every supported language to Buildroot,
# but this image has no Fortran or OpenMP application.  Remove those runtime
# libraries after package installation so they do not consume DDR or initramfs
# space.
rm -f \
	"${target_dir}"/lib/libgfortran.so* \
	"${target_dir}"/usr/lib/libgfortran.so* \
	"${target_dir}"/lib/libgomp.so* \
	"${target_dir}"/usr/lib/libgomp.so*

# The official LA32R toolchain searches /usr/lib32/sf, which resolves to
# /usr/lib in this Buildroot image.  Buildroot installs the glibc runtime in
# /lib, so expose those versioned libraries through the searched directory.
# Without these links, dynamic executables fail before main() with a missing
# libudev.so.1 or libc.so.6 even though the files exist in /lib.
for library in "${target_dir}"/lib/*.so*; do
	[ -e "${library}" ] || continue
	name=${library##*/}
	if [ ! -e "${target_dir}/usr/lib/${name}" ] && \
		[ ! -L "${target_dir}/usr/lib/${name}" ]; then
		ln -s "../../lib/${name}" "${target_dir}/usr/lib/${name}"
	fi
done

# eudev rules are sufficient for input discovery.  The hardware database is
# not used by this fixed board and is several megabytes when generated.
rm -f "${target_dir}/etc/udev/hwdb.bin"
rm -f "${target_dir}"/etc/udev/hwdb.d/*.hwdb

# Xorg's package script installs a generic S40xorg service unconditionally.
# The NSCSCC service owns Xorg, Fluxbox, XTerm, logging, and stale-socket
# cleanup, so running both services would start two servers on display :0.
rm -f "${target_dir}/etc/init.d/S40xorg"
