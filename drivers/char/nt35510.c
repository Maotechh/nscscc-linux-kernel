/*
 * Driver for nt35510
 *
 * Copyright (C) 2016-2019 Tsinghua University
 * Author: Zhang Yuxiang <zz593141477@gmail.com> Jiajie Chen <jiegec@qq.com>
 *
 * This program is free software; you can redistribute it and/or modify it
 * under the terms and conditions of the GNU General Public License,
 * version 2, as published by the Free Software Foundation.
 */

#include <linux/module.h>
#include <linux/platform_device.h>
#include <linux/io.h>
#include <linux/slab.h>
#include <linux/of.h>
#include <linux/fs.h>
#include <linux/errno.h>
#include <linux/cdev.h>
#include <linux/uaccess.h>
#include <linux/fb.h>
#include <linux/list.h>
#include <linux/mutex.h>
#include <linux/vmalloc.h>
#include <asm/delay.h>

#define DRV_NAME "nt35510"
#define CLASS_NAME "nlcd"
#define MAX_LCD_NUM 1

#define NT35510_INST_OFFSET 0x0
#define NT35510_DATA_OFFSET 0x1
#define BYTES_PER_PIXEL 2
#define NT35510_DEFAULT_XRES 480
#define NT35510_DEFAULT_YRES 800
#define NT35510_DEFAULT_DEFIO_HZ 20

static int majorNumber;
static struct class *nt35510_class;

static struct nt35510_drvdata {
	struct device *device;
	struct cdev cdev;
	int isOpen;
	phys_addr_t regs_phys;
	void __iomem *regs;
	u32 xres, yres;
	loff_t curr_off;
	struct mutex lock;
	void *fbmem;
	size_t fbsize;
	struct fb_info *fb_info;
	struct fb_deferred_io fbdefio;
} * nt35510s[MAX_LCD_NUM];

static struct nt35510_drvdata default_nt35510_drvdata = {
	.xres = NT35510_DEFAULT_XRES,
	.yres = NT35510_DEFAULT_YRES,
	.isOpen = 0,
};

static void nt35510_out32(const struct nt35510_drvdata *drvdata, u32 offset,
		u32 val)
{
	iowrite32(val, drvdata->regs + (offset << 2));
	dev_dbg(drvdata->device, "nt35510_out32: off=0x%02x val=0x%04x\n", offset, val);
}

