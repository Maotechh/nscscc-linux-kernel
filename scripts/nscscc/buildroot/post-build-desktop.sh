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

# eudev rules are sufficient for input discovery.  The hardware database is
# not used by this fixed board and is several megabytes when generated.
rm -f "${target_dir}/etc/udev/hwdb.bin"
rm -f "${target_dir}"/etc/udev/hwdb.d/*.hwdb
