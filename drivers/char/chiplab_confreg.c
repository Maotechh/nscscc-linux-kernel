// SPDX-License-Identifier: GPL-2.0
/*
 * Chiplab configuration-register driver.
 *
 * The register block provides the switches, buttons, LEDs, seven-segment
 * display, frequency register, and timer used by the Loongson experiment box.
 */

#include <linux/cdev.h>
#include <linux/device.h>
#include <linux/fs.h>
#include <linux/io.h>
#include <linux/ioport.h>
#include <linux/kernel.h>
#include <linux/module.h>
#include <linux/of.h>
#include <linux/platform_device.h>
#include <linux/slab.h>
#include <linux/spinlock.h>
#include <linux/sysfs.h>
#include <linux/uaccess.h>

#define DRIVER_NAME			"chiplab_confreg"
#define CHIPLAB_CONFREG_REG_SIZE	0x1034

#define TIMER_ADDR	0x0000
#define LED_ADDR	0x1000
#define LED_RG0_ADDR	0x1004
#define LED_RG1_ADDR	0x1008
#define NUM_ADDR	0x1010
#define SWITCH_ADDR	0x1020
#define BTN_KEY_ADDR	0x1024
#define BTN_STEP_ADDR	0x1028
#define FREQ_ADDR	0x1030

enum confreg_format {
	CONFREG_HEX2,
	CONFREG_HEX4,
	CONFREG_HEX8,
	CONFREG_DECIMAL,
	CONFREG_FREQUENCY,
};

struct confreg_device {
	void __iomem *base;
	resource_size_t phys_base;
	struct platform_device *pdev;
	struct cdev cdev;
	struct class *class;
	struct device *device;
	dev_t devt;
	spinlock_t lock;
};

struct confreg_attribute {
	struct device_attribute dev_attr;
	u32 offset;
	u32 mask;
	enum confreg_format format;
};

static bool debug;
module_param(debug, bool, 0644);
MODULE_PARM_DESC(debug, "Log character-device register accesses");

static bool confreg_offset_valid(u32 offset)
{
	switch (offset) {
	case TIMER_ADDR:
	case LED_ADDR:
	case LED_RG0_ADDR:
	case LED_RG1_ADDR:
	case NUM_ADDR:
	case SWITCH_ADDR:
	case BTN_KEY_ADDR:
	case BTN_STEP_ADDR:
	case FREQ_ADDR:
		return true;
	default:
		return false;
	}
}

static bool confreg_offset_writable(u32 offset)
{
	switch (offset) {
	case TIMER_ADDR:
	case LED_ADDR:
	case LED_RG0_ADDR:
	case LED_RG1_ADDR:
	case NUM_ADDR:
		return true;
	default:
		return false;
	}
}

static u32 confreg_readl(struct confreg_device *confreg, u32 offset)
{
	return ioread32(confreg->base + offset);
}

static void confreg_writel(struct confreg_device *confreg, u32 offset,
			   u32 value)
{
	iowrite32(value, confreg->base + offset);
}

static u32 confreg_read_locked(struct confreg_device *confreg, u32 offset)
{
	unsigned long flags;
	u32 value;

	spin_lock_irqsave(&confreg->lock, flags);
	value = confreg_readl(confreg, offset);
	spin_unlock_irqrestore(&confreg->lock, flags);

	return value;
}

static void confreg_write_locked(struct confreg_device *confreg, u32 offset,
				 u32 value)
{
	unsigned long flags;

	spin_lock_irqsave(&confreg->lock, flags);
	confreg_writel(confreg, offset, value);
	spin_unlock_irqrestore(&confreg->lock, flags);
}

static ssize_t confreg_attr_show(struct device *dev,
				 struct device_attribute *dev_attr, char *buf)
{
	struct confreg_attribute *attr;
	struct confreg_device *confreg = dev_get_drvdata(dev);
	u32 value;

	attr = container_of(dev_attr, struct confreg_attribute, dev_attr);
	value = confreg_read_locked(confreg, attr->offset) & attr->mask;

	switch (attr->format) {
	case CONFREG_HEX2:
		return sysfs_emit(buf, "0x%02x\n", value);
	case CONFREG_HEX4:
		return sysfs_emit(buf, "0x%04x\n", value);
	case CONFREG_HEX8:
		return sysfs_emit(buf, "0x%08x\n", value);
	case CONFREG_FREQUENCY:
		return sysfs_emit(buf, "%u Hz\n", value);
	case CONFREG_DECIMAL:
	default:
		return sysfs_emit(buf, "%u\n", value);
	}
}