static void nt35510_init(const struct nt35510_drvdata *drvdata)
{
	static const u32 init_insts[][2] = {
		{ 0xF000, 0x55 },
		{ 0xF001, 0xAA },
		{ 0xF002, 0x52 },
		{ 0xF003, 0x08 },
		{ 0xF004, 0x01 },
		// AVDD Set AVDD 5.2V
		{ 0xB000, 0x0D },
		{ 0xB001, 0x0D },
		{ 0xB002, 0x0D },
		// AVDD ratio
		{ 0xB600, 0x34 },
		{ 0xB601, 0x34 },
		{ 0xB602, 0x34 },
		// AVEE -5.2V
		{ 0xB100, 0x0D },
		{ 0xB101, 0x0D },
		{ 0xB102, 0x0D },
		// AVEE ratio
		{ 0xB700, 0x34 },
		{ 0xB701, 0x34 },
		{ 0xB702, 0x34 },
		// VCL -2.5V
		{ 0xB200, 0x00 },
		{ 0xB201, 0x00 },
		{ 0xB202, 0x00 },
		// VCL ratio
		{ 0xB800, 0x24 },
		{ 0xB801, 0x24 },
		{ 0xB802, 0x24 },
		// VGH 15V (Free pump)
		{ 0xBF00, 0x01 },
		{ 0xB300, 0x0F },
		{ 0xB301, 0x0F },
		{ 0xB302, 0x0F },
		// VGH ratio
		{ 0xB900, 0x34 },
		{ 0xB901, 0x34 },
		{ 0xB902, 0x34 },
		// VGL_REG -10V
		{ 0xB500, 0x08 },
		{ 0xB501, 0x08 },
		{ 0xB502, 0x08 },
		{ 0xC200, 0x03 },
		// VGLX ratio
		{ 0xBA00, 0x24 },
		{ 0xBA01, 0x24 },
		{ 0xBA02, 0x24 },
		// VGMP/VGSP 4.5V/0V
		{ 0xBC00, 0x00 },
		{ 0xBC01, 0x78 },
		{ 0xBC02, 0x00 },
		// VGMN/VGSN -4.5V/0V
		{ 0xBD00, 0x00 },
		{ 0xBD01, 0x78 },
		{ 0xBD02, 0x00 },
		// VCOM
		{ 0xBE00, 0x00 },
		{ 0xBE01, 0x64 },
		// Gamma Setting
		{ 0xD100, 0x00 },
		{ 0xD101, 0x33 },
		{ 0xD102, 0x00 },
		{ 0xD103, 0x34 },
		{ 0xD104, 0x00 },
		{ 0xD105, 0x3A },
		{ 0xD106, 0x00 },
		{ 0xD107, 0x4A },
		{ 0xD108, 0x00 },
		{ 0xD109, 0x5C },
		{ 0xD10A, 0x00 },
		{ 0xD10B, 0x81 },
		{ 0xD10C, 0x00 },
		{ 0xD10D, 0xA6 },
		{ 0xD10E, 0x00 },
		{ 0xD10F, 0xE5 },
		{ 0xD110, 0x01 },
		{ 0xD111, 0x13 },
		{ 0xD112, 0x01 },
		{ 0xD113, 0x54 },
		{ 0xD114, 0x01 },
		{ 0xD115, 0x82 },
		{ 0xD116, 0x01 },
		{ 0xD117, 0xCA },
		{ 0xD118, 0x02 },
		{ 0xD119, 0x00 },
		{ 0xD11A, 0x02 },
		{ 0xD11B, 0x01 },
		{ 0xD11C, 0x02 },
		{ 0xD11D, 0x34 },
		{ 0xD11E, 0x02 },
		{ 0xD11F, 0x67 },
		{ 0xD120, 0x02 },
		{ 0xD121, 0x84 },
		{ 0xD122, 0x02 },
		{ 0xD123, 0xA4 },
		{ 0xD124, 0x02 },
		{ 0xD125, 0xB7 },
		{ 0xD126, 0x02 },
		{ 0xD127, 0xCF },
		{ 0xD128, 0x02 },
		{ 0xD129, 0xDE },
		{ 0xD12A, 0x02 },
		{ 0xD12B, 0xF2 },
		{ 0xD12C, 0x02 },
		{ 0xD12D, 0xFE },
		{ 0xD12E, 0x03 },
		{ 0xD12F, 0x10 },
		{ 0xD130, 0x03 },
		{ 0xD131, 0x33 },
		{ 0xD132, 0x03 },
		{ 0xD133, 0x6D },
		{ 0xD200, 0x00 },
		{ 0xD201, 0x33 },
		{ 0xD202, 0x00 },
		{ 0xD203, 0x34 },
		{ 0xD204, 0x00 },
		{ 0xD205, 0x3A },
		{ 0xD206, 0x00 },
		{ 0xD207, 0x4A },
		{ 0xD208, 0x00 },
		{ 0xD209, 0x5C },
		{ 0xD20A, 0x00 },

		{ 0xD20B, 0x81 },
		{ 0xD20C, 0x00 },
		{ 0xD20D, 0xA6 },
		{ 0xD20E, 0x00 },
		{ 0xD20F, 0xE5 },
		{ 0xD210, 0x01 },
		{ 0xD211, 0x13 },
		{ 0xD212, 0x01 },
		{ 0xD213, 0x54 },
		{ 0xD214, 0x01 },
		{ 0xD215, 0x82 },
		{ 0xD216, 0x01 },
		{ 0xD217, 0xCA },
		{ 0xD218, 0x02 },
		{ 0xD219, 0x00 },
		{ 0xD21A, 0x02 },
		{ 0xD21B, 0x01 },
		{ 0xD21C, 0x02 },
		{ 0xD21D, 0x34 },
		{ 0xD21E, 0x02 },
		{ 0xD21F, 0x67 },
		{ 0xD220, 0x02 },
		{ 0xD221, 0x84 },
		{ 0xD222, 0x02 },
		{ 0xD223, 0xA4 },
		{ 0xD224, 0x02 },
		{ 0xD225, 0xB7 },
		{ 0xD226, 0x02 },
		{ 0xD227, 0xCF },
		{ 0xD228, 0x02 },
		{ 0xD229, 0xDE },
		{ 0xD22A, 0x02 },
		{ 0xD22B, 0xF2 },
		{ 0xD22C, 0x02 },
		{ 0xD22D, 0xFE },
		{ 0xD22E, 0x03 },
		{ 0xD22F, 0x10 },
		{ 0xD230, 0x03 },
		{ 0xD231, 0x33 },
		{ 0xD232, 0x03 },
		{ 0xD233, 0x6D },
		{ 0xD300, 0x00 },
		{ 0xD301, 0x33 },
		{ 0xD302, 0x00 },
		{ 0xD303, 0x34 },
		{ 0xD304, 0x00 },
		{ 0xD305, 0x3A },
		{ 0xD306, 0x00 },
		{ 0xD307, 0x4A },
		{ 0xD308, 0x00 },
		{ 0xD309, 0x5C },
		{ 0xD30A, 0x00 },

		{ 0xD30B, 0x81 },
		{ 0xD30C, 0x00 },
		{ 0xD30D, 0xA6 },
		{ 0xD30E, 0x00 },
		{ 0xD30F, 0xE5 },
		{ 0xD310, 0x01 },
		{ 0xD311, 0x13 },
		{ 0xD312, 0x01 },
		{ 0xD313, 0x54 },
		{ 0xD314, 0x01 },
		{ 0xD315, 0x82 },
		{ 0xD316, 0x01 },
		{ 0xD317, 0xCA },
		{ 0xD318, 0x02 },
		{ 0xD319, 0x00 },
		{ 0xD31A, 0x02 },
		{ 0xD31B, 0x01 },
		{ 0xD31C, 0x02 },
		{ 0xD31D, 0x34 },
		{ 0xD31E, 0x02 },
		{ 0xD31F, 0x67 },
		{ 0xD320, 0x02 },
		{ 0xD321, 0x84 },
		{ 0xD322, 0x02 },
		{ 0xD323, 0xA4 },
		{ 0xD324, 0x02 },
		{ 0xD325, 0xB7 },
		{ 0xD326, 0x02 },
		{ 0xD327, 0xCF },
		{ 0xD328, 0x02 },
		{ 0xD329, 0xDE },
		{ 0xD32A, 0x02 },
		{ 0xD32B, 0xF2 },
		{ 0xD32C, 0x02 },
		{ 0xD32D, 0xFE },
		{ 0xD32E, 0x03 },
		{ 0xD32F, 0x10 },
		{ 0xD330, 0x03 },
		{ 0xD331, 0x33 },
		{ 0xD332, 0x03 },
		{ 0xD333, 0x6D },
		{ 0xD400, 0x00 },
		{ 0xD401, 0x33 },
		{ 0xD402, 0x00 },
		{ 0xD403, 0x34 },
		{ 0xD404, 0x00 },
		{ 0xD405, 0x3A },
		{ 0xD406, 0x00 },
		{ 0xD407, 0x4A },
		{ 0xD408, 0x00 },
		{ 0xD409, 0x5C },
		{ 0xD40A, 0x00 },
		{ 0xD40B, 0x81 },

		{ 0xD40C, 0x00 },
		{ 0xD40D, 0xA6 },
		{ 0xD40E, 0x00 },
		{ 0xD40F, 0xE5 },
		{ 0xD410, 0x01 },
		{ 0xD411, 0x13 },
		{ 0xD412, 0x01 },
		{ 0xD413, 0x54 },
		{ 0xD414, 0x01 },
		{ 0xD415, 0x82 },
		{ 0xD416, 0x01 },
		{ 0xD417, 0xCA },
		{ 0xD418, 0x02 },
		{ 0xD419, 0x00 },
		{ 0xD41A, 0x02 },
		{ 0xD41B, 0x01 },
		{ 0xD41C, 0x02 },
		{ 0xD41D, 0x34 },
		{ 0xD41E, 0x02 },
		{ 0xD41F, 0x67 },
		{ 0xD420, 0x02 },
		{ 0xD421, 0x84 },
		{ 0xD422, 0x02 },
		{ 0xD423, 0xA4 },
		{ 0xD424, 0x02 },
		{ 0xD425, 0xB7 },
		{ 0xD426, 0x02 },
		{ 0xD427, 0xCF },
		{ 0xD428, 0x02 },
		{ 0xD429, 0xDE },
		{ 0xD42A, 0x02 },
		{ 0xD42B, 0xF2 },
		{ 0xD42C, 0x02 },
		{ 0xD42D, 0xFE },
		{ 0xD42E, 0x03 },
		{ 0xD42F, 0x10 },
		{ 0xD430, 0x03 },
		{ 0xD431, 0x33 },
		{ 0xD432, 0x03 },
		{ 0xD433, 0x6D },
		{ 0xD500, 0x00 },
		{ 0xD501, 0x33 },
		{ 0xD502, 0x00 },
		{ 0xD503, 0x34 },
		{ 0xD504, 0x00 },
		{ 0xD505, 0x3A },
		{ 0xD506, 0x00 },
		{ 0xD507, 0x4A },
		{ 0xD508, 0x00 },
		{ 0xD509, 0x5C },
		{ 0xD50A, 0x00 },
		{ 0xD50B, 0x81 },

		{ 0xD50C, 0x00 },
		{ 0xD50D, 0xA6 },
		{ 0xD50E, 0x00 },
		{ 0xD50F, 0xE5 },
		{ 0xD510, 0x01 },
		{ 0xD511, 0x13 },
		{ 0xD512, 0x01 },
		{ 0xD513, 0x54 },
		{ 0xD514, 0x01 },
		{ 0xD515, 0x82 },
		{ 0xD516, 0x01 },
		{ 0xD517, 0xCA },
		{ 0xD518, 0x02 },
		{ 0xD519, 0x00 },
		{ 0xD51A, 0x02 },
		{ 0xD51B, 0x01 },
		{ 0xD51C, 0x02 },
		{ 0xD51D, 0x34 },
		{ 0xD51E, 0x02 },
		{ 0xD51F, 0x67 },
		{ 0xD520, 0x02 },
		{ 0xD521, 0x84 },
		{ 0xD522, 0x02 },
		{ 0xD523, 0xA4 },
		{ 0xD524, 0x02 },
		{ 0xD525, 0xB7 },
		{ 0xD526, 0x02 },
		{ 0xD527, 0xCF },
		{ 0xD528, 0x02 },
		{ 0xD529, 0xDE },
		{ 0xD52A, 0x02 },
		{ 0xD52B, 0xF2 },
		{ 0xD52C, 0x02 },
		{ 0xD52D, 0xFE },
		{ 0xD52E, 0x03 },
		{ 0xD52F, 0x10 },
		{ 0xD530, 0x03 },
		{ 0xD531, 0x33 },
		{ 0xD532, 0x03 },
		{ 0xD533, 0x6D },
		{ 0xD600, 0x00 },
		{ 0xD601, 0x33 },
		{ 0xD602, 0x00 },
		{ 0xD603, 0x34 },
		{ 0xD604, 0x00 },
		{ 0xD605, 0x3A },
		{ 0xD606, 0x00 },
		{ 0xD607, 0x4A },
		{ 0xD608, 0x00 },
		{ 0xD609, 0x5C },
		{ 0xD60A, 0x00 },
		{ 0xD60B, 0x81 },

		{ 0xD60C, 0x00 },
		{ 0xD60D, 0xA6 },
		{ 0xD60E, 0x00 },
		{ 0xD60F, 0xE5 },
		{ 0xD610, 0x01 },
		{ 0xD611, 0x13 },
		{ 0xD612, 0x01 },
		{ 0xD613, 0x54 },
		{ 0xD614, 0x01 },
		{ 0xD615, 0x82 },
		{ 0xD616, 0x01 },
		{ 0xD617, 0xCA },
		{ 0xD618, 0x02 },
		{ 0xD619, 0x00 },
		{ 0xD61A, 0x02 },
		{ 0xD61B, 0x01 },
		{ 0xD61C, 0x02 },
		{ 0xD61D, 0x34 },
		{ 0xD61E, 0x02 },
		{ 0xD61F, 0x67 },
		{ 0xD620, 0x02 },
		{ 0xD621, 0x84 },
		{ 0xD622, 0x02 },
		{ 0xD623, 0xA4 },
		{ 0xD624, 0x02 },
		{ 0xD625, 0xB7 },
		{ 0xD626, 0x02 },
		{ 0xD627, 0xCF },
		{ 0xD628, 0x02 },
		{ 0xD629, 0xDE },
		{ 0xD62A, 0x02 },
		{ 0xD62B, 0xF2 },
		{ 0xD62C, 0x02 },
		{ 0xD62D, 0xFE },
		{ 0xD62E, 0x03 },
		{ 0xD62F, 0x10 },
		{ 0xD630, 0x03 },
		{ 0xD631, 0x33 },
		{ 0xD632, 0x03 },
		{ 0xD633, 0x6D },
		// LV2 Page 0 enable
		{ 0xF000, 0x55 },
		{ 0xF001, 0xAA },
		{ 0xF002, 0x52 },
		{ 0xF003, 0x08 },
		{ 0xF004, 0x00 },
		// Display control
		{ 0xB100, 0xCC },
		{ 0xB101, 0x00 },
		// Source hold time
		{ 0xB600, 0x05 },
		// Gate EQ control
		{ 0xB700, 0x70 },
		{ 0xB701, 0x70 },
		// Source EQ control (Mode 2)
		{ 0xB800, 0x01 },
		{ 0xB801, 0x03 },
		{ 0xB802, 0x03 },
		{ 0xB803, 0x03 },
		// Inversion mode (2-dot)
		{ 0xBC00, 0x02 },
		{ 0xBC01, 0x00 },
		{ 0xBC02, 0x00 },
		// Timing control 4H w/ 4-delay
		{ 0xC900, 0xD0 },
		{ 0xC901, 0x02 },
		{ 0xC902, 0x50 },
		{ 0xC903, 0x50 },
		{ 0xC904, 0x50 },
		{ 0x3500, 0x00 },
		{ 0x3A00, 0x55 } // 16-bit/pixel
	};
	const int NUM_INIT_INS = sizeof(init_insts) / sizeof(init_insts[0]);
	int i;
	for (i = 0; i < NUM_INIT_INS; i++) {
		nt35510_out32(drvdata, NT35510_INST_OFFSET, init_insts[i][0]);
		nt35510_out32(drvdata, NT35510_DATA_OFFSET, init_insts[i][1]);
	}
	nt35510_out32(drvdata, NT35510_INST_OFFSET, 0x1100);
	udelay(100000);
	nt35510_out32(drvdata, NT35510_INST_OFFSET, 0x2900);
}

