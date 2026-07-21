# Buildroot desktop for the NSCSCC experiment box

## Design

The experiment box has 128 MiB of DDR, a low-frequency in-order CPU, and no
GPU or OpenGL implementation.  A GNOME installation does not fit those
constraints.  The desktop image therefore uses the following software:

- modular Xorg server;
- the `fbdev` video driver and the standard `/dev/fb0` ABI;
- the `evdev` input driver;
- Fluxbox as the window manager, toolbar, workspace manager, and application
  menu;
- XTerm with Xft, Fontconfig, and DejaVu Sans Mono;
- eudev for dynamic input-device discovery.

This provides the desktop operations needed on the board: pointer-driven
window movement and menus, keyboard input, multiple windows and workspaces,
and a graphical terminal.  It deliberately excludes compositing, OpenGL,
desktop indexing, and other services that are not practical in 128 MiB.

## Kernel interface

`CONFIG_CHIPLAB_NT35510` registers both the existing `/dev/nt35510`
diagnostic character device and an RGB565 framebuffer at `/dev/fb0`.  The
framebuffer is 480 by 800 pixels and supports the standard read, write,
ioctl, drawing, and mmap paths.  Xorg writes to a shadow framebuffer through
mmap.  Linux deferred I/O converts dirty pages to LCD row updates.

The existing character-device interface remains available for full-frame
hardware tests.  Both interfaces share the same shadow buffer and LCD
controller lock.

The kernel configuration already enables `CONFIG_INPUT_EVDEV`, PS/2 keyboard
and mouse protocol handlers, and `CONFIG_SERIO_ALTERA_PS2`.  Xorg discovers
every `/dev/input/event*` keyboard and pointer through eudev.

## Reproducible root filesystem build

Run the build on an x86-64 Linux host with the official LoongArch32 Reduced
GCC 8.3 toolchain:

```sh
scripts/nscscc/buildroot-desktop.sh \
  /absolute/path/to/buildroot-work \
  /absolute/path/to/loongarch32r-toolchain \
  /absolute/path/to/artifacts
```

The helper pins the upstream Buildroot source and the three required
`nscscc24-jit-thu/Buildroot` patches by commit, tree, and SHA256.  It writes a
compressed initramfs, an NFS-capable root filesystem tar archive, and a
manifest to the artifact directory.

The external toolchain must advertise C++, Fortran, and OpenMP because the
official Buildroot patch checks all advertised capabilities.  The post-build
script removes the unused Fortran/OpenMP libraries and eudev hardware database
from the target image.  Fluxbox retains C++ support, while the image keeps
only the DejaVu Sans and Sans Mono families used by the desktop.

For an embedded initramfs kernel, pass Buildroot's extracted target directory
to the existing kernel helper:

```sh
export ARCH=loongarch
export CROSS_COMPILE=/absolute/path/to/toolchain/bin/loongarch32r-linux-gnusf-
export NSCSCC_ARTIFACT_NAME=vmlinux-desktop
scripts/nscscc/build-kernel.sh \
  /absolute/path/to/buildroot-work/output/target \
  /absolute/path/to/kernel-output \
  /absolute/path/to/kernel-artifacts
```

The kernel helper adds the NSCSCC init and diagnostic files without removing
the Xorg, Fluxbox, eudev, font, or desktop-start files from the Buildroot
target.

## Startup and diagnosis

SysV init starts the static `10.90.50.44/24` network configuration and then
starts Xorg on `/dev/fb0`.  Fluxbox and one XTerm are started by
`/root/.xinitrc`.  Xorg is not started when `/dev/fb0` is absent, so a missing
framebuffer does not prevent the serial shell from working.

Runtime state is available through:

```sh
cat /var/log/nscscc-desktop.log
cat /run/nscscc-desktop.pid
ls -l /dev/fb0 /dev/input/event*
cat /proc/fb
cat /sys/class/graphics/fb0/{name,virtual_size,bits_per_pixel}
ps | grep -E 'Xorg|fluxbox|xterm'
```

## Hardware limits

The current SoC bitstream instantiates one Altera PS/2 controller at
`0x1fe04000`.  It can operate a PS/2 keyboard or a PS/2 mouse, but one
controller cannot operate two independent PS/2 devices simultaneously.  The
userspace and Xorg configuration already accept both devices.  Simultaneous
physical keyboard and mouse operation requires a second controller or a USB
host controller in the Chiplab system integration; it does not require a
desktop-image change.

Successful creation of `/dev/fb0` and successful Xorg startup verify the
software interface.  They do not prove that the physical LCD displays an
image.  A separate visual observation is required after the panel or LCD
hardware path is replaced.
