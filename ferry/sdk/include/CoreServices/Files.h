/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: the few File Manager calls of CoreServices that Cocoa apps
 * still make, written from Apple's public documentation (freemac 1.221,
 * Ferry 0.45.0): a file reference made from a path, the path back, and
 * moving a file to the trash, which is the desktop's own (the
 * freedesktop.org trash, as NSFileManager's trashItemAtURL: uses). A
 * reference names a path, not the file itself, so it doesn't follow a
 * file that moves. Served from Foundation's file. */
#ifndef _FERRY_CORESERVICES_FILES_H_
#define _FERRY_CORESERVICES_FILES_H_
#include <CoreFoundation/CoreFoundation.h>

__FERRY_BEGIN
#ifndef _FERRY_FSREF_DEFINED
#define _FERRY_FSREF_DEFINED
struct FSRef { uint8_t hidden[80]; };
typedef struct FSRef FSRef;
#endif
typedef FSRef *FSRefPtr;
typedef uint32_t OptionBits;

enum { kFSFileOperationDefaultOptions = 0, kFSFileOperationOverwrite = 1, kFSFileOperationSkipSourcePermissionErrors = 2,
       kFSFileOperationDoNotMoveAcrossVolumes = 4, kFSFileOperationSkipPreflight = 8 };
enum { kFSPathMakeRefDefaultOptions = 0, kFSPathMakeRefDoNotFollowLeafSymlink = 1 };
/* The File Manager's result codes (MacErrors.h). */
enum { nsvErr = -35, ioErr = -36, bdNamErr = -37, eofErr = -39, dupFNErr = -48, permErr = -54,
       dirNFErr = -120, afpAccessDenied = -5000, errFSBadFSRef = -1401, errFSRefsDifferent = -1420 };

OSStatus FSPathMakeRef(const UInt8 *path, FSRef *ref, Boolean *isDirectory);
OSStatus FSPathMakeRefWithOptions(const UInt8 *path, OptionBits options, FSRef *ref, Boolean *isDirectory);
OSStatus FSRefMakePath(const FSRef *ref, UInt8 *path, UInt32 pathBufferSize);
Boolean CFURLGetFSRef(CFURLRef url, FSRef *fsRef);
CFURLRef CFURLCreateFromFSRef(CFAllocatorRef allocator, const FSRef *fsRef);
OSStatus FSMoveObjectToTrashSync(const FSRef *source, FSRef *target, OptionBits options);
OSStatus FSPathMoveObjectToTrashSync(const char *sourcePath, char **targetPath, OptionBits options);
OSErr FSCompareFSRefs(const FSRef *ref1, const FSRef *ref2);

/* Math64.h, which these days is a cast. */
static inline UInt64 UnsignedWideToUInt64(UnsignedWide w) { return ((UInt64)w.hi << 32) | w.lo; }
static inline UnsignedWide UInt64ToUnsignedWide(UInt64 v)
{
    UnsignedWide w = {(uint32_t)v, (uint32_t)(v >> 32)};
    return w;
}
__FERRY_END
#endif
