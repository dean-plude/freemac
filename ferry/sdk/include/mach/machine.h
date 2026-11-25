/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry SDK) */
/* The processor types and subtypes, as the public Mach-O file format
 * reference numbers them (freemac 1.223, Ferry 0.47.0): what a Mach-O
 * header names, and what sysctl's hw.cputype answers. */
#ifndef _FERRY_MACH_MACHINE_H_
#define _FERRY_MACH_MACHINE_H_
#include <_ferry.h>
__FERRY_BEGIN
#ifndef _FERRY_CPU_TYPE_T
#define _FERRY_CPU_TYPE_T
typedef int cpu_type_t;
typedef int cpu_subtype_t;
#endif
#ifndef CPU_TYPE_X86_64
#define CPU_ARCH_MASK 0xff000000
#define CPU_ARCH_ABI64 0x01000000
#define CPU_TYPE_ANY ((cpu_type_t)-1)
#define CPU_TYPE_X86 ((cpu_type_t)7)
#define CPU_TYPE_I386 CPU_TYPE_X86
#define CPU_TYPE_X86_64 (CPU_TYPE_X86 | CPU_ARCH_ABI64)
#define CPU_TYPE_ARM ((cpu_type_t)12)
#define CPU_TYPE_ARM64 (CPU_TYPE_ARM | CPU_ARCH_ABI64)
#define CPU_TYPE_POWERPC ((cpu_type_t)18)
#define CPU_TYPE_POWERPC64 (CPU_TYPE_POWERPC | CPU_ARCH_ABI64)
#define CPU_SUBTYPE_MASK 0xff000000
#define CPU_SUBTYPE_LIB64 0x80000000
#define CPU_SUBTYPE_X86_ALL ((cpu_subtype_t)3)
#define CPU_SUBTYPE_X86_64_ALL ((cpu_subtype_t)3)
#define CPU_SUBTYPE_X86_64_H ((cpu_subtype_t)8)
#define CPU_SUBTYPE_I386_ALL ((cpu_subtype_t)3)
#define CPU_SUBTYPE_ARM64_ALL ((cpu_subtype_t)0)
#define CPU_SUBTYPE_ARM64E ((cpu_subtype_t)2)
#endif
/* the PowerPC subtypes, which programs that name them all list (freemac 1.224) */
#ifndef CPU_SUBTYPE_POWERPC_ALL
#define CPU_SUBTYPE_POWERPC_ALL ((cpu_subtype_t)0)
#define CPU_SUBTYPE_POWERPC_601 ((cpu_subtype_t)1)
#define CPU_SUBTYPE_POWERPC_602 ((cpu_subtype_t)2)
#define CPU_SUBTYPE_POWERPC_603 ((cpu_subtype_t)3)
#define CPU_SUBTYPE_POWERPC_603e ((cpu_subtype_t)4)
#define CPU_SUBTYPE_POWERPC_603ev ((cpu_subtype_t)5)
#define CPU_SUBTYPE_POWERPC_604 ((cpu_subtype_t)6)
#define CPU_SUBTYPE_POWERPC_604e ((cpu_subtype_t)7)
#define CPU_SUBTYPE_POWERPC_620 ((cpu_subtype_t)8)
#define CPU_SUBTYPE_POWERPC_750 ((cpu_subtype_t)9)
#define CPU_SUBTYPE_POWERPC_7400 ((cpu_subtype_t)10)
#define CPU_SUBTYPE_POWERPC_7450 ((cpu_subtype_t)11)
#define CPU_SUBTYPE_POWERPC_970 ((cpu_subtype_t)100)
#endif
__FERRY_END
#endif
