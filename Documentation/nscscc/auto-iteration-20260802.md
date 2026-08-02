# OpenCode Linux Auto-Iteration Handoff (2026-08-02)

## Scope and Branch State

This document summarizes the stopped `linux-continuous` OpenCode campaign.
The campaign started from
`aa3888d6a5c658d05da518a24c26a2fbe4b678c1` and produced 60 iteration
receipts, 23 review records, and 46 integration commits.

The final integration result before this documentation commit is
`9141be600fbfcea0852ed0454245baa641065f05`. The board-bound kernel candidate
remains `0cf30051c84872edcfba69b37e008d92c82cdf15`; later commits add evidence,
review dispositions, runbooks, and a host-native test without changing that
kernel artifact.

Nothing from this campaign was merged into `main` automatically.

## Implemented Changes

### UE11 USB host controller

- Restore IN-transfer DATAx selection and verify received DATA0/DATA1 PIDs.
- Treat a control transfer status stage as DATA1 regardless of the data-stage
  direction toggle (`6832b1aa4`).
- Split port reset completion into de-assert and recovery phases so the first
  SOF respects the USB 2.0 recovery floor at `CONFIG_HZ=250`.
- Present port ENABLE at reset de-assert while keeping SOF gated.
- Suppress only transient disconnect reporting during recovery while keeping
  connection detection active.
- Guard stale recovery timers and serialize power/start lifecycle transitions
  under the controller lock.
- Remove per-transfer console flooding while retaining enumeration lifecycle
  diagnostics and raw post-reset line-state evidence.

### PS/2 and build support

- Add `psmouse.proto=bare` to the board DTS to reduce keyboard/mouse dual-probe
  interference while retaining `atkbd.reset=0`.
- Add RX, TX, and port-open diagnostics to `altera_ps2`.
- Make `scripts/nscscc/build-kernel.sh` select and record a host compiler that
  can build host tools even when a Conda compiler shadows system GCC.

The board-candidate code diff from the campaign base is 246 insertions and 48
deletions across the UE11 driver, PS/2 driver, DTS, build script, and USB HID
documentation. Evidence and handoff records account for the rest of the final
branch diff.

## Verification Results

- Changed-range checkpatch findings were resolved or explicitly bound to raw
  serial evidence files rather than source.
- Targeted `W=1` UE11 object builds completed with no driver warnings.
- Full LoongArch32 vmlinux builds completed with reproducible build metadata.
- The reduced QEMU source-boot lane reached the BusyBox `/ #` shell at the
  refreshed head.
- Enabling UE11 in QEMU failed at the first access to unmodeled MMIO address
  `0x1fe0c000`; this is negative evidence that the emulator cannot validate
  this HCD, not evidence of a driver regression.
- A host-native DATAx harness reproduced the pre-fix `-EPROTO` failure after
  three mismatches for SET_ADDRESS and SET_REPORT, while the `6832b1aa4`
  decision completed both sequences with status zero.
- The final checkpoint disposition was Sol ACCEPT, DeepSeek NON-BLOCKING, and
  Opus CONDITIONAL with all recorded conditions landed.

## Reproducible Board-Candidate Artifacts

The recorded candidate triple is documented in
`Documentation/nscscc/hardware-validation-candidate-0cf30051c.md`.

| Artifact | Identity |
| --- | --- |
| Kernel commit | `0cf30051c84872edcfba69b37e008d92c82cdf15` |
| vmlinux size | 13,550,412 bytes |
| vmlinux SHA-256 | `12943d1a253f3fe6e6ce6dc1af86fb59d574898115ffda2045eca81e573cedf5` |
| initramfs SHA-256 | `b2cbb5f2d27b1ab377edb884893592d9a29d48bfe98fd3baca1631a5d260aa2b` |
| kernel config SHA-256 | `e4565246f1d3fb28a703bcaa22b4416bb27249802876b3cc292fa8f55135ff09` |
| Toolchain | LoongArch32r GCC 8.3.0 |

The manifest records `SOURCE_DATE_EPOCH`, Kbuild identity, tool hashes, ELF
entry/load bounds, and the path-bound HOSTCC qualification. The initramfs was
reproduced byte-for-byte on the recorded host path.

## Evidence Boundary and Remaining Work

This campaign did not obtain new real-board UE11 enumeration or bidirectional
PS/2 evidence for the final candidate. The existing USB-capable bitstream has a
receive-only, pre-bidirectional PS/2 controller, and a paired USB plus
bidirectional-PS/2 bitstream was not built.

Consequently:

- the USB fixes are source-, build-, harness-, and artifact-verified, but not
  final-candidate real-device verified;
- the PS/2 change is a defensive mitigation plus diagnostics, not proof that
  board keyboard/mouse behavior is fixed;
- QEMU boot evidence proves source bootability only because the peripheral
  drivers are disabled in that lane.

Use `auto-iteration/linux-board-candidate-0cf30051c` for the candidate plus its
operator contract. Use `auto-iteration/linux-complete-20260802` for the entire
iteration history, later reviews, runbooks, QEMU evidence, and DATAx harness.
