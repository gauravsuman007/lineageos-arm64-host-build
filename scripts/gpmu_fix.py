#!/usr/bin/env python3
"""Patch drivers/gpu/msm/adreno_a5xx.c: give the GPMU time to acknowledge power-level changes."""
import re, sys
p = sys.argv[1]
s = open(p).read()
old_start = s.index("static int gpmu_set_level(")
old_end = s.index("return (reg & 0x80000000) ? -ETIMEDOUT : 0;\n}", old_start) + len("return (reg & 0x80000000) ? -ETIMEDOUT : 0;\n}")
new = '''static int gpmu_set_level(struct adreno_device *adreno_dev, unsigned int val)
{
	unsigned int reg;
	/*
	 * The GPMU micro-controller needs time to acknowledge a level change.
	 * The original loop re-read the register 21 times back-to-back (a few
	 * microseconds in total), printed an error on every pass, and then gave
	 * up with the voltage change unconfirmed. Wait up to ~2 ms, quietly.
	 */
	int retry = 200;

	kgsl_regwrite(KGSL_DEVICE(adreno_dev), A5XX_GPMU_GPMU_VOLTAGE, val);

	do {
		kgsl_regread(KGSL_DEVICE(adreno_dev), A5XX_GPMU_GPMU_VOLTAGE, &reg);
		if (!(reg & 0x80000000))
			break;
		udelay(10);
	} while (retry--);

	if (reg & 0x80000000)
		pr_err_ratelimited("GPMU powerlevel %08x not acknowledged\\n", val);

	return (reg & 0x80000000) ? -ETIMEDOUT : 0;
}'''
s = s[:old_start] + new + s[old_end:]
if "#include <linux/delay.h>" not in s:
    s = s.replace("#include <linux/firmware.h>", "#include <linux/firmware.h>\n#include <linux/delay.h>", 1)
open(p, "w").write(s)
print("patched", p)
