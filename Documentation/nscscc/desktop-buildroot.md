# Buildroot desktop for the NSCSCC experiment box

## Design

The experiment box has 128 MiB of DDR, a low-frequency in-order CPU, and no
GPU or OpenGL implementation.  A GNOME installation does not fit those
constraints.  The desktop image therefore uses the following software:

- modular Xorg server;
- the `fbdev` video driver and the standard `/dev/fb0` ABI;
- the `evdev` input driver;
- `evtest` for decoded keyboard and pointer event capture;
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

The kernel configuration enables `CONFIG_INPUT_EVDEV`, PS/2 keyboard and
mouse protocol handlers, `CONFIG_SERIO_ALTERA_PS2`, the UE11 USB host,
generic USB HID, and `hidraw`. Xorg discovers every `/dev/input/event*`
keyboard and pointer through eudev.

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
manifest to the artifact directory.  The manifest also records the BusyBox
version, source archive, configuration, binary identity, and the ELF identity
of all desktop executables and Xorg drivers used by the image.

The external toolchain must advertise C++, Fortran, and OpenMP because the
official Buildroot patch checks all advertised capabilities.  The post-build
script removes the unused Fortran/OpenMP libraries and eudev hardware database
from the target image.  Fluxbox retains C++ support, while the image keeps
only the DejaVu Sans and Sans Mono families used by the desktop.

The GCC 8.3 runtime loader searches `/usr/lib32/sf`, which resolves to
`/usr/lib` in this image, while Buildroot installs glibc runtime libraries in
`/lib`.  The post-build script adds relative links in `/usr/lib` for every
runtime library in `/lib`, then verifies the `DT_NEEDED` entries for Xorg,
Fluxbox, XTerm, fbdev, evdev, fbdevhw, and shadow.  This is required for both
Xorg and eudev; setting a library path only in the desktop service would leave
input-device discovery unavailable.

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
framebuffer does not prevent the serial shell from working.  The post-build
step removes Buildroot's generic `S40xorg` service because
`S99nscscc-desktop` is the sole owner of Xorg startup and logging.
The Xorg configuration explicitly loads `fbdevhw` and `shadow` before the
fbdev video driver.  The LA32R module loader otherwise rejects
`fbdev_drv.so` before that driver can request its own helper modules.

Runtime state is available through:

```sh
cat /var/log/nscscc-desktop.log
cat /run/nscscc-desktop.pid
ls -l /dev/fb0 /dev/input/event*
lsusb
cat /proc/bus/input/devices
evtest /dev/input/eventX
cat /proc/fb
cat /sys/class/graphics/fb0/{name,virtual_size,bits_per_pixel}
ps | grep -E 'Xorg|fluxbox|xterm|udevd'
```

## Hardware limits

The image includes `usbutils` for `lsusb` and `evtest` for decoded input
events. The USB system-integration bitstream instantiates one Full-Speed host at
`0x1fe0c000`, in addition to the Altera PS/2 controller at `0x1fe04000`.
The PS/2 controller can operate one PS/2 keyboard or mouse. A Full-Speed USB
receiver provides the independent mouse path. The UE11 controller does not
support Low-Speed or isochronous transfers, so device speed must be confirmed
from the enumeration log.

Detailed hardware, kernel, and event validation instructions are in
[`usb-hid.md`](usb-hid.md).

Successful creation of `/dev/fb0` and successful Xorg startup verify the
software interface.  They do not prove that the physical LCD displays an
image.  A separate visual observation is required after the panel or LCD
hardware path is replaced.
