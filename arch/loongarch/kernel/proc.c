// SPDX-License-Identifier: GPL-2.0
/*
 * Copyright (C) 2020-2021 Loongson Technology Corporation Limited
 */
#include <linux/delay.h>
#include <linux/kernel.h>
#include <linux/sched.h>
#include <linux/seq_file.h>
#include <asm/bootinfo.h>
#include <asm/cpu.h>
#include <asm/cpu-features.h>
#include <asm/idle.h>
#include <asm/processor.h>
#include <asm/time.h>

/*
 * No lock; only written during early bootup by CPU 0.
 */
static RAW_NOTIFIER_HEAD(proc_cpuinfo_chain);

int __ref register_proc_cpuinfo_notifier(struct notifier_block *nb)
{
	return raw_notifier_chain_register(&proc_cpuinfo_chain, nb);
}

int proc_cpuinfo_notifier_call_chain(unsigned long val, void *v)
{
	return raw_notifier_call_chain(&proc_cpuinfo_chain, val, v);
}

static int show_cpuinfo(struct seq_file *m, void *v)
{
	unsigned long n = (unsigned long)v - 1;
	unsigned int isa = cpu_data[n].isa_level;
	unsigned int version = cpu_data[n].processor_id & 0xff;
	unsigned int bogomips_unit = 500000 / HZ;
	u64 freq = cpu_clock_freq;
	struct proc_cpuinfo_notifier_args notifier_args;

#ifdef CONFIG_SMP
	if (!cpu_online(n))
		return 0;
#endif

	if (n == 0)
		seq_printf(m, "system type\t\t: %s\n\n", get_system_type());

	seq_printf(m, "processor\t\t: %lu\n", n);
	seq_printf(m, "package\t\t\t: %d\n", cpu_data[n].package);
	seq_printf(m, "core\t\t\t: %u\n", cpu_core(&cpu_data[n]));
	seq_printf(m, "CPU Family\t\t: %s\n", __cpu_family[n]);
	seq_printf(m, "Model Name\t\t: %s\n", __cpu_full_name[n]);
	seq_printf(m, "PRID\t\t\t: %08x\n", cpu_data[n].processor_id);
	seq_printf(m, "CPU Revision\t\t: 0x%02x\n", version);
	seq_printf(m, "FPU Revision\t\t: 0x%02x\n", cpu_data[n].fpu_vers);
	do_div(freq, 10000);
	seq_printf(m, "CPU MHz\t\t\t: %u.%02u\n",
		   (u32)freq / 100, (u32)freq % 100);
	if (bogomips_unit)
		seq_printf(m, "BogoMIPS\t\t: %u.%02u\n",
			   cpu_data[n].udelay_val / bogomips_unit,
			   (cpu_data[n].udelay_val % bogomips_unit) * 100 /
			   bogomips_unit);
	seq_printf(m, "TLB Entries\t\t: %d\n", cpu_data[n].tlbsize);
	seq_printf(m, "Address Sizes\t\t: %d bits physical, %d bits virtual\n",
		   cpu_pabits + 1, cpu_vabits + 1);

	seq_puts(m, "ISA\t\t\t:");
	if (isa & LOONGARCH_CPU_ISA_LA32R)
		seq_puts(m, " loongarch32r");
	if (isa & LOONGARCH_CPU_ISA_LA32S)
		seq_puts(m, " loongarch32s");
	if (isa & LOONGARCH_CPU_ISA_LA64)
		seq_puts(m, " loongarch64");
	seq_puts(m, "\n");

	seq_puts(m, "Features\t\t:");
	if (cpu_has_cpucfg)
		seq_puts(m, " cpucfg");
	if (cpu_has_csr)
		seq_puts(m, " csr");
	if (cpu_has_tlb)
		seq_puts(m, " tlb");
	if (cpu_has_vint)
		seq_puts(m, " vint");
	if (cpu_has_watch)
		seq_puts(m, " watch");
	seq_puts(m, "\n");

	seq_printf(m, "Hardware Watchpoint\t: %s",
		   cpu_has_watch ? "yes" : "no");
	if (cpu_has_watch)
		seq_printf(m, ", iwatch count: %u, dwatch count: %u",
			   cpu_data[n].watch_ireg_count,
			   cpu_data[n].watch_dreg_count);
	seq_puts(m, "\n");

	notifier_args.m = m;
	notifier_args.n = n;
	proc_cpuinfo_notifier_call_chain(0, &notifier_args);
	seq_puts(m, "\n");

	return 0;
}

static void *c_start(struct seq_file *m, loff_t *pos)
{
	unsigned long i = *pos;

	return i < NR_CPUS ? (void *)(i + 1) : NULL;
}

static void *c_next(struct seq_file *m, void *v, loff_t *pos)
{
	++*pos;
	return c_start(m, pos);
}

static void c_stop(struct seq_file *m, void *v)
{
}

const struct seq_operations cpuinfo_op = {
	.start	= c_start,
	.next	= c_next,
	.stop	= c_stop,
	.show	= show_cpuinfo,
};
