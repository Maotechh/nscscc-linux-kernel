# CEMU kernel validation

This document records the compile and simulator checks for the board-specific
kernel profile added on 2026-08-15. It is not FPGA hardware evidence.

## Test identity

- Kernel source base: `8cd03e11df09b75aa9e7385f605f684cefadd872`.
- CEMU source: `cyyself/cemu` commit
  `d14fea85d663b249434fc3876406efff84627720` with a local LA32R launcher.
- Toolchain: LoongArch32 Reduced GCC 8.3.0, GNU ld 2.31.1.20190122.
- Initramfs size: `1330663` bytes.
- Initramfs SHA256:
  `78f9c2fe2cce005f115b4e570507d9eb59b516146a639097921bc44f00a32c3b`.
- `la32_nscscc_defconfig` SHA256:
  `a8d9f77a281baec4ad3da1e76b882825b3e3a3346876c1f6087c6253e3871a89`.

The simulator-only DTS disables DMFE, confreg, PS/2, UE11 USB, and NT35510.
It changes the command line to `console=ttyS0,115200 init=/init loglevel=8`.
That DTS is not part of the kernel commit and must not be used for an FPGA
artifact.

## Build and run

The CEMU launcher loads a raw kernel image at physical `0x00300000`, which
corresponds to the kernel's first `PT_LOAD` address `0xa0300000`. It passes the
`g` placeholder and command line through the LA32R firmware argument ABI.

The essential commands are:

```bash
make O="$BUILD" ARCH=loongarch CROSS_COMPILE="$CROSS_COMPILE" \
  la32_nscscc_defconfig
scripts/config --file "$BUILD/.config" \
  --set-str INITRAMFS_SOURCE "$INITRAMFS"
make O="$BUILD" ARCH=loongarch CROSS_COMPILE="$CROSS_COMPILE" \
  olddefconfig
scripts/nscscc/validate-kernel-config.sh "$BUILD/.config"
make O="$BUILD" ARCH=loongarch CROSS_COMPILE="$CROSS_COMPILE" \
  -j"$(nproc)" vmlinux
"${CROSS_COMPILE}objcopy" -O binary "$BUILD/vmlinux" vmlinux.bin
entry=$("${CROSS_COMPILE}readelf" -h "$BUILD/vmlinux" |
  awk '/Entry point address:/{print $4}')
timeout 12s cemu vmlinux.bin "$entry" \
  'console=ttyS0,115200 rdinit=/init loglevel=8'
```

The `timeout` exit status is `124` because this CEMU launcher intentionally
continues executing after the shell prompt. A successful run must contain
`NSCSCC_CEMU_SHELL_READY` and `/ #` before the timeout.

## Results

Both configurations use the same source base, compiler, simulator DTS, and
minimal initramfs.

| Measurement | General `la32_defconfig` | `la32_nscscc_defconfig` | Difference |
|---|---:|---:|---:|
| Resolved config SHA256 | `01bf8df5107a1850a6cc996c0662df85daa9fa07a8a81235c2aa8b5779d66853` | `ed426dd2716877c093ac38405d3dd0d4fb79c8e8fa44293d139c378ef40fb8ac` | n/a |
| Debug `vmlinux` bytes | 227020476 | 170777488 | -56242988 |
| Stripped ELF bytes | 14032336 | 10854896 | -3177440 |
| Raw image bytes | 14027308 | 10849868 | -3177440 |
| Available memory at boot | 113416 KiB | 116564 KiB | +3148 KiB |
| Guest time at init | 1.348 s | 0.540 s | -0.808 s |

Final simulator artifact identities:

```text
debug_vmlinux_sha256=b307d44683fb20ee2ff81b75f3391aab04df386d889724f08a8a9450febedf91
raw_kernel_sha256=9ade534c0c30b89ef2913f1e4cdc0e7b034d64be286f6e7be3f05330ab3f0572
stripped_elf_sha256=cc8f61099a2e03bc0610ed46cee3e4cbade8fdeeb1544347b3694fbda791d196
entry=0xa0981db0
first_load=0xa0300000
load_filesz=0xa58e4c
load_memsz=0xada538
```

The final run was repeated from the same raw image. Both complete serial logs
are byte-for-byte identical with SHA256
`b75dabc948bd66446f792757d7929654a0227d4a9a59a409f920e3776788eef9`.

The reduced init time mainly comes from removing the RAID6 benchmark, XFS,
Btrfs, NTFS, IPMI, SCTP, libata, PPS, TUN, and IR initialization. The final
profile also omits drivers for hardware absent from the active DTS: PCMCIA,
CFI NOR, SATA, STMMAC, wireless networking, nonstandard serial devices, and
the Xilinx DMA framebuffer. DMFE remains built in and uses its own PHY register
access rather than the generic PHY framework.

An attempted EFI removal failed at link time because the LA32R platform code
unconditionally references `efi_init` and `efi_runtime_init`. EFI therefore
remains enabled. This is a pre-existing architecture-port limitation rather
than a runtime requirement established by the experiment box.

## Simulator limits

CEMU proves that the ELF layout, LA32R instruction execution, kernel
initialization, embedded initramfs, and shell path work together. It also
supports a controlled comparison of the two kernel profiles.

The MMIO windows are RAM-backed placeholders. CEMU does not model Ethernet,
PHY behavior, USB transactions, input interrupts, PS/2 protocol, LCD commands,
framebuffer transfer, or NAND. The reported guest time is a deterministic
kernel timestamp in this simulator, not FPGA wall-clock performance. USB
storage, NFS root, pointer latency, display refresh rate, and physical panel
output still require separate hardware tests.