/*
 * Set an inclusive address window.  The original character-device path only
 * programmed the start coordinate, which is sufficient for a linear write
 * but does not describe a framebuffer rectangle to the controller.
 */
static int nt35510_set_window(const struct nt35510_drvdata *drvdata,
			u32 x0, u32 y0, u32 x1, u32 y1)
{
	if (x0 > x1 || y0 > y1 || x1 >= drvdata->xres || y1 >= drvdata->yres)
		return -ERANGE;

	nt35510_out32(drvdata, NT35510_INST_OFFSET, 0x2A00);
	nt35510_out32(drvdata, NT35510_DATA_OFFSET, (x0 >> 8) & 0xff);
	nt35510_out32(drvdata, NT35510_INST_OFFSET, 0x2A01);
	nt35510_out32(drvdata, NT35510_DATA_OFFSET, x0 & 0xff);
	nt35510_out32(drvdata, NT35510_INST_OFFSET, 0x2A02);
	nt35510_out32(drvdata, NT35510_DATA_OFFSET, (x1 >> 8) & 0xff);
	nt35510_out32(drvdata, NT35510_INST_OFFSET, 0x2A03);
	nt35510_out32(drvdata, NT35510_DATA_OFFSET, x1 & 0xff);
	nt35510_out32(drvdata, NT35510_INST_OFFSET, 0x2B00);
	nt35510_out32(drvdata, NT35510_DATA_OFFSET, (y0 >> 8) & 0xff);
	nt35510_out32(drvdata, NT35510_INST_OFFSET, 0x2B01);
	nt35510_out32(drvdata, NT35510_DATA_OFFSET, y0 & 0xff);
	nt35510_out32(drvdata, NT35510_INST_OFFSET, 0x2B02);
	nt35510_out32(drvdata, NT35510_DATA_OFFSET, (y1 >> 8) & 0xff);
	nt35510_out32(drvdata, NT35510_INST_OFFSET, 0x2B03);
	nt35510_out32(drvdata, NT35510_DATA_OFFSET, y1 & 0xff);
	return 0;
}

