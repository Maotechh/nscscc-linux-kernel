/*
 * Host-native harness for the ue11-hcd control status-stage DATAx decision.
 *
 * Campaign linux-continuous, iteration 060 (Opus checkpoint-053-056 C4):
 * first-ever runtime execution of the fix logic in 6832b1aa4, without a
 * board, without QEMU, and without touching the board-bound artifact.
 *
 * USB 2.0 spec 8.5.3: the control status stage always uses DATA1, and its
 * transaction direction is opposite the data stage.  The toggle check
 * introduced in 7407da63a compared the received PID against usb_gettoggle()
 * keyed by the URB pipe direction, which is correct for genuine data-IN
 * packets but wrong for the status stage.  A control write whose data stage
 * has an odd number of packets (or a ZLP, like the SET_ADDRESS status stage)
 * then saw expected=0 vs received=1, rejected the DATA1 status, and failed
 * the URB with -EPROTO after three retries.
 *
 * This harness re-implements process_transfer_result()'s DATAx decision for
 * both the broken (7407da63a) and fixed (6832b1aa4) forms, and drives the
 * full control-write state machine (SETUP -> [data] -> STATUS) for two
 * concrete URBs: SET_ADDRESS (zero-length, ZLP status) and SET_REPORT
 * (one data packet, odd parity).  Pre-fix must fail with -EPROTO; post-fix
 * must complete with status 0.
 *
 * Build:  gcc -O2 -Wall -Wextra -o ue11h-datax-harness ue11h-datax-harness.c
 */

#include <stdio.h>
#include <string.h>

/* USB 2.0 PID values (Table 8-1). */
#define USB_PID_DATA0  0x30
#define USB_PID_DATA1  0xb0
#define USB_PID_ACK    0xd2
#define USB_PID_NAK    0x5a
#define USB_PID_STALL  0x1e
#define USB_PID_IN     0x69
#define USB_PID_OUT    0xe1
#define USB_PID_SETUP  0x2d

/* urbstat mirror of the kernel's error codes. */
#define EINPROGRESS   (-115)
#define EPROTO        (-71)
#define ETIMEDOUT     (-110)

#define DEVNUM_MAX 2
#define EP_MAX     16

/* ------------------------------------------------------------------ */
/* Minimal stand-in for the USB core's per-(dev,ep,direction) toggle.  */
/* ------------------------------------------------------------------ */

static unsigned char toggle_tbl[DEVNUM_MAX][EP_MAX][2];

static unsigned usb_gettoggle(int dev, int ep, int out)
{
	if (dev >= DEVNUM_MAX || ep >= EP_MAX)
		return 0;
	return toggle_tbl[dev][ep][out != 0];
}

static void usb_settoggle(int dev, int ep, int out, unsigned v)
{
	if (dev >= DEVNUM_MAX || ep >= EP_MAX)
		return;
	toggle_tbl[dev][ep][out != 0] = v & 1u;
}

static void usb_dotoggle(int dev, int ep, int out)
{
	if (dev >= DEVNUM_MAX || ep >= EP_MAX)
		return;
	toggle_tbl[dev][ep][out != 0] ^= 1u;
}

static void toggle_reset(void)
{
	memset(toggle_tbl, 0, sizeof(toggle_tbl));
}

/* ------------------------------------------------------------------ */
/* The DATAx decision extracted from process_transfer_result().
 * Returns 1 (mismatch) or 0 (DATA1/DATA0 matched the expectation).
 * `fixed` selects the pre-6832b1aa4 (7407da63a) vs post-6832b1aa4 form.
 * ------------------------------------------------------------------ */

static int datax_mismatch(int nextpid, int response, int dev, int ep, int out,
			  int fixed)
{
	int received = (response == USB_PID_DATA1);
	int expected;

	if (fixed && nextpid == USB_PID_ACK)
		expected = 1;		/* control status stage always DATA1 */
	else
		expected = usb_gettoggle(dev, ep, out);

	return expected != received;
}

/* ------------------------------------------------------------------ */
/* Control-write state machine.  Models ue11's queue/IRQ flow at the
 * level needed to expose the DATAx decision: SETUP (always DATA0) ->
 * optional data stage (OUT/IN, toggle per packet) -> STATUS (always
 * DATA1, direction opposite the data stage).  On a DATAx mismatch the
 * driver's error path retries the stage up to 3 times then fails the
 * URB with -EPROTO.
 * ------------------------------------------------------------------ */

struct ctrl_urb {
	int	dev;
	int	ep;		/* 0 */
	int	out;		/* pipe direction: 1 = host->device */
	int	len;		/* transfer_buffer_length */
	int	done;		/* actual_length */
};

