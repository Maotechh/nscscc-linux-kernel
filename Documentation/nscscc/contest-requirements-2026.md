# 2026 团体赛官方要求对照

本文依据《2026 年全国大学生计算机系统能力大赛 CPU 设计赛（龙芯杯）
团体赛技术方案》整理。最近核对日期为 2026 年 8 月 15 日。大赛网站为
[cpu.xtnl.org.cn](https://cpu.xtnl.org.cn/#/) 和
[nscscc.com](https://www.nscscc.com/)。

## Linux 对应的分值

官方技术方案第 11 条规定，决赛系统测试占总成绩的 20%。第 13 条给出四个
互斥等级：

1. 按照指定方式启动典型 bootloader 并完成指定操作，系统测试为 5 分。
2. 按照指定方式启动典型教学操作系统并完成指定操作，系统测试为 10 分。
3. 按照指定方式启动 Linux，系统测试为 15 分。
4. 按照指定方式启动 Linux 并完成指定操作，系统测试为 20 分。

因此，Linux 启动和 Linux 指定操作不是可以相加的 15 分与 20 分。完成第四项
时，系统测试总分为 20 分。

截至最近核对日期，技术方案和已发布的初赛资料没有列出 Linux 的“指定方式”与
“指定操作”明细。当前仓库可以验证已经公布的 Linux 启动条件，但不能据此
声称第四项已经全部完成。组委会发布明细后，必须逐项增加测试并保存记录。

## 当前实现与已确认项目

当前 `main` 包含以下系统功能：

- U-Boot、DMFE Ethernet、TFTP 下载、主机与实验箱两端文件校验，以及
  `bootelf -p` 加载。
- ELF32 LoongArch kernel，128 MiB DDR 地址检查，100 MHz UART 配置和
  内嵌 initramfs。
- `/init`、静态 BusyBox、`/bin/sh`、`ls`、基础文件系统命令和可重复构建
  信息。
- Linux DMFE 网络、confreg 拨动开关、按键、LED 和七段数码管接口。
- NT35510 character device 和 RGB565 framebuffer。
- PS／2 serio、keyboard protocol 和 evdev 接口。
- UE11 Full-Speed USB host、USB HID 和 userspace 工具。

2026 年 8 月 3 日的两次独立运行均从 FPGA 编程开始，并完成以下检查：

- Vivado 2023.2 编程成功，FPGA startup status 为 HIGH。
- U-Boot 能够访问 TFTP server，传输字节数与 CRC32 一致，没有 TFTP block
  retransmission。
- Linux 显示版本信息、识别 128 MiB memory、进入 `/ #`，并成功执行
  `ls -la /`。
- initramfs 中 `chmod`、`hostname`、`mkdir`、`reboot`、`sync` 和 `umount`
  等启动及重复测试所需 BusyBox applet 可用。
- `eth0` carrier 为 1，RX／TX error 为 0，三次 ping 均成功，DMFE interrupt
  count 增加。
- confreg read、LED write 和七段数码管 write 成功。

这些记录支持第 13 条第三项所述的 Linux 成功启动。它们也证明了一组可能用于
指定操作的基础功能，但在组委会公布明细前，不构成第四项的完整证明。

## 尚未完成或不能声明的项目

- Linux 指定操作的官方明细尚未发布，所以 20 分等级无法完成最终核对。
- 当前连接的 USB 鼠标接收器被识别为 Low-Speed device，而 UE11 SIE 仅支持
  Full-Speed，当前没有 USB mouse event 成功记录。
- PS／2 controller、`AT Raw Set 2 keyboard` 和 input event device 已注册，
  但当前记录没有实际按键 event，因此不声明键盘输入已经完整通过。
- framebuffer 和 NT35510 device node 证明 Linux software interface 存在，
  不能替代对 LCD 实际显示内容的观察。
- 决赛的性能测试、自定义指令、系统展示和答辩属于其他评分项目，Linux 启动
  不能证明这些项目已经完成。

## 其他官方约束

技术方案还规定：

- 指定实验设备包含 Artix-7 FPGA、128 MiB DDR3、4 MiB SPI flash、一个
  RS-232 UART、八个七段数码管和八位拨动开关。
- FPGA 流程使用 Vivado 2023.2，软件使用指定 LoongArch32 Reduced
  cross-toolchain。
- 作品必须提交完整硬件工程、源代码、pin assignment、FPGA binary 和设计
  报告。
- 使用第三方 IP 或直接复用他人源码时，必须在设计报告中明确说明。仓库中的
  对应记录见 [third-party-code.md](third-party-code.md)。