static void nt35510_flush_rect_locked(struct nt35510_drvdata *drvdata,
			u32 x0, u32 y0, u32 x1, u32 y1)
{
	u32 x, y;
	u16 *pixels = drvdata->fbmem;

	if (!pixels || nt35510_set_window(drvdata, x0, y0, x1, y1))
		return;

	nt35510_out32(drvdata, NT35510_INST_OFFSET, 0x2C00);
	for (y = y0; y <= y1; y++) {
		for (x = x0; x <= x1; x++)
			nt35510_out32(drvdata, NT35510_DATA_OFFSET,
					pixels[y * drvdata->xres + x]);
	}
}

static void nt35510_flush_rows_locked(struct nt35510_drvdata *drvdata,
			u32 y0, u32 y1)
{
	if (!drvdata->yres || y0 >= drvdata->yres)
		return;
	if (y1 >= drvdata->yres)
		y1 = drvdata->yres - 1;
	nt35510_flush_rect_locked(drvdata, 0, y0, drvdata->xres - 1, y1);
}

static void nt35510_flush_bytes_locked(struct nt35510_drvdata *drvdata,
		unsigned long start, unsigned long end)
{
	u32 y0, y1;

	if (!drvdata->fbmem || start >= end || start >= drvdata->fbsize)
		return;
	if (end > drvdata->fbsize)
		end = drvdata->fbsize;
	y0 = start / (drvdata->xres * BYTES_PER_PIXEL);
	y1 = (end - 1) / (drvdata->xres * BYTES_PER_PIXEL);
	nt35510_flush_rows_locked(drvdata, y0, y1);
}