static ssize_t confreg_attr_store(struct device *dev,
				  struct device_attribute *dev_attr,
				  const char *buf, size_t count)
{
	struct confreg_attribute *attr;
	struct confreg_device *confreg = dev_get_drvdata(dev);
	u32 value;
	int ret;

	attr = container_of(dev_attr, struct confreg_attribute, dev_attr);
	ret = kstrtou32(buf, 0, &value);
	if (ret)
		return ret;
	if (value & ~attr->mask)
		return -ERANGE;

	confreg_write_locked(confreg, attr->offset, value);
	return count;
}

#define CONFREG_ATTR_RW(_name, _offset, _mask, _format) \
	static struct confreg_attribute confreg_attr_##_name = { \
		.dev_attr = __ATTR(_name, 0644, confreg_attr_show, \
				  confreg_attr_store), \
		.offset = (_offset), \
		.mask = (_mask), \
		.format = (_format), \
	}

#define CONFREG_ATTR_RO(_name, _offset, _mask, _format) \
	static struct confreg_attribute confreg_attr_##_name = { \
		.dev_attr = __ATTR(_name, 0444, confreg_attr_show, NULL), \
		.offset = (_offset), \
		.mask = (_mask), \
		.format = (_format), \
	}

CONFREG_ATTR_RW(led, LED_ADDR, 0xffff, CONFREG_HEX4);
CONFREG_ATTR_RW(led_rg0, LED_RG0_ADDR, 0x3, CONFREG_DECIMAL);
CONFREG_ATTR_RW(led_rg1, LED_RG1_ADDR, 0x3, CONFREG_DECIMAL);
CONFREG_ATTR_RO(switch, SWITCH_ADDR, 0xff, CONFREG_HEX2);
CONFREG_ATTR_RO(btn_key, BTN_KEY_ADDR, 0xffff, CONFREG_HEX4);
CONFREG_ATTR_RO(btn_step, BTN_STEP_ADDR, 0x3, CONFREG_HEX2);
CONFREG_ATTR_RW(display, NUM_ADDR, U32_MAX, CONFREG_HEX8);
CONFREG_ATTR_RW(timer, TIMER_ADDR, U32_MAX, CONFREG_DECIMAL);
CONFREG_ATTR_RO(freq, FREQ_ADDR, U32_MAX, CONFREG_FREQUENCY);

static ssize_t all_leds_show(struct device *dev,
			     struct device_attribute *attr, char *buf)
{
	struct confreg_device *confreg = dev_get_drvdata(dev);
	unsigned long flags;
	u32 led, rg0, rg1;

	spin_lock_irqsave(&confreg->lock, flags);
	led = confreg_readl(confreg, LED_ADDR) & 0xffff;
	rg0 = confreg_readl(confreg, LED_RG0_ADDR) & 0x3;
	rg1 = confreg_readl(confreg, LED_RG1_ADDR) & 0x3;
	spin_unlock_irqrestore(&confreg->lock, flags);

	return sysfs_emit(buf, "main=0x%04x rg0=%u rg1=%u\n", led, rg0, rg1);
}

static ssize_t all_leds_store(struct device *dev,
			      struct device_attribute *attr,
			      const char *buf, size_t count)
{
	struct confreg_device *confreg = dev_get_drvdata(dev);
	unsigned long flags;
	u32 led, rg0, rg1;

	if (sscanf(buf, "%x %u %u", &led, &rg0, &rg1) != 3)
		return -EINVAL;
	if (led > 0xffff || rg0 > 3 || rg1 > 3)
		return -ERANGE;

	spin_lock_irqsave(&confreg->lock, flags);
	confreg_writel(confreg, LED_ADDR, led);
	confreg_writel(confreg, LED_RG0_ADDR, rg0);
	confreg_writel(confreg, LED_RG1_ADDR, rg1);
	spin_unlock_irqrestore(&confreg->lock, flags);

	return count;
}
static DEVICE_ATTR_RW(all_leds);

static ssize_t all_inputs_show(struct device *dev,
			       struct device_attribute *attr, char *buf)
{
	struct confreg_device *confreg = dev_get_drvdata(dev);
	unsigned long flags;
	u32 switches, buttons, step, frequency;

	spin_lock_irqsave(&confreg->lock, flags);
	switches = confreg_readl(confreg, SWITCH_ADDR) & 0xff;
	buttons = confreg_readl(confreg, BTN_KEY_ADDR) & 0xffff;
	step = confreg_readl(confreg, BTN_STEP_ADDR) & 0x3;
	frequency = confreg_readl(confreg, FREQ_ADDR);
	spin_unlock_irqrestore(&confreg->lock, flags);

	return sysfs_emit(buf,
			  "switches=0x%02x buttons=0x%04x step=0x%02x freq=%uHz\n",
			  switches, buttons, step, frequency);
}
static DEVICE_ATTR_RO(all_inputs);