static int run_control_write(const struct ctrl_urb *u, int fixed)
{
	struct ctrl_urb w = *u;	/* mutable working copy for done/toggle */
	int nextpid = USB_PID_SETUP;
	int error_count = 0;
	int urbstat = EINPROGRESS;

	toggle_reset();

	/* Drive the full transfer loop: SETUP -> [data] -> STATUS.  A
	 * DATAx mismatch leaves the response unconverted (not ACK), so the
	 * URB stays in progress and the stage is retried; the third strike
	 * fails the URB with -EPROTO, mirroring the driver's error tail. */
	while (urbstat == EINPROGRESS) {
		int response;

		switch (nextpid) {
		case USB_PID_SETUP:
			/* device ACKs SETUP; choose the data stage. */
			if (w.done == w.len)
				nextpid = USB_PID_ACK;	/* ZLP: to status */
			else if (w.out) {
				usb_settoggle(w.dev, 0, 1, 1);
				nextpid = USB_PID_OUT;
			} else {
				usb_settoggle(w.dev, 0, 0, 1);
				nextpid = USB_PID_IN;
			}
			break;

		case USB_PID_OUT:
			/* host sends the data packet (DATAx by toggle); the
			 * device ACKs.  No DATAx check on host->device data:
			 * the driver only compares PIDs for IN and the
			 * status stage. */
			usb_dotoggle(w.dev, w.ep, 1);
			w.done++;
			if (w.done == w.len)
				nextpid = USB_PID_ACK;
			break;

		case USB_PID_IN:
			/* host sends IN; device returns DATA0/DATA1 by the
			 * IN toggle.  Both driver versions check this. */
			response = usb_gettoggle(w.dev, w.ep, 0)
				? USB_PID_DATA1 : USB_PID_DATA0;
			if (datax_mismatch(USB_PID_IN, response, w.dev, w.ep,
					   0, fixed)) {
				if (++error_count >= 3)
					urbstat = EPROTO;
				break;
			}
			usb_dotoggle(w.dev, w.ep, 0);
			w.done++;
			if (w.done == w.len)
				nextpid = USB_PID_ACK;
			break;

		case USB_PID_ACK:
			/* STATUS stage: always DATA1 (USB 2.0 8.5.3),
			 * direction opposite the data stage, so IN for a
			 * control write.  The broken driver asked the
			 * *write* toggle slot here; for an odd-parity or
			 * ZLP data stage that slot holds 0 -> expected 0
			 * vs received 1 -> mismatch on every retry. */
			response = USB_PID_DATA1;
			if (datax_mismatch(USB_PID_ACK, response, w.dev,
					   w.ep, w.out, fixed)) {
				if (++error_count >= 3)
					urbstat = EPROTO;
				break;	/* else retry the status stage */
			}
			urbstat = 0;	/* URB completes */
			break;
		}
	}

	return urbstat;
}

/* ------------------------------------------------------------------ */

static int failures = 0;

static void expect(int cond, const char *what)
{
	if (cond) {
		printf("  PASS: %s\n", what);
	} else {
		printf("  FAIL: %s\n", what);
		failures++;
	}
}

int main(void)
{
	struct ctrl_urb set_address = {
		.dev = 1, .ep = 0, .out = 1, .len = 0, .done = 0,
	};
	struct ctrl_urb set_report = {
		.dev = 1, .ep = 0, .out = 1, .len = 1, .done = 0,
	};
	int st;

	printf("ue11h DATAx harness — control status-stage verification\n");
	printf("fix 6832b1aa4 vs broken 7407da63a\n\n");

	/* --- SET_ADDRESS, zero-length control write (ZLP status) --- */
	printf("[SET_ADDRESS: transfer_buffer_length=0]\n");
	printf("  broken (7407da63a):\n");
	st = run_control_write(&set_address, 0);
	expect(st == EPROTO, "URB fails with -EPROTO after 3 strikes");
	printf("    (urbstat=%d)\n", st);
	printf("  fixed (6832b1aa4):\n");
	st = run_control_write(&set_address, 1);
	expect(st == 0, "URB completes with status 0");
	printf("    (urbstat=%d)\n", st);

	/* --- SET_REPORT, one data packet (odd parity) --- */
	printf("\n[SET_REPORT: transfer_buffer_length=1]\n");
	printf("  broken (7407da63a):\n");
	st = run_control_write(&set_report, 0);
	expect(st == EPROTO, "URB fails with -EPROTO after 3 strikes");
	printf("    (urbstat=%d)\n", st);
	printf("  fixed (6832b1aa4):\n");
	st = run_control_write(&set_report, 1);
	expect(st == 0, "URB completes with status 0");
	printf("    (urbstat=%d)\n", st);

	printf("\n%s (%d failures)\n",
	       failures ? "RESULT: FAIL" : "RESULT: PASS", failures);
	return failures ? 1 : 0;
}
