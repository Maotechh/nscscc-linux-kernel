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
- 可选的 NFSv3 root 启动方式。内核仍然保留 recovery initramfs，网络或者
  NFS mount 失败时继续进入原有串口 shell。
- build-info、kernel artifact、BusyBox、initramfs 和 ELF load address 的
  manifest，便于校验不同主机之间的文件身份。

PS/2 的 Chiplab patch、controller 来源、寄存器 ABI 和自动仿真说明见
[`Documentation/nscscc/chiplab-ps2-controller.md`](Documentation/nscscc/chiplab-ps2-controller.md)。
所有实际复制或修改后复用的第三方代码见
[`Documentation/nscscc/third-party-code.md`](Documentation/nscscc/third-party-code.md)。
官方评分条件、当前已确认项目和仍需等待组委会发布的 Linux 指定操作见
[`Documentation/nscscc/contest-requirements-2026.md`](Documentation/nscscc/contest-requirements-2026.md)。

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

2026-07-24 的 input 支持更新：

- 加入 UE11 platform HCD、USB HID、generic HID、hidraw 和 evdev 配置，并把
  driver 加入 kernel link。
- 使用 UTMI LineState 区分无设备、Full-Speed 和不支持的 Low-Speed 设备，
  修正 root hub attachment、disconnect、URB error return 和 RX overflow 行为。
- 在不支持 `ECFG.VS` hardware-vector offset 的当前 SpinalHDL CPU 上，由
  fallback interrupt dispatcher 分发 PS/2 IP5 和 USB IP6。
- PS/2 启动参数使用 `atkbd.reset=0`，避免对当前单通道 controller 执行不兼容
  的 reset sequence。
- Buildroot 加入 `usbutils` 和 `evtest`，并校验 `lsusb` 的 LoongArch ELF
  identity、runtime dependency 和 SHA256。

2026-08-03 的基础 userspace 更新：

- initramfs 构建保证 `ls` 及启动脚本、验证脚本和重复运行所需的 BusyBox
  applet 链接存在。
- `nscscc-check` 明确检查 `ls` 并执行 `ls -la /`。
- 两次独立 FPGA 编程、TFTP 和 Linux 运行均进入 `/ #`，完成 `ls`、DMFE、
  confreg 和基础系统命令检查。
- 官方技术方案确认 Linux 成功启动对应系统测试 15 分；20 分等级所需的指定
  操作明细尚未发布，因此当前没有声明已经完成全部 20 分条件。

2026-08-15 的离线 Linux 更新：

- 内核加入 IPv4 autoconfiguration、NFSv2/v3 client 和 root NFS 支持，NFSv4
  保持禁用。
- `/init` 支持 `nscscc.nfsroot=` 和 `nscscc.nfsopts=`，成功 mount 后通过
  `switch_root` 运行远端 root filesystem，失败时保留 recovery shell。
- Buildroot 与 initramfs 的 network service 会保留已经配置的 `eth0` 地址，
  避免 `switch_root` 后重新 flush NFS root 正在使用的接口。
- 静态 BusyBox 配置加入 NFS mount 支持。initramfs 和 kernel manifest 记录
  实际嵌入的 BusyBox commit、config SHA256 和 binary SHA256。
- 修正 UE11 platform driver 的 driver data 注册和 remove lifecycle。
- 新增 NFS root 离线检查，校验 kernel config、BusyBox config、initramfs 内容
  及 BusyBox identity。以上更新尚未进行 FPGA 实物验证。

2026-08-15 的网络与自检更新：

- initramfs 和 Buildroot 网络服务保留 kernel、DHCP 或 BOOTP 已经
  配置的 global IPv4 地址，避免 NFS root 前后重新配置正在使用的
  网卡。显式 `restart` 仍然会使用 `network.conf` 中的静态地址。
- 网卡不存在、link 配置失败或 IPv4 地址添加失败时，服务返回
  非零状态，不会写入错误的 ready marker。
- `nscscc-check` 现在校验 build identity、128 MiB DDR 范围、可配置网卡的
  global IPv4 地址、carrier、RX/TX error counter、ping、DMFE interrupt
  增量和 confreg 输入。
  任意必要检查失败时，命令返回非零状态。
- `scripts/nscscc/test-userspace-services.sh` 通过 host shell mock 覆盖网络
  首次配置、重复运行、已有地址、网卡缺失、配置失败以及
  `nscscc-check` 的成功与失败结果。

本次更新已完成交叉编译和静态检查。PS/2 key event、USB enumeration、mouse
event 和 disconnect 行为仍需要在后续单独进行实物验证。

## 构建

构建应在 x86-64 Linux 主机（例如 EPYC2）完成，使用官方 LoongArch32
Reduced GCC 8.3 toolchain：

```bash
export ARCH=loongarch
export CROSS_COMPILE=/path/to/toolchain/bin/loongarch32r-linux-gnusf-

scripts/nscscc/build-busybox.sh \
  /absolute/path/to/clean-busybox-1.33-source \
  /absolute/path/to/busybox-output \
  /absolute/path/to/busybox-artifacts/busybox

export NSCSCC_BUSYBOX=/absolute/path/to/busybox-artifacts/busybox

scripts/nscscc/buildroot-desktop.sh \
  /absolute/path/to/buildroot-work \
  /absolute/path/to/toolchain \
  /absolute/path/to/buildroot-artifacts

scripts/nscscc/build-kernel.sh \
  /absolute/path/to/buildroot-work/output/target \
  /absolute/path/to/kernel-output \
  /absolute/path/to/kernel-artifacts

scripts/nscscc/test-userspace-services.sh
```

桌面 image 的构建细节、Buildroot patch identity、runtime loader 处理和
initramfs 约束见 [`Documentation/nscscc/desktop-buildroot.md`](Documentation/nscscc/desktop-buildroot.md)。
可选 NFS root 的启动参数、server 设置和离线检查见
[`Documentation/nscscc/nfs-root.md`](Documentation/nscscc/nfs-root.md)。
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
- NFS root 已通过 kernel、BusyBox、initramfs 和 identity 离线检查，但尚未在
  实验箱上验证 DMFE、NFSv3 mount 和 `switch_root`。

## 依赖

- 交叉工具链：`loongarch32r-linux-gnusf-`，GCC 8.3.0。
- 主机工具：`flex`、`bison`、`bc`、`rsync`、`libssl-dev`。
- Buildroot source 和 `nscscc24-jit-thu/Buildroot` patch，详见 desktop
  build document。