static void nt35510fb_deferred_io(struct fb_info *info,
		struct list_head *pagelist)
{
	struct nt35510_drvdata *drvdata = info->par;
	struct page *page;
	unsigned long first = 0, end = 0, page_start;

	/* The page list is sorted by index.  Coalesce adjacent pages into rows. */
	mutex_lock(&drvdata->lock);
	list_for_each_entry(page, pagelist, lru) {
		page_start = page->index << PAGE_SHIFT;
		if (!end) {
			first = page_start;
			end = page_start + PAGE_SIZE;
			continue;
		}
		if (page_start == end) {
			end += PAGE_SIZE;
			continue;
		}
		nt35510_flush_bytes_locked(drvdata, first, end);
		first = page_start;
		end = page_start + PAGE_SIZE;
	}
	if (end)
		nt35510_flush_bytes_locked(drvdata, first, end);
	mutex_unlock(&drvdata->lock);
}

static int nt35510fb_check_var(struct fb_var_screeninfo *var,
		struct fb_info *info)
{
	struct nt35510_drvdata *drvdata = info->par;

	if (var->xres != drvdata->xres || var->yres != drvdata->yres ||
	    var->xres_virtual != drvdata->xres ||
	    var->yres_virtual != drvdata->yres || var->bits_per_pixel != 16)
		return -EINVAL;
	var->xoffset = 0;
	var->yoffset = 0;
	return 0;
}