static ssize_t all_registers_show(struct device *dev,
				  struct device_attribute *attr, char *buf)
{
	struct confreg_device *confreg = dev_get_drvdata(dev);
	unsigned long flags;
	u32 led, rg0, rg1, display, switches, buttons, step, timer, frequency;
	ssize_t len = 0;

	spin_lock_irqsave(&confreg->lock, flags);
	led = confreg_readl(confreg, LED_ADDR) & 0xffff;
	rg0 = confreg_readl(confreg, LED_RG0_ADDR) & 0x3;
	rg1 = confreg_readl(confreg, LED_RG1_ADDR) & 0x3;
	display = confreg_readl(confreg, NUM_ADDR);
	switches = confreg_readl(confreg, SWITCH_ADDR) & 0xff;
	buttons = confreg_readl(confreg, BTN_KEY_ADDR) & 0xffff;
	step = confreg_readl(confreg, BTN_STEP_ADDR) & 0x3;
	frequency = confreg_readl(confreg, FREQ_ADDR);
	timer = confreg_readl(confreg, TIMER_ADDR);
	spin_unlock_irqrestore(&confreg->lock, flags);

	len += sysfs_emit_at(buf, len, "Chiplab configuration registers\n");
	len += sysfs_emit_at(buf, len,
			     "LED: 0x%04x RGB0: %u RGB1: %u\n",
			     led, rg0, rg1);
	len += sysfs_emit_at(buf, len,
			     "Switches: 0x%02x Buttons: 0x%04x Step: 0x%02x\n",
			     switches, buttons, step);
	len += sysfs_emit_at(buf, len,
			     "Display: 0x%08x Timer: %u Freq: %u Hz\n",
			     display, timer, frequency);
	return len;
}
static DEVICE_ATTR_RO(all_registers);

static ssize_t device_info_show(struct device *dev,
				struct device_attribute *attr, char *buf)
{
	struct confreg_device *confreg = dev_get_drvdata(dev);

	return sysfs_emit(buf,
		"Chiplab Confreg Device (Loongson)\n"
		"Physical base: 0x%llx\n"
		"Character device: %u:%u\n"
		"Platform device: %s\n",
		(unsigned long long)confreg->phys_base,
		MAJOR(confreg->devt), MINOR(confreg->devt),
		dev_name(&confreg->pdev->dev));
}
static DEVICE_ATTR_RO(device_info);

static ssize_t driver_version_show(struct device *dev,
				   struct device_attribute *attr, char *buf)
{
	return sysfs_emit(buf, "2.1 (NSCSCC port)\n");
}
static DEVICE_ATTR_RO(driver_version);

static struct attribute *confreg_attrs[] = {
	&dev_attr_device_info.attr,
	&dev_attr_driver_version.attr,
	&confreg_attr_led.dev_attr.attr,
	&confreg_attr_led_rg0.dev_attr.attr,
	&confreg_attr_led_rg1.dev_attr.attr,
	&dev_attr_all_leds.attr,
	&confreg_attr_switch.dev_attr.attr,
	&confreg_attr_btn_key.dev_attr.attr,
	&confreg_attr_btn_step.dev_attr.attr,
	&dev_attr_all_inputs.attr,
	&confreg_attr_display.dev_attr.attr,
	&confreg_attr_timer.dev_attr.attr,
	&confreg_attr_freq.dev_attr.attr,
	&dev_attr_all_registers.attr,
	NULL,
};

static const struct attribute_group confreg_attr_group = {
	.attrs = confreg_attrs,
};

static const struct attribute_group *confreg_groups[] = {
	&confreg_attr_group,
	NULL,
};

static int confreg_open(struct inode *inode, struct file *file)
{
	struct confreg_device *confreg;

	confreg = container_of(inode->i_cdev, struct confreg_device, cdev);
	file->private_data = confreg;
	return 0;
}

static ssize_t confreg_read(struct file *file, char __user *buf,
			    size_t count, loff_t *position)
{
	struct confreg_device *confreg = file->private_data;
	u32 offset, value;

	if (count < sizeof(value))
		return -EINVAL;
	if (*position < 0 || *position > U32_MAX)
		return -EINVAL;

	offset = *position;
	if ((offset & 3) || !confreg_offset_valid(offset))
		return -EINVAL;

	value = confreg_read_locked(confreg, offset);
	if (copy_to_user(buf, &value, sizeof(value)))
		return -EFAULT;

	if (debug)
		dev_info(confreg->device, "read 0x%08x from offset 0x%x\n",
			 value, offset);
	*position += sizeof(value);
	return sizeof(value);
}

