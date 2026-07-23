# Third-party code and build inputs

This file records code copied into the NSCSCC Linux work and external patches
that are applied by its build scripts. Projects that were only read as
references are intentionally omitted.

## Linux base

This repository is a fork of `loongson-edu/la32r-Linux`, branch
`la32r-new-world`. The original Linux copyright and license declarations are
retained in the source tree.

## DFPMTS archive

The user-provided archive is:

```text
show_software_la32r(1).tar.gz
SHA256 04ddbe3fab6ad9cf30171761179292beffde5420cacf2005343d3507b54b742a
```

The following files originated in its Linux patch and were subsequently
adapted for the current device tree and driver interfaces:

- `drivers/char/nt35510.c`. The original file identifies Tsinghua University,
  Zhang Yuxiang, and Jiajie Chen and is licensed under GPL-2.0.
- `drivers/video/fbdev/xilinxfb_accl.c`. The file retains the MontaVista,
  Secret Lab Technologies, and Xilinx copyright and GPL-2.0 license text.

`drivers/char/chiplab_confreg.c` is a new platform-driver implementation. It
uses the register definitions learned from the DFPMTS material, but it is not
a copy of the supplied driver.

## Buildroot LoongArch32 Reduced support

`scripts/nscscc/buildroot-desktop.sh` applies three patches from
`nscscc24-jit-thu/Buildroot` commit
`5b73cf2f9247502fc16835f14c6a4c3edc0e88e9` to upstream Buildroot commit
`3ebc7c69d56430c34eba4c869d1d4fe4d1e8de55`:

```text
0001-loongarch-add-arch-support-for-LoongArch-32bit-Reduc.patch
SHA256 13d70982554aee709d70b7bd18ef624c1e445bb2faa7c49fa9309b7a56b9ec46

0002-package-temporarily-disable-the-gcc-wrappers-prefix-.patch
SHA256 7866fa2cce4bcb56abc852456f0136046335de307bb943ee85cedb746b526acd

0007-libpng-disable-the-vector-insn-of-loongarch-platform.patch
SHA256 a75db4a3530c3d06a6d1ae124420d28135b01cbe2415ca1ad9cd817cb806ed55
```

These patches are fetched and applied during the Buildroot build; their code
is not stored as files in this kernel repository.

## Chiplab PS/2 and LCD integration

The recorded Chiplab patch contains two implementations derived from third
party projects:

- `IP/APB_DEV/bytestream_ps2.v` is copied without modification from
  `evansm7/mic-hw` commit
  `32a35d67193aaba1dd53549162d7ef6b719e6f8b`, path
  `src/bytestream_ps2.v`. It retains
  `Apache-2.0 WITH SHL-2.1`. Its SHA256 is
  `5320f273c20f92ee5fc009b0c89514ea4c5a5f1e10934ddb4422bac291a03ed8`.
- `IP/APB_DEV/nt35510_apb_adapter.v` is a Chiplab port of
  `trivialmips/nontrivial-mips` commit
  `8e83643c22a3ba7612a9bb9cec93292dad618ab5`, path
  `vivado/ip_repo/nt35510_controller/src/nt35510_apb_adapter_v1_0.v`.
  It retains the TrivialMIPS copyright and MIT license identifier.

The APB PS/2 register adapter, FIFO, protocol testbench, address integration,
interrupt connection, and Vivado source-list changes were written for this
project.