static int nt35510fb_setcolreg(unsigned int regno, unsigned int red,
		unsigned int green, unsigned int blue, unsigned int transp,
		struct fb_info *info)
{
	u32 value;

	if (regno >= 16)
		return -EINVAL;
	red >>= 11;
	green >>= 10;
	blue >>= 11;
	value = (red << 11) | (green << 5) | blue;
	((u32 *)info->pseudo_palette)[regno] = value;
	return 0;
}

static ssize_t nt35510fb_write(struct fb_info *info, const char __user *buf,
		size_t count, loff_t *ppos)
{
	struct nt35510_drvdata *drvdata = info->par;
	loff_t start = *ppos;
	ssize_t ret;

	ret = fb_sys_write(info, buf, count, ppos);
	if (ret > 0) {
		mutex_lock(&drvdata->lock);
		nt35510_flush_bytes_locked(drvdata, start, start + ret);
		mutex_unlock(&drvdata->lock);
	}
	return ret;
}

static void nt35510fb_fillrect(struct fb_info *info,
		const struct fb_fillrect *rect)
{
	struct nt35510_drvdata *drvdata = info->par;
	u32 x1, y1;

	sys_fillrect(info, rect);
	if (!rect->width || !rect->height || rect->dx >= drvdata->xres ||
	    rect->dy >= drvdata->yres)
		return;
	x1 = min(rect->dx + rect->width, drvdata->xres) - 1;
	y1 = min(rect->dy + rect->height, drvdata->yres) - 1;
	mutex_lock(&drvdata->lock);
	nt35510_flush_rect_locked(drvdata, rect->dx, rect->dy, x1, y1);
	mutex_unlock(&drvdata->lock);
}

static void nt35510fb_copyarea(struct fb_info *info,
		const struct fb_copyarea *area)
{
	struct nt35510_drvdata *drvdata = info->par;
	u32 x1, y1;

	sys_copyarea(info, area);
	if (!area->width || !area->height || area->dx >= drvdata->xres ||
	    area->dy >= drvdata->yres)
		return;
	x1 = min(area->dx + area->width, drvdata->xres) - 1;
	y1 = min(area->dy + area->height, drvdata->yres) - 1;
	mutex_lock(&drvdata->lock);
	nt35510_flush_rect_locked(drvdata, area->dx, area->dy, x1, y1);
	mutex_unlock(&drvdata->lock);
}

static void nt35510fb_imageblit(struct fb_info *info,
		const struct fb_image *image)
{
	struct nt35510_drvdata *drvdata = info->par;
	u32 x1, y1;

	sys_imageblit(info, image);
	if (!image->width || !image->height || image->dx >= drvdata->xres ||
	    image->dy >= drvdata->yres)
		return;
	x1 = min(image->dx + image->width, drvdata->xres) - 1;
	y1 = min(image->dy + image->height, drvdata->yres) - 1;
	mutex_lock(&drvdata->lock);
	nt35510_flush_rect_locked(drvdata, image->dx, image->dy, x1, y1);
	mutex_unlock(&drvdata->lock);
}

static const struct fb_ops nt35510fb_ops = {
	.owner = THIS_MODULE,
	.fb_read = fb_sys_read,
	.fb_write = nt35510fb_write,
	.fb_check_var = nt35510fb_check_var,
	.fb_setcolreg = nt35510fb_setcolreg,
	.fb_fillrect = nt35510fb_fillrect,
	.fb_copyarea = nt35510fb_copyarea,
	.fb_imageblit = nt35510fb_imageblit,
};

static int nt35510fb_register(struct platform_device *pdev,
		struct nt35510_drvdata *drvdata)
{
	struct fb_info *info;
	int ret;

	drvdata->fbsize = drvdata->xres * drvdata->yres * BYTES_PER_PIXEL;
	drvdata->fbmem = vzalloc(drvdata->fbsize);
	if (!drvdata->fbmem)
		return -ENOMEM;

	info = framebuffer_alloc(0, &pdev->dev);
	if (!info) {
		vfree(drvdata->fbmem);
		drvdata->fbmem = NULL;
		return -ENOMEM;
	}

