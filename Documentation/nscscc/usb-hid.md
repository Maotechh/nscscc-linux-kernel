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
| CPU `intrpt` input | `6` |
| Device-tree hardware interrupt | `8` |
| Linux IRQ | `24` |
| APB clock | 100 MHz |
| UTMI clock | 60 MHz |
| Transfer types | control, bulk, interrupt |

The hardware explicitly rejects Low-Speed and isochronous transfers with
`-EOPNOTSUPP`. A mouse receiver must enumerate as Full-Speed. The HCD performs
a PHY reset during probe and polls the raw UTMI LineState because the V0.5
RTL does not drive the readable `USB_IRQ_STS.DEVICE_DETECT` bit. It keeps SOF
disabled until a real Full-Speed attachment completes reset, limits every RX
copy to both the current packet and the URB buffer, drains excess RX bytes,
and completes an active URB with `-ESHUTDOWN` on disconnect.

The current pure SpinalHDL CPU writes `intrpt[7:0]` to `ESTAT[9:2]` but always
enters at `EENTRY`; it does not apply the `ECFG.VS` hardware-vector offset.
The LoongArch32 fallback dispatcher therefore handles ECFG IP5 and IP6,
which are the PS/2 hardware interrupt 7 and USB hardware interrupt 8.

## Linux and desktop path

`CONFIG_USB_UE11_HCD=y` registers the controller from
`arch/loongarch/boot/dts/loongson/loongson32_ls.dts`. The kernel configuration
also enables `CONFIG_USB_HID`, `CONFIG_HID_GENERIC`, `CONFIG_HIDRAW`, and
`CONFIG_INPUT_EVDEV`. Buildroot enables `usbutils` and `evtest`, in addition
to the existing X.Org `evdev` driver and eudev device discovery.

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

Connection detection also needs a negative test. Boot once with no USB
device attached, wait at least two root-hub polling periods, and require that
no downstream device appears:

```sh
sleep 1
test ! -e /sys/bus/usb/devices/1-1
dmesg | grep -E 'Full-Speed device detected|Low-Speed device detected'
```

The final command must produce no attachment message in the no-device run.
For an attached receiver, require `12` from the corresponding sysfs `speed`
file. A value of `1.5` identifies a Low-Speed device, which this SIE detects
but cannot use.

The same checks are packaged in
`scripts/nscscc/validate-ue11-root-hub.sh`. Run only the mode matching the
physical attachment for that boot.

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

## Control transfer DATAx toggle semantics

The HCD verifies the received DATAx PID for IN and control-status
transactions in `ue11h_process_transfer_result()`. The USB 2.0 spec (8.5.3)
requires the control status stage to always use DATA1 regardless of the
data-stage toggle parity, and the status stage direction is opposite the
URB's data direction.

- Data-stage IN (`ep->nextpid == USB_PID_IN`): expected PID is the
  pipe-keyed toggle (`usb_gettoggle`). This is correct because the data
  stage direction equals the URB direction.
- Control status stage (`ep->nextpid == USB_PID_ACK`): expected PID is
  hard-wired to DATA1. Using the pipe-keyed toggle here reads the data-stage
  slot, which for a control write ends at DATA0 after an odd number of data
  packets and falsely rejects the DATA1 status (`-EPROTO` after three
  retries). Commit `6832b1aa4` fixed this; the behavior was introduced by
  the DATAx verification in `7407da63a`.
- `status_packet()` always transmits DATA1 for both the IN and OUT status
  forms, and the SETUP ACK path force-sets the control toggles to 1, so the
  data stage always begins with DATA1 as the spec requires.

A bogus status-stage DATA0 is still rejected (expected DATA1).

## Current limitations

The controller is a single-port Full-Speed host. The PHY can identify a
Low-Speed pull-up, but the SIE cannot perform Low-Speed transactions. It also
does not support isochronous endpoints or simultaneous independent USB ports.
The current source has passed an x86-64 GCC 8.3 LoongArch32 Reduced cross
build and link check. USB enumeration, HID events, and disconnect handling
have not been revalidated on hardware for this revision. X.Org input
discovery proves the software device path but does not prove physical LCD
output.
