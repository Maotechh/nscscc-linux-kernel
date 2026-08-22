# MIKU final Linux integration

## Kernel changes

- `drivers/char/nt35510.c`
  - Tunable deferred-I/O refresh (`defio_hz` module parameter).
  - Per-flush timing counters (`flush_count`, `flush_avg_us`, `flush_max_us`).
  - Exact dirty-rectangle flush from byte ranges instead of full rows.
  - Relaxed MMIO pixel writes with one barrier per rectangle.
- `drivers/char/chiplab_confreg.c`
  - Adds `/dev/chiplab_btn_events` character device.
  - Kernel-side 8 ms matrix-keypad sampler with 64-entry event queue.
  - Blocking read + poll support for event-driven userspace clients.

## Userspace

- `scripts/nscscc/mikutap/mikutap_web_server.c`
  - Single-file HTTP static server + SSE keypad bridge.
  - Prefers `/dev/chiplab_btn_events`; falls back to
    `/dev/chiplab_confreg` offset 0x1024 polling.
- `scripts/nscscc/rootfs-overlay/`
  - `root/.xinitrc`: white root window, miku wallpaper in the upper half,
    xterm in the lower half, fluxbox with default toolbar.
  - `root/miku.png`: 480x800 wallpaper generated from the miku logo.
  - `etc/init.d/S90mikutap-web`: starts the mikutap server on port 80.
  - `etc/init.d/S95miku-tune`: sets `defio_hz=80`.

## Verified artifacts

See the companion `show` package:

- bitstream: `soc_top-ad6551-cpu40-uncore100-usb-axil-cdc.bit`
- kernel: `vmlinux-d0b3f7a6e-miku-web`