	drvdata->fb_info = info;
	info->par = drvdata;
	info->screen_base = (void __iomem *)drvdata->fbmem;
	info->screen_size = drvdata->fbsize;
	info->fbops = &nt35510fb_ops;
	info->flags = FBINFO_FLAG_DEFAULT | FBINFO_VIRTFB;
	strscpy(info->fix.id, "nt35510", sizeof(info->fix.id));
	info->fix.type = FB_TYPE_PACKED_PIXELS;
	info->fix.visual = FB_VISUAL_TRUECOLOR;
	info->fix.smem_len = drvdata->fbsize;
	info->fix.line_length = drvdata->xres * BYTES_PER_PIXEL;
	info->fix.accel = FB_ACCEL_NONE;
	info->var.xres = drvdata->xres;
	info->var.yres = drvdata->yres;
	info->var.xres_virtual = drvdata->xres;
	info->var.yres_virtual = drvdata->yres;
	info->var.bits_per_pixel = 16;
	info->var.red.offset = 11;
	info->var.red.length = 5;
	info->var.green.offset = 5;
	info->var.green.length = 6;
	info->var.blue.offset = 0;
	info->var.blue.length = 5;
	info->var.activate = FB_ACTIVATE_NOW;
	info->pseudo_palette = devm_kcalloc(&pdev->dev, 16, sizeof(u32),
			GFP_KERNEL);
	if (!info->pseudo_palette) {
		ret = -ENOMEM;
		goto err_release;
	}

	ret = fb_alloc_cmap(&info->cmap, 16, 0);
	if (ret)
		goto err_release;

	drvdata->fbdefio.delay = max_t(unsigned long, 1,
			HZ / NT35510_DEFAULT_DEFIO_HZ);
	drvdata->fbdefio.deferred_io = nt35510fb_deferred_io;
	info->fbdefio = &drvdata->fbdefio;
	fb_deferred_io_init(info);

	ret = register_framebuffer(info);
	if (ret)
		goto err_defio;

	fb_info(info, "NT35510 shadow framebuffer, %ux%u RGB565, %zu bytes\n",
		drvdata->xres, drvdata->yres, drvdata->fbsize);
	return 0;

err_defio:
	fb_deferred_io_cleanup(info);
	fb_dealloc_cmap(&info->cmap);
err_release:
	framebuffer_release(info);
	drvdata->fb_info = NULL;
	vfree(drvdata->fbmem);
	drvdata->fbmem = NULL;
	return ret;
}

static void nt35510fb_unregister(struct nt35510_drvdata *drvdata)
{
	if (!drvdata->fb_info)
		return;
	unregister_framebuffer(drvdata->fb_info);
	fb_deferred_io_cleanup(drvdata->fb_info);
	fb_dealloc_cmap(&drvdata->fb_info->cmap);
	framebuffer_release(drvdata->fb_info);
	drvdata->fb_info = NULL;
	vfree(drvdata->fbmem);
	drvdata->fbmem = NULL;
}

static int nt35510_open(struct inode *inode, struct file *file)
{
	int num = MINOR(inode->i_rdev);
	struct nt35510_drvdata *drvdata;

	if (num >= MAX_LCD_NUM || !nt35510s[num])
		return -ENODEV;
	drvdata = nt35510s[num];
	if (drvdata->isOpen) {
		return -EBUSY;
	}
	drvdata->isOpen = 1;
	drvdata->curr_off = 0;
	file->private_data = drvdata;
	file->f_pos = 0;
	return 0;
}

static int nt35510_release(struct inode *inode, struct file *file)
{
	struct nt35510_drvdata *drvdata = file->private_data;

	drvdata->isOpen = 0;
	return 0;
}

static ssize_t nt35510_write(struct file *file, const char __user *buf,
		size_t size, loff_t *poss)
{
	struct nt35510_drvdata *drvdata = file->private_data;
	unsigned long start = *poss;
	size_t count;
	ssize_t ret;

	if (start >= drvdata->fbsize)
		return 0;
	count = min_t(size_t, size, drvdata->fbsize - start);
	if (count & (BYTES_PER_PIXEL - 1))
		count--;
	if (!count)
		return 0;

	mutex_lock(&drvdata->lock);
	if (copy_from_user((u8 *)drvdata->fbmem + start, buf, count)) {
		ret = -EFAULT;
	} else {
		*poss += count;
		file->f_pos = *poss;
		drvdata->curr_off = *poss;
		nt35510_flush_bytes_locked(drvdata, start, start + count);
		ret = count;
	}
	mutex_unlock(&drvdata->lock);
	return ret;
}

static loff_t nt35510_llseek(struct file *file, loff_t offset, int whence)
{
	loff_t newpos;
	struct nt35510_drvdata *drvdata = file->private_data;

	switch (whence) {
		case 0:
			newpos = offset;
			break;
		case 1:
			newpos = file->f_pos + offset;
			break;
		case 2:
			newpos = drvdata->xres * drvdata->yres * BYTES_PER_PIXEL +
				offset;
			break;
		default:
			return -EINVAL;
	}
	dev_dbg(drvdata->device, "nt35510_llseek: opos=%lld, npos=%lld, tol=%d\n", file->f_pos, newpos, drvdata->xres * drvdata->yres * BYTES_PER_PIXEL);
	if (newpos % BYTES_PER_PIXEL != 0) {
		return -EINVAL;
	}
	if ((newpos < 0) ||
			(newpos > drvdata->xres * drvdata->yres * BYTES_PER_PIXEL))
		return -EINVAL;

	file->f_pos = newpos;
	drvdata->curr_off = newpos;
	return newpos;
}

