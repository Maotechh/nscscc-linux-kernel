# Chiplab PS/2 controller

## Scope

The Linux `altera_ps2` driver was already enabled and its device-tree node was
already present. The missing part was a reliable bidirectional PS/2 physical
controller in the Chiplab system integration. A receive-only controller is not
sufficient for a keyboard because `atkbd` starts detection by sending the
keyboard reset command `0xff` and expects `0xfa` followed by `0xaa`.

The existing display and PS/2 address integration is recorded in:

```text
Documentation/nscscc/evidence/chiplab-display-ps2-20260720.patch
SHA256 c45fd7b1468b8ec60c011418d878847482a71d63f0d0b81d87a512a97cc631ae
```

The bidirectional PS/2 replacement is a separate four-file update:

```text
Documentation/nscscc/evidence/chiplab-ps2-bidirectional-20260724.patch
SHA256 f6382fd503524eeca5b65fc036685ddf3b7e6840807513b6704cc1ed235d0853
```

The first patch applies to Chiplab commit
`a2e11b38bc5c85abb4408a8e0c0f5ce903c7ba31`. The PS/2 update applies after
it and corresponds to local commit
`d3ef945fa43875913d50b6dc8cbb7ee7beaf49fe`.

## Controller

`IP/APB_DEV/bytestream_ps2.v` is an unchanged copy of
`evansm7/mic-hw` commit
`32a35d67193aaba1dd53549162d7ef6b719e6f8b`, file
`src/bytestream_ps2.v`. Its SHA256 is:

```text
5320f273c20f92ee5fc009b0c89514ea4c5a5f1e10934ddb4422bac291a03ed8
```

The file retains its original
`Apache-2.0 WITH SHL-2.1` license declaration. It implements input
synchronization and filtering, odd parity, receive and transmit state
machines, the PS/2 host request-to-send sequence, and transfer timeouts.

`IP/APB_DEV/chiplab_ps2_rx.v` is the project-specific APB adapter. It was
written for this integration and was not copied from another project. It:

- exposes the two-register ABI used by `drivers/input/serio/altera_ps2.c`;
- buffers 16 received bytes and asserts the interrupt while the FIFO is not
  empty and receive interrupts are enabled;
- queues a host command written to offset `0`;
- drives the Xilinx `IOBUF` signals as open drain, so the FPGA only drives a
  low level and otherwise releases the line;
- configures the protocol timing for the 100 MHz Chiplab uncore clock.

The register contract is:

```text
offset 0, read:  bits 31:16 RAVAIL, bit 15 RVALID, bits 7:0 data
offset 0, write: bits 7:0 host command
offset 4, write: bit 0 receive interrupt enable
```

The integration maps the controller at `0x1fe04000`, connects it to SoC
interrupt input `7` (Linux IRQ `23`), and assigns `PS2_clk` to package pin
`Y2` and `PS2_dat` to `AD1`, both with `LVCMOS33` and pull-ups.

## Automated check

Run:

```sh
scripts/nscscc/test-chiplab-ps2.sh /path/to/chiplab
```

The script creates a temporary detached worktree at the exact Chiplab base,
checks and applies the recorded patch, verifies the copied source hash, and
runs:

- an Icarus Verilog keyboard-reset simulation;
- Verilator lint;
- Yosys synthesis and structural checks;
- Linux defconfig and device-tree contract checks.

The simulated keyboard receives `0xff`, acknowledges the host transmission,
then sends `0xfa` and `0xaa`. The test checks FIFO order, RAVAIL, RVALID,
interrupt assertion, interrupt clearing, and open-drain output behavior.

## Validation status

The protocol simulation, Verilator lint, and Yosys checks pass. No experiment
box was accessed for this revision, and no claim is made that a physical
keyboard produced Linux input events. Hardware validation still requires
`atkbd` detection, `/dev/input/event*`, an increasing PS/2 interrupt count,
and captured key events.
