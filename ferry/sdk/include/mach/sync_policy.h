/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry SDK) */
/* The policies a Mach semaphore takes (freemac 1.232). */
#ifndef _FERRY_MACH_SYNC_POLICY_H_
#define _FERRY_MACH_SYNC_POLICY_H_
typedef int sync_policy_t;
#define SYNC_POLICY_FIFO 0x0
#define SYNC_POLICY_FIXED_PRIORITY 0x1
#define SYNC_POLICY_REVERSED 0x2
#define SYNC_POLICY_ORDER_MASK 0x3
#define SYNC_POLICY_LIFO (SYNC_POLICY_FIFO | SYNC_POLICY_REVERSED)
#endif