static struct file_operations fops = {
	.owner = THIS_MODULE,
	.open = nt35510_open,
	.write = nt35510_write,
	.release = nt35510_release,
	.llseek = nt35510_llseek,
};

static int nt35510_of_probe(struct platform_device *pdev)
{
	struct nt35510_drvdata *drvdata;
	struct resource *res;
	struct device *device;
	int ret;

	drvdata = devm_kzalloc(&pdev->dev, sizeof(*drvdata), GFP_KERNEL);
	if (!drvdata)
		return -ENOMEM;
	*drvdata = default_nt35510_drvdata;
	dev_set_drvdata(&pdev->dev, drvdata);
	drvdata->device = &pdev->dev;
	mutex_init(&drvdata->lock);

	res = platform_get_resource(pdev, IORESOURCE_MEM, 0);
	drvdata->regs = devm_ioremap_resource(&pdev->dev, res);
	if (IS_ERR(drvdata->regs)) {
		ret = PTR_ERR(drvdata->regs);
		goto err_mutex;
	}

	drvdata->regs_phys = res->start;
	mutex_lock(&drvdata->lock);
	nt35510_init(drvdata);
	mutex_unlock(&drvdata->lock);

	ret = nt35510fb_register(pdev, drvdata);
	if (ret)
		goto err_mutex;

	device = device_create(nt35510_class, NULL, MKDEV(majorNumber, 0), NULL,
			"nt35510");
	if (IS_ERR(device)) {
		ret = PTR_ERR(device);
		nt35510fb_unregister(drvdata);
		goto err_mutex;
	}

	drvdata->device = device;
	nt35510s[0] = drvdata;
	dev_info(device, "nt35510: character device and fb0 ready, %ux%u, reg=%p\n",
			drvdata->xres, drvdata->yres, drvdata->regs);

	return 0;

err_mutex:
	mutex_destroy(&drvdata->lock);
	return ret;
}

static int nt35510_remove(struct platform_device *pdev)
{
	struct nt35510_drvdata *drvdata = platform_get_drvdata(pdev);
	if (drvdata->isOpen) {
		return -EBUSY;
	}
	device_destroy(nt35510_class, MKDEV(majorNumber, 0));
	nt35510s[0] = NULL;
	nt35510fb_unregister(drvdata);
	mutex_destroy(&drvdata->lock);
	return 0;
}

#ifdef CONFIG_OF
static const struct of_device_id nt35510_match[] = {
	{
		.compatible = "lcd,nt35510",
	},
	{},
};
MODULE_DEVICE_TABLE(of, nt35510_match);
#endif /* CONFIG_OF */

/*
 * Our device driver structure
 */
static struct platform_driver nt35510_driver = {
	.probe = nt35510_of_probe,
	.remove = nt35510_remove,
	.driver =
	{
		.name = DRV_NAME,
		.of_match_table = of_match_ptr(nt35510_match),
	},
};

static char *nt35510_devnode(struct device *dev, umode_t *mode)
{
	if (mode)
		*mode = 0200;
	return NULL;
}

static int __init nt35510_module_init(void)
{
	pr_info("nt35510: Initializing the nt35510\n");

	// Try to dynamically allocate a major number for the device -- more difficult but worth it
	majorNumber = register_chrdev(0, DRV_NAME, &fops);
	if (majorNumber < 0) {
		pr_alert("nt35510 failed to register a major number\n");
		return majorNumber;
	}
	nt35510_class = class_create(THIS_MODULE, CLASS_NAME);
	if (IS_ERR(nt35510_class)) {
		int ret = PTR_ERR(nt35510_class);

		unregister_chrdev(majorNumber, DRV_NAME);
		return ret;
	}
	nt35510_class->devnode = nt35510_devnode;

	if (platform_driver_register(&nt35510_driver)) {
		class_destroy(nt35510_class);
		unregister_chrdev(majorNumber, DRV_NAME);
		return -ENODEV;
	}
	pr_info("nt35510: registered correctly with major number %d\n",
			majorNumber);

	return 0;
}
static void __exit nt35510_module_exit(void)
{
	platform_driver_unregister(&nt35510_driver);
	class_destroy(nt35510_class);
	unregister_chrdev(majorNumber, DRV_NAME);
	pr_info("nt35510: unregistered");
}

module_init(nt35510_module_init);
module_exit(nt35510_module_exit);

MODULE_DESCRIPTION("NT35510 LCD Driver");
MODULE_AUTHOR("Zhang Yuxiang <zz593141477@gmail.com>");
MODULE_LICENSE("GPL");
MODULE_ALIAS("platform:" DRV_NAME);
