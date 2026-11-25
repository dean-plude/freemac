/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: the low-level event flags Cocoa apps still name, written from
 * Apple's public documentation of NSEvent's modifier flags, of which these
 * are the older names: the device-independent masks in the top half and
 * the left- and right-hand keys' device-dependent bits in the bottom half.
 * Ferry has no IOKit; nothing here calls into one. */
#ifndef _FERRY_IOKIT_IOLLEVENT_H_
#define _FERRY_IOKIT_IOLLEVENT_H_

#define NX_ALPHASHIFTMASK 0x00010000
#define NX_SHIFTMASK 0x00020000
#define NX_CONTROLMASK 0x00040000
#define NX_ALTERNATEMASK 0x00080000
#define NX_COMMANDMASK 0x00100000
#define NX_NUMERICPADMASK 0x00200000
#define NX_HELPMASK 0x00400000
#define NX_SECONDARYFNMASK 0x00800000
#define NX_ALPHASHIFT_STATELESS_MASK 0x01000000

#define NX_DEVICELCTLKEYMASK 0x00000001
#define NX_DEVICELSHIFTKEYMASK 0x00000002
#define NX_DEVICERSHIFTKEYMASK 0x00000004
#define NX_DEVICELCMDKEYMASK 0x00000008
#define NX_DEVICERCMDKEYMASK 0x00000010
#define NX_DEVICELALTKEYMASK 0x00000020
#define NX_DEVICERALTKEYMASK 0x00000040
#define NX_DEVICE_ALPHASHIFT_STATELESS_MASK 0x00000080
#define NX_DEVICERCTLKEYMASK 0x00002000

/* The event types by their old numbers, as NSEventType has them. */
#define NX_NULLEVENT 0
#define NX_LMOUSEDOWN 1
#define NX_LMOUSEUP 2
#define NX_RMOUSEDOWN 3
#define NX_RMOUSEUP 4
#define NX_MOUSEMOVED 5
#define NX_LMOUSEDRAGGED 6
#define NX_RMOUSEDRAGGED 7
#define NX_MOUSEENTERED 8
#define NX_MOUSEEXITED 9
#define NX_KEYDOWN 10
#define NX_KEYUP 11
#define NX_FLAGSCHANGED 12
#define NX_SYSDEFINED 14
#define NX_SCROLLWHEELMOVED 22
#define NX_OMOUSEDOWN 25
#define NX_OMOUSEUP 26
#define NX_OMOUSEDRAGGED 27

#endif
