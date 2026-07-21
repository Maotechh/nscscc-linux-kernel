# USB HID on the NSCSCC experiment box

## Scope

The USB path is a system-integration extension for the current pure SpinalHDL
CPU. The CPU core is unchanged. Chiplab instantiates one UltraEmbedded USB
Full-Speed host and connects its UTMI interface to the experiment-box USB
PHY. The Linux tree contains the platform HCD and the standard USB HID,
`hid-generic`, `hidraw`, and `evdev` layers.

The RTL is based on UltraEmbedded `core_usb_host` commit
`81eb9f131dbb434a9047ae074fea5c31ef46ce5d`. The JIT-THU V0.5 register block
adds `USB_CTRL2` at offset `0x24`, which is used for PHY reset and TX FIFO
flush. The Chiplab bridge accepts one APB transaction at a time and crosses
the 100 MHz uncore clock to the 60 MHz UTMI clock. AXI-Lite writes send AW
before W, as required by this V0.5 register block.

The exact Chiplab patch, RTL identities, routed package pins, implementation
timing, DRC result, and bitstream identity are recorded in
[`evidence/usb-hardware-20260722.manifest`](evidence/usb-hardware-20260722.manifest).

## Address and interrupt mapping

| Resource | Value |
| --- | --- |
| USB controller physical address | `0x1fe0c000` |
| Register window | `0x1000` bytes |
| SoC interrupt input | `6` |
| Linux interrupt | `8` |
| APB clock | 100 MHz |
| UTMI clock | 60 MHz |
| Transfer types | control, bulk, interrupt |

The hardware explicitly rejects Low-Speed and isochronous transfers. A mouse
receiver must enumerate as Full-Speed. The HCD performs a PHY reset during
probe, enables the root hub and SOF generation, retries a finite number of
transfer errors, and reports RX overflow instead of indexing beyond the PIO
buffer.

## Linux and desktop path

`CONFIG_USB_UE11_HCD=y` registers the controller from
`arch/loongarch/boot/dts/loongson/loongson32_ls.dts`. The kernel configuration
also enables `CONFIG_USB_HID`, `CONFIG_HID_GENERIC`, `CONFIG_HIDRAW`, and
`CONFIG_INPUT_EVDEV`. Buildroot enables `evtest`, in addition to the existing
X.Org `evdev` driver and eudev device discovery.

After enumeration, the expected device path is:

```text
USB device -> usbh-hcd -> usbcore -> usbhid -> hid-generic
            -> input device -> /dev/input/eventX -> X.Org evdev
            -> /dev/hidrawX (raw HID access)
```

The device name, VID/PID, and event node must be taken from the actual
receiver. Do not hard-code an event number because eudev assigns it at boot.

## Hardware validation

From the Linux shell, the first checks are:

```sh
dmesg | grep -E 'ue11-hcd|full-speed USB|New USB device|hid-generic'
lsusb
cat /proc/bus/input/devices
ls -l /dev/hidraw* /dev/input/event*
cat /proc/interrupts
```

Find the event node whose `Handlers` line contains `mouse`, then record both
movement and button events. `evtest` prints the decoded Linux input ABI and is
the preferred evidence source:

```sh
evtest /dev/input/eventX
```

Move the physical mouse and press and release the left button during the
capture. Evidence must include `EV_REL` with `REL_X` or `REL_Y`, and
`EV_KEY` with `BTN_LEFT`. The X.Org log must contain evdev input discovery,
and the Fluxbox desktop must remain running after the capture.

The USB controller interrupt counter must increase during enumeration and
interrupt polling. A successful Linux boot without a USB descriptor, HID
input node, or event record is not a successful mouse validation.

## Rebuild procedure

1. Build the Chiplab system integration with Vivado 2023.2, CPU 40 MHz and
   uncore 100 MHz. Require WNS at least zero, TNS zero, and zero DRC errors.
2. Query the routed checkpoint for the UTMI package pins. The source XDC is
   not sufficient evidence by itself.
3. Build the kernel and the Buildroot desktop image in independent output
   directories on EPYC2. Keep the debug `vmlinux` and its stripped TFTP copy.
4. Recalculate the manifest SHA256 and CRC32 after every transfer.
5. Program the FPGA, boot with U-Boot TFTP and `bootelf -p`, and capture the
   serial and status logs. Repeat from FPGA programming for a second run.

The Chiplab changes stay in a system-integration worktree. Only the kernel
source, desktop configuration, validation scripts, and evidence are published
in this repository. No CPU implementation or Linux UAPI changes are required.

## Current limitations

The controller is a single-port Full-Speed host. It does not support
Low-Speed devices, isochronous endpoints, or simultaneous independent USB
ports. A receiver that does not enumerate must first be checked with
another known Full-Speed HID device, then classified using the PHY, UTMI,
controller interrupt, and descriptor logs. X.Org input discovery proves the
software device path but does not prove physical LCD output.
