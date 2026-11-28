// SPDX-License-Identifier: GPL-3.0-or-later
//
// Ferry's Swift overlay for IOKit (freemac 1.271): the kIOReturn codes,
// which C headers build with iokit_common_err() and Swift can't read,
// as the Int32 values that Swift code on a Mac sees (Stats compares its
// IOKit results with them). The values are those of IOKit's public
// IOReturn.h documentation.

@_exported import IOKit

public var kIOReturnSuccess: Int32 { 0 }
public var kIOReturnError: Int32 { Int32(bitPattern: 0xe000_0000 | 0x2bc) }
public var kIOReturnNoMemory: Int32 { Int32(bitPattern: 0xe000_0000 | 0x2bd) }
public var kIOReturnNoResources: Int32 { Int32(bitPattern: 0xe000_0000 | 0x2be) }
public var kIOReturnIPCError: Int32 { Int32(bitPattern: 0xe000_0000 | 0x2bf) }
public var kIOReturnNoDevice: Int32 { Int32(bitPattern: 0xe000_0000 | 0x2c0) }
public var kIOReturnNotPrivileged: Int32 { Int32(bitPattern: 0xe000_0000 | 0x2c1) }
public var kIOReturnBadArgument: Int32 { Int32(bitPattern: 0xe000_0000 | 0x2c2) }
public var kIOReturnLockedRead: Int32 { Int32(bitPattern: 0xe000_0000 | 0x2c3) }
public var kIOReturnLockedWrite: Int32 { Int32(bitPattern: 0xe000_0000 | 0x2c4) }
public var kIOReturnExclusiveAccess: Int32 { Int32(bitPattern: 0xe000_0000 | 0x2c5) }
public var kIOReturnBadMessageID: Int32 { Int32(bitPattern: 0xe000_0000 | 0x2c6) }
public var kIOReturnUnsupported: Int32 { Int32(bitPattern: 0xe000_0000 | 0x2c7) }
public var kIOReturnVMError: Int32 { Int32(bitPattern: 0xe000_0000 | 0x2c8) }
public var kIOReturnInternalError: Int32 { Int32(bitPattern: 0xe000_0000 | 0x2c9) }
public var kIOReturnIOError: Int32 { Int32(bitPattern: 0xe000_0000 | 0x2ca) }
public var kIOReturnCannotLock: Int32 { Int32(bitPattern: 0xe000_0000 | 0x2cc) }
public var kIOReturnNotOpen: Int32 { Int32(bitPattern: 0xe000_0000 | 0x2cd) }
public var kIOReturnNotReadable: Int32 { Int32(bitPattern: 0xe000_0000 | 0x2ce) }
public var kIOReturnNotWritable: Int32 { Int32(bitPattern: 0xe000_0000 | 0x2cf) }
public var kIOReturnNotAligned: Int32 { Int32(bitPattern: 0xe000_0000 | 0x2d0) }
public var kIOReturnBadMedia: Int32 { Int32(bitPattern: 0xe000_0000 | 0x2d1) }
public var kIOReturnStillOpen: Int32 { Int32(bitPattern: 0xe000_0000 | 0x2d2) }
public var kIOReturnRLDError: Int32 { Int32(bitPattern: 0xe000_0000 | 0x2d3) }
public var kIOReturnDMAError: Int32 { Int32(bitPattern: 0xe000_0000 | 0x2d4) }
public var kIOReturnBusy: Int32 { Int32(bitPattern: 0xe000_0000 | 0x2d5) }
public var kIOReturnTimeout: Int32 { Int32(bitPattern: 0xe000_0000 | 0x2d6) }
public var kIOReturnOffline: Int32 { Int32(bitPattern: 0xe000_0000 | 0x2d7) }
public var kIOReturnNotReady: Int32 { Int32(bitPattern: 0xe000_0000 | 0x2d8) }
public var kIOReturnNotAttached: Int32 { Int32(bitPattern: 0xe000_0000 | 0x2d9) }
public var kIOReturnNoChannels: Int32 { Int32(bitPattern: 0xe000_0000 | 0x2da) }
public var kIOReturnNoSpace: Int32 { Int32(bitPattern: 0xe000_0000 | 0x2db) }
public var kIOReturnPortExists: Int32 { Int32(bitPattern: 0xe000_0000 | 0x2dd) }
public var kIOReturnCannotWire: Int32 { Int32(bitPattern: 0xe000_0000 | 0x2de) }
public var kIOReturnNoInterrupt: Int32 { Int32(bitPattern: 0xe000_0000 | 0x2df) }
public var kIOReturnNoFrames: Int32 { Int32(bitPattern: 0xe000_0000 | 0x2e0) }
public var kIOReturnMessageTooLarge: Int32 { Int32(bitPattern: 0xe000_0000 | 0x2e1) }
public var kIOReturnNotPermitted: Int32 { Int32(bitPattern: 0xe000_0000 | 0x2e2) }
public var kIOReturnNoPower: Int32 { Int32(bitPattern: 0xe000_0000 | 0x2e3) }
public var kIOReturnNoMedia: Int32 { Int32(bitPattern: 0xe000_0000 | 0x2e4) }
public var kIOReturnUnformattedMedia: Int32 { Int32(bitPattern: 0xe000_0000 | 0x2e5) }
public var kIOReturnUnsupportedMode: Int32 { Int32(bitPattern: 0xe000_0000 | 0x2e6) }
public var kIOReturnUnderrun: Int32 { Int32(bitPattern: 0xe000_0000 | 0x2e7) }
public var kIOReturnOverrun: Int32 { Int32(bitPattern: 0xe000_0000 | 0x2e8) }
public var kIOReturnDeviceError: Int32 { Int32(bitPattern: 0xe000_0000 | 0x2e9) }
public var kIOReturnNoCompletion: Int32 { Int32(bitPattern: 0xe000_0000 | 0x2ea) }
public var kIOReturnAborted: Int32 { Int32(bitPattern: 0xe000_0000 | 0x2eb) }
public var kIOReturnNoBandwidth: Int32 { Int32(bitPattern: 0xe000_0000 | 0x2ec) }
public var kIOReturnNotResponding: Int32 { Int32(bitPattern: 0xe000_0000 | 0x2ed) }
public var kIOReturnIsoTooOld: Int32 { Int32(bitPattern: 0xe000_0000 | 0x2ee) }
public var kIOReturnIsoTooNew: Int32 { Int32(bitPattern: 0xe000_0000 | 0x2ef) }
public var kIOReturnNotFound: Int32 { Int32(bitPattern: 0xe000_0000 | 0x2f0) }
public var kIOReturnInvalid: Int32 { Int32(bitPattern: 0xe000_0000 | 0x1) }
