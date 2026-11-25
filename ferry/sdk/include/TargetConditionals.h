/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: which system a program is being built for, as the public
 * TARGET_OS_ and TARGET_CPU_ conditionals describe it. Ferry builds for an
 * Intel Mac and nothing else (freemac 1.221, Ferry 0.45.0). Written for
 * freemac; not Apple's header. */
#ifndef _FERRY_TARGETCONDITIONALS_H_
#define _FERRY_TARGETCONDITIONALS_H_

#define TARGET_OS_MAC 1
#define TARGET_OS_OSX 1
#define TARGET_OS_UNIX 0
#define TARGET_OS_WIN32 0
#define TARGET_OS_WINDOWS 0
#define TARGET_OS_LINUX 0
#define TARGET_OS_IPHONE 0
#define TARGET_OS_IOS 0
#define TARGET_OS_MACCATALYST 0
#define TARGET_OS_UIKITFORMAC 0
#define TARGET_OS_TV 0
#define TARGET_OS_WATCH 0
#define TARGET_OS_VISION 0
#define TARGET_OS_BRIDGE 0
#define TARGET_OS_DRIVERKIT 0
#define TARGET_OS_SIMULATOR 0
#define TARGET_OS_EMBEDDED 0
#define TARGET_OS_NANO 0
#define TARGET_IPHONE_SIMULATOR 0
#define TARGET_ABI_USES_IOS_VALUES 0

#define TARGET_CPU_X86_64 1
#define TARGET_CPU_X86 0
#define TARGET_CPU_ARM 0
#define TARGET_CPU_ARM64 0
#define TARGET_CPU_PPC 0
#define TARGET_CPU_PPC64 0
#define TARGET_CPU_68K 0
#define TARGET_CPU_MIPS 0
#define TARGET_CPU_SPARC 0
#define TARGET_CPU_ALPHA 0

#define TARGET_RT_LITTLE_ENDIAN 1
#define TARGET_RT_BIG_ENDIAN 0
#define TARGET_RT_64_BIT 1
#define TARGET_RT_MAC_CFM 0
#define TARGET_RT_MAC_MACHO 1

#endif
