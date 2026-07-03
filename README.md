# nscscc-linux

2026 龙芯杯团体赛 Linux 内核，fork 自 [loongson-edu/la32r-Linux](https://gitee.com/loongson-edu/la32r-Linux)（branch `la32r-new-world`）。

## 本分支修改（`nscscc` vs 上游）

| 文件 | 修改 | 原因 |
|------|------|------|
| `loongson32_ls.dts` | clock-frequency: 33M → **100M** | 竞赛 SoC UART 挂 sys_clk=100MHz |
| `serial.c` | uartclk: 33M → **100M**; 修正 memset 覆盖 bug | 原代码 memset 在赋值后执行，导致 uartclk=0 |

> 如果用实验箱 SoC（loongson），需把两处的 100000000 改回 33000000。

## 编译

```bash
# 工具链 (GCC 8.3.0)
export PATH=/path/to/loongson-gnu-toolchain-8.3-*/bin:$PATH
export CROSS_COMPILE=loongarch32r-linux-gnusf-
export ARCH=loongarch

# 配置 & 编译
make la32_defconfig
# 如果有 initramfs: 编辑 .config → CONFIG_INITRAMFS_SOURCE=initrd_pck32
make -j$(nproc)

# 裁剪符号减小体积
loongarch32r-linux-gnusf-strip vmlinux
```

## 部署

- **实验箱**: PMON `load tftp://<host>/vmlinux` → `g console=ttyS0,115200 rdinit=/sbin/init`
- **竞赛 SoC**: JTAG-AXI 写 vmlinux.bin 到 DDR3(0x300000)，启动桩写 0x1c000000

## 依赖

- 交叉工具链: `loongarch32r-linux-gnusf-` (GCC 8.3.0)
- 主机: flex bison bc rsync libssl-dev
- initramfs: 可用 [la32r-buildroot](https://gitee.com/loongson-edu/la32r-buildroot) 或 busybox 制作