static ssize_t confreg_write(struct file *file, const char __user *buf,
			     size_t count, loff_t *position)
{
	struct confreg_device *confreg = file->private_data;
	u32 offset, value;

	if (count != sizeof(value))
		return -EINVAL;
	if (*position < 0 || *position > U32_MAX)
		return -EINVAL;

	offset = *position;
	if ((offset & 3) || !confreg_offset_valid(offset))
		return -EINVAL;
	if (!confreg_offset_writable(offset))
		return -EPERM;
	if (copy_from_user(&value, buf, sizeof(value)))
		return -EFAULT;

	confreg_write_locked(confreg, offset, value);
	if (debug)
		dev_info(confreg->device, "wrote 0x%08x to offset 0x%x\n",
			 value, offset);
	*position += sizeof(value);
	return sizeof(value);
}

static const struct file_operations confreg_fops = {
	.owner = THIS_MODULE,
	.open = confreg_open,
	.read = confreg_read,
	.write = confreg_write,
	.llseek = default_llseek,
};

static int confreg_setup_chardev(struct confreg_device *confreg)
{
	int ret;

	ret = alloc_chrdev_region(&confreg->devt, 0, 1, DRIVER_NAME);
	if (ret)
		return ret;

	cdev_init(&confreg->cdev, &confreg_fops);
	confreg->cdev.owner = THIS_MODULE;
	ret = cdev_add(&confreg->cdev, confreg->devt, 1);
	if (ret)
		goto err_unregister;

	confreg->class = class_create(THIS_MODULE, DRIVER_NAME);
	if (IS_ERR(confreg->class)) {
		ret = PTR_ERR(confreg->class);
		goto err_cdev;
	}
	confreg->class->dev_groups = confreg_groups;

	confreg->device = device_create(confreg->class, &confreg->pdev->dev,
					  confreg->devt, confreg, DRIVER_NAME);
	if (IS_ERR(confreg->device)) {
		ret = PTR_ERR(confreg->device);
		goto err_class;
	}

	return 0;

err_class:
	class_destroy(confreg->class);
err_cdev:
	cdev_del(&confreg->cdev);
err_unregister:
	unregister_chrdev_region(confreg->devt, 1);
	return ret;
}

static void confreg_cleanup_chardev(struct confreg_device *confreg)
{
	device_destroy(confreg->class, confreg->devt);
	class_destroy(confreg->class);
	cdev_del(&confreg->cdev);
	unregister_chrdev_region(confreg->devt, 1);
}

static int confreg_probe(struct platform_device *pdev)
{
	struct confreg_device *confreg;
	struct resource *res;
	int ret;

	confreg = devm_kzalloc(&pdev->dev, sizeof(*confreg), GFP_KERNEL);
	if (!confreg)
		return -ENOMEM;

	res = platform_get_resource(pdev, IORESOURCE_MEM, 0);
	if (!res)
		return -ENODEV;
	if (resource_size(res) < CHIPLAB_CONFREG_REG_SIZE) {
		dev_err(&pdev->dev, "register resource is too small: 0x%llx bytes\n",
			(unsigned long long)resource_size(res));
		return -EINVAL;
	}

	confreg->base = devm_ioremap_resource(&pdev->dev, res);
	if (IS_ERR(confreg->base))
		return PTR_ERR(confreg->base);

	confreg->phys_base = res->start;
	confreg->pdev = pdev;
	spin_lock_init(&confreg->lock);
	platform_set_drvdata(pdev, confreg);

	ret = confreg_setup_chardev(confreg);
	if (ret)
		return dev_err_probe(&pdev->dev, ret,
				     "failed to register character device\n");

	dev_info(&pdev->dev,
		 "registered /dev/%s and /sys/class/%s/%s\n",
		 DRIVER_NAME, DRIVER_NAME, DRIVER_NAME);
	return 0;
}

static int confreg_remove(struct platform_device *pdev)
{
	struct confreg_device *confreg = platform_get_drvdata(pdev);

	confreg_cleanup_chardev(confreg);
	return 0;
}

static const struct of_device_id confreg_of_match[] = {
	{ .compatible = "loongson,chiplab_confreg" },
	{ }
};
MODULE_DEVICE_TABLE(of, confreg_of_match);

static struct platform_driver confreg_driver = {
	.probe = confreg_probe,
	.remove = confreg_remove,
	.driver = {
		.name = DRIVER_NAME,
		.of_match_table = confreg_of_match,
	},
};
module_platform_driver(confreg_driver);

MODULE_AUTHOR("DFPMTS; NSCSCC port by Maotech");
MODULE_DESCRIPTION("Chiplab experiment-box configuration registers");
MODULE_LICENSE("GPL");
MODULE_VERSION("2.1");
