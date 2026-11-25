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
/* Copying and moving into a folder (freemac 1.223, Ferry 0.47.0), by
 * NSFileManager; destName NULL keeps the name. An item already there is
 * replaced only with kFSFileOperationOverwrite (otherwise dupFNErr). */
OSStatus FSCopyObjectSync(const FSRef *source, const FSRef *destDir, CFStringRef destName, FSRef *target,
                          OptionBits options);
OSStatus FSMoveObjectSync(const FSRef *source, const FSRef *destDir, CFStringRef destName, FSRef *target,
                          OptionBits options);
OSStatus FSPathCopyObjectSync(const char *sourcePath, const char *destDirPath, CFStringRef destName,
                              char **targetPath, OptionBits options);
OSStatus FSPathMoveObjectSync(const char *sourcePath, const char *destDirPath, CFStringRef destName,
                              char **targetPath, OptionBits options);

/* A file's catalog information (Files.h): its kind, sizes and dates, from
 * stat. Volumes, Finder information and permissions read as zero, and the
 * old FSSpec is never filled (64-bit Mac programs can't use one either). */
typedef int16_t FSVolumeRefNum;
typedef uint32_t FSCatalogInfoBitmap;
typedef struct HFSUniStr255 {
    UInt16 length;
    UniChar unicode[255];
} HFSUniStr255;
typedef struct FSSpec {
    FSVolumeRefNum vRefNum;
    SInt32 parID;
    Str63 name;
} FSSpec;
typedef FSSpec *FSSpecPtr;
typedef struct UTCDateTime {
    UInt16 highSeconds;
    UInt32 lowSeconds;
    UInt16 fraction;
} __attribute__((packed, aligned(2))) UTCDateTime;
typedef struct FSCatalogInfo {
    UInt16 nodeFlags;
    FSVolumeRefNum volume;
    UInt32 parentDirID;
    UInt32 nodeID;
    UInt8 sharingFlags;
    UInt8 userPrivileges;
    UInt8 reserved1;
    UInt8 reserved2;
    UTCDateTime createDate;
    UTCDateTime contentModDate;
    UTCDateTime attributeModDate;
    UTCDateTime accessDate;
    UTCDateTime backupDate;
    UInt32 permissions[4];
    UInt8 finderInfo[16];
    UInt8 extFinderInfo[16];
    UInt64 dataLogicalSize;
    UInt64 dataPhysicalSize;
    UInt64 rsrcLogicalSize;
    UInt64 rsrcPhysicalSize;
    UInt32 valence;
    UInt32 textEncodingHint;
} FSCatalogInfo;
enum {
    kFSCatInfoNone = 0, kFSCatInfoTextEncoding = 0x1, kFSCatInfoNodeFlags = 0x2, kFSCatInfoVolume = 0x4,
    kFSCatInfoParentDirID = 0x8, kFSCatInfoNodeID = 0x10, kFSCatInfoCreateDate = 0x20,
    kFSCatInfoContentMod = 0x40, kFSCatInfoAttrMod = 0x80, kFSCatInfoAccessDate = 0x100,
    kFSCatInfoBackupDate = 0x200, kFSCatInfoPermissions = 0x400, kFSCatInfoFinderInfo = 0x800,
    kFSCatInfoFinderXInfo = 0x1000, kFSCatInfoValence = 0x2000, kFSCatInfoDataSizes = 0x4000,
    kFSCatInfoRsrcSizes = 0x8000, kFSCatInfoSharingFlags = 0x10000, kFSCatInfoUserPrivs = 0x20000,
    kFSCatInfoUserAccess = 0x80000, kFSCatInfoAllDates = 0x3E0, kFSCatInfoGettableInfo = 0x3FFFF,
};
enum { kFSNodeLockedMask = 0x0001, kFSNodeIsDirectoryMask = 0x0010 };
OSErr FSGetCatalogInfo(const FSRef *ref, FSCatalogInfoBitmap whichInfo, FSCatalogInfo *catalogInfo,
                       HFSUniStr255 *outName, FSSpecPtr fsSpec, FSRef *parentRef);

/* A volume's parameters (Files.h; freemac 1.NEXT, Ferry 0.NEXT, VLC). Ferry
 * gives volumes no numbers, so FSGetVolumeParms zeroes the buffer and
 * answers nsvErr, "no such volume". */
typedef struct GetVolParmsInfoBuffer {
    SInt16 vMVersion;
    SInt32 vMAttrib;
    Handle vMLocalHand;
    SInt32 vMServerAdr;
    SInt32 vMVolumeGrade;
    SInt16 vMForeignPrivID;
    SInt32 vMExtendedAttributes;
    void *vMDeviceID;
    unsigned long vMMaxNameLength;
} GetVolParmsInfoBuffer;
OSStatus FSGetVolumeParms(FSVolumeRefNum volume, GetVolParmsInfoBuffer *buffer, unsigned long bufferSize);

/* Math64.h, which these days is a cast. */
static inline UInt64 UnsignedWideToUInt64(UnsignedWide w) { return ((UInt64)w.hi << 32) | w.lo; }
static inline UnsignedWide UInt64ToUnsignedWide(UInt64 v)
{
    UnsignedWide w = {(uint32_t)v, (uint32_t)(v >> 32)};
    return w;
}
__FERRY_END
#endif
