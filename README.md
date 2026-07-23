# nscscc-linux

2026 龙芯杯团体赛 Linux 内核，fork 自
[loongson-edu/la32r-Linux](https://gitee.com/loongson-edu/la32r-Linux) 的
`la32r-new-world` 分支。当前 main 面向 NSCSCC 实验箱的 100 MHz UART、
DMFE、confreg、NT35510 framebuffer、PS/2 和 USB Full-Speed 控制器。

## 当前 main 已实现

- 保留原有 UART clock 修正：device tree 和 NS16550 使用 `100000000`，并
  修复 `serial.c` 中覆盖 `uartclk` 的 `memset` 问题。
- 内嵌可重复构建的 Buildroot initramfs，包含静态 BusyBox、`/init`、网络
  工具和 `/bin/sh`。
- NT35510 character device 与 `480x800 RGB565` framebuffer，设备节点为
  `/dev/nt35510` 和 `/dev/fb0`。
- X.Org、fbdev、evdev、eudev、Fluxbox 和 XTerm 的轻量 X11 桌面。它不是
  GNOME，也不依赖 GPU 或 OpenGL，适合实验箱的 128 MiB DDR。
- PS/2 serio、keyboard 和 mouse protocol 支持，以及 Linux evdev 接口。
- UE11 USB Full-Speed host、USB HID、`hid-generic`、`hidraw`、evdev 和
  Buildroot `usbutils`／`evtest`，用于 USB 鼠标接收器和 X.Org 输入。
- build-info、kernel artifact、BusyBox、initramfs 和 ELF load address 的
  manifest，便于校验不同主机之间的文件身份。

PS/2 的 Chiplab patch、controller 来源、寄存器 ABI 和自动仿真说明见
[`Documentation/nscscc/chiplab-ps2-controller.md`](Documentation/nscscc/chiplab-ps2-controller.md)。
所有实际复制或修改后复用的第三方代码见
[`Documentation/nscscc/third-party-code.md`](Documentation/nscscc/third-party-code.md)。

## 最近 main 变更

从 GitHub baseline `518625445067c9265b8ba38fbc9b43491fdea006` 到 desktop
validation commit `7236be01b06768938ad1439209256f2aa966ad62`：

- `3118ab6ff`：加入 framebuffer desktop image、X.Org 配置、Fluxbox、XTerm、
  eudev 和桌面启动脚本。
- `721f911cc`、`95818723b`、`cc75d34b1`：记录 userspace 身份，修正启动
  用户、runtime loader、Xorg 模块加载和启动等待逻辑。
- `0605fbd80`、`3d8e8c8e3`：固定内嵌 initramfs 路径和 kernel build timestamp，
  使两个独立输出可重复。
- `7c5518b35`、`9dc187ead`：增加 NT35510 full-frame data path 检查，并兼容
  BusyBox 的 `1+0 records out` 输出。
- `7236be01b`：加入 EPYC2 reproducibility 记录和两次完整 FPGA Linux 桌面
  验证证据。

## 构建

构建应在 x86-64 Linux 主机（例如 EPYC2）完成，使用官方 LoongArch32
Reduced GCC 8.3 toolchain：

```bash
export ARCH=loongarch
export CROSS_COMPILE=/path/to/toolchain/bin/loongarch32r-linux-gnusf-

scripts/nscscc/buildroot-desktop.sh \
  /absolute/path/to/buildroot-work \
  /absolute/path/to/toolchain \
  /absolute/path/to/buildroot-artifacts

scripts/nscscc/build-kernel.sh \
  /absolute/path/to/buildroot-work/output/target \
  /absolute/path/to/kernel-output \
  /absolute/path/to/kernel-artifacts
```

桌面 image 的构建细节、Buildroot patch identity、runtime loader 处理和
initramfs 约束见 [`Documentation/nscscc/desktop-buildroot.md`](Documentation/nscscc/desktop-buildroot.md)。
USB RTL、kernel、HID 和 input event 的映射及验证方法见
[`Documentation/nscscc/usb-hid.md`](Documentation/nscscc/usb-hid.md)。
当前 USB bitstream 的 Chiplab patch、RTL 与约束文件 SHA256、routed
package pin、时序、DRC 和文件身份见
[`Documentation/nscscc/evidence/usb-hardware-20260722.manifest`](Documentation/nscscc/evidence/usb-hardware-20260722.manifest)。

## U-Boot TFTP 启动

Windows Tftpd32 root 使用 `10.90.50.43`，实验箱使用 `10.90.50.44`。只有在
TFTP 字节数和 CRC32 与 manifest 一致时才运行 `bootelf`：

```text
setenv ipaddr 10.90.50.44
setenv serverip 10.90.50.43
setenv netmask 255.255.255.0
setenv ethaddr 00:98:76:64:32:19
ping 10.90.50.43
tftpboot 0xa3000000 vmlinux-7c5518b35-desktop
crc32 0xa3000000 ${filesize}
bootelf -p 0xa3000000 g console=ttyS0,115200 rdinit=/init loglevel=8
```

当前 verified artifact：

```text
size=30595600
sha256=830afcbb91ebb98e871a0645d6c08448b2ea4a2201fb33853afab872acadb978
crc32=13433a3f
entry=0xa0b8d6d0
first_load=0xa0300000
tftp_address=0xa3000000
```

## 2026-07-22 硬件验证

从 FPGA programming 开始连续完成两次独立运行。两次均通过 Vivado
2023.2、TFTP、U-Boot CRC32、Linux shell、DMFE、confreg、PS/2 idle、
`/dev/nt35510` full-frame write、`/dev/fb0`、X.Org、Fluxbox 和 XTerm 检查。
两次 TFTP 都传输 `30595600` 字节，Tftpd32 记录 `0 blk resent`，validator
返回 `result=success`。

详细报告见
[`Documentation/nscscc/hardware-validation-desktop-20260722.md`](Documentation/nscscc/hardware-validation-desktop-20260722.md)，
artifact contract 见
[`Documentation/nscscc/evidence/vmlinux-7c5518b35-desktop.manifest`](Documentation/nscscc/evidence/vmlinux-7c5518b35-desktop.manifest)。

## 当前限制

- framebuffer 和 NT35510 写入证明 Linux device path 与 framebuffer ABI，不能
  代替物理观察。当前 `panel_status=not_observed`，没有宣称 LCD 已显示图像。
- 本次验证没有连接 PS/2 keyboard 或 mouse，因此没有宣称 key event、pointer
  event 或实际输入操作已经通过。新的双向 PS/2 controller 已通过 keyboard
  reset、`0xfa` ACK、`0xaa` BAT、FIFO 和 interrupt 仿真，但尚未在实物键盘上
  验证。
- 单个 PS/2 controller 不能同时连接两个独立 PS/2 设备。USB
  Full-Speed host 为鼠标接收器提供独立输入。
- UE11 controller 不支持 Low-Speed 和 isochronous transfer。接收器必须
  以 Full-Speed 枚举。
- 当前 USB revision 已通过 EPYC2 的 LoongArch32 Reduced 全量 kernel build、
  `W=1` object build 和 `vmlinux` symbol 检查，但按当前要求没有连接实验箱，
  因此没有宣称 USB descriptor、HID event 或 disconnect 实物验证已经通过。

## 依赖

- 交叉工具链：`loongarch32r-linux-gnusf-`，GCC 8.3.0。
- 主机工具：`flex`、`bison`、`bc`、`rsync`、`libssl-dev`。
- Buildroot source 和 `nscscc24-jit-thu/Buildroot` patch，详见 desktop
  build document。
