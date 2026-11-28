/* SPDX-License-Identifier: GPL-3.0-or-later
 * File references and the trash (freemac 1.221, Ferry 0.45.0): the File
 * Manager calls of CoreServices that Gas Mask and Sequel Pro make, written
 * for freemac from Apple's public documentation of each.
 *
 * An FSRef is 80 bytes the program keeps and copies. Ferry's holds a mark
 * and the address of a copy of the absolute path it was made from, kept
 * for as long as the program runs (a reference has no call that frees it).
 * The reference doesn't follow the file if it moves, as a Mac's does. The
 * trash is the freedesktop.org one, through NSFileManager. */
#import "FInternal.h"
#include <CoreServices/CoreServices.h>
#include <sys/stat.h>
#include <errno.h>
#include <limits.h>

#define FSREF_MARK 0x46725246u /* "FRrF" */

struct ferry_fsref {
    uint32_t mark;
    uint32_t length;
    const char *path;
};
_Static_assert(sizeof(struct ferry_fsref) <= sizeof(FSRef), "an FSRef holds Ferry's reference");

static const char *ref_path(const FSRef *ref)
{
    const struct ferry_fsref *r = (const struct ferry_fsref *)ref;
    return ref && r->mark == FSREF_MARK ? r->path : NULL;
}

/* Paths given out once are kept, so the same path makes the same reference. */
static const char *kept_path(const char *path)
{
    static NSMutableDictionary *kept;
    static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
    pthread_mutex_lock(&lock);
    if (!kept)
        kept = [[NSMutableDictionary alloc] init];
    NSString *key = [NSString stringWithUTF8String:path];
    NSValue *v = key ? kept[key] : nil;
    const char *copy = v ? [v pointerValue] : NULL;
    if (!copy && key) {
        copy = strdup(path);
        kept[key] = [NSValue valueWithPointer:copy];
    }
    pthread_mutex_unlock(&lock);
    return copy;
}

static OSStatus fill(const char *path, BOOL follow, FSRef *ref, Boolean *isDirectory)
{
    if (!path || !*path)
        return paramErr;
    char absolute[PATH_MAX];
    if (path[0] == '/')
        snprintf(absolute, sizeof absolute, "%s", path);
    else {
        char cwd[PATH_MAX];
        if (!getcwd(cwd, sizeof cwd))
            return ioErr;
        snprintf(absolute, sizeof absolute, "%s/%s", cwd, path);
    }
    NSString *standard = [[NSString stringWithUTF8String:absolute] stringByStandardizingPath];
    const char *p = [standard fileSystemRepresentation];
    struct stat st;
    if ((follow ? stat(p, &st) : lstat(p, &st)) != 0)
        return errno == EACCES ? permErr : fnfErr;
    if (isDirectory)
        *isDirectory = S_ISDIR(st.st_mode);
    if (ref) {
        memset(ref, 0, sizeof *ref);
        struct ferry_fsref *r = (struct ferry_fsref *)ref;
        r->mark = FSREF_MARK;
        r->path = kept_path(p);
        r->length = (uint32_t)strlen(r->path);
    }
    return noErr;
}

OSStatus FSPathMakeRef(const UInt8 *path, FSRef *ref, Boolean *isDirectory)
{
    return fill((const char *)path, YES, ref, isDirectory);
}

OSStatus FSPathMakeRefWithOptions(const UInt8 *path, OptionBits options, FSRef *ref, Boolean *isDirectory)
{
    return fill((const char *)path, !(options & kFSPathMakeRefDoNotFollowLeafSymlink), ref, isDirectory);
}

OSStatus FSRefMakePath(const FSRef *ref, UInt8 *path, UInt32 size)
{
    const char *p = ref_path(ref);
    if (!p)
        return errFSBadFSRef;
    if (!path || strlen(p) + 1 > size)
        return paramErr;
    strcpy((char *)path, p);
    return noErr;
}

OSErr FSCompareFSRefs(const FSRef *a, const FSRef *b)
{
    const char *pa = ref_path(a), *pb = ref_path(b);
    if (!pa || !pb)
        return paramErr;
    return strcmp(pa, pb) ? errFSRefsDifferent : noErr;
}

Boolean CFURLGetFSRef(CFURLRef url, struct FSRef *ref)
{
    NSURL *u = (NSURL *)url;
    if (![u isFileURL])
        return false;
    return fill([u fileSystemRepresentation], YES, ref, NULL) == noErr;
}

CFURLRef CFURLCreateFromFSRef(CFAllocatorRef allocator, const FSRef *ref)
{
    const char *p = ref_path(ref);
    if (!p)
        return NULL;
    BOOL dir = NO;
    [[NSFileManager defaultManager] fileExistsAtPath:@(p) isDirectory:&dir];
    return (CFURLRef)[[NSURL fileURLWithPath:@(p) isDirectory:dir] retain];
}

static OSStatus trash(const char *p, NSString **where)
{
    NSURL *result = nil;
    NSError *error = nil;
    if (![[NSFileManager defaultManager] trashItemAtURL:[NSURL fileURLWithPath:@(p)] resultingItemURL:&result
                                                  error:&error])
        return [error code] == NSFileNoSuchFileError ? fnfErr : ioErr;
    if (where)
        *where = [result path];
    return noErr;
}

OSStatus FSMoveObjectToTrashSync(const FSRef *source, FSRef *target, OptionBits options)
{
    const char *p = ref_path(source);
    if (!p)
        return errFSBadFSRef;
    NSString *where = nil;
    OSStatus r = trash(p, &where);
    if (r == noErr && target)
        fill([where fileSystemRepresentation], NO, target, NULL);
    return r;
}

/* ---- copying and moving (freemac 1.223, Ferry 0.47.0) ------------------------ */

static OSStatus status_of(NSError *error)
{
    NSError *posix = [error userInfo][NSUnderlyingErrorKey];
    NSInteger code = [[posix domain] isEqual:NSPOSIXErrorDomain] ? [posix code] : 0;
    if (code == EACCES || code == EPERM || [error code] == NSFileReadNoPermissionError ||
        [error code] == NSFileWriteNoPermissionError)
        return permErr;
    if (code == ENOENT || [error code] == NSFileNoSuchFileError || [error code] == NSFileReadNoSuchFileError)
        return fnfErr;
    if ([error code] == NSFileWriteFileExistsError || code == EEXIST)
        return dupFNErr;
    return ioErr;
}

static OSStatus copy_or_move(BOOL move, const char *from, const char *dir, CFStringRef name, NSString **where,
                             OptionBits options)
{
    if (!from || !dir)
        return errFSBadFSRef;
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *src = [fm stringWithFileSystemRepresentation:from length:strlen(from)];
    NSString *folder = [fm stringWithFileSystemRepresentation:dir length:strlen(dir)];
    BOOL isDir = NO;
    if (![fm fileExistsAtPath:folder isDirectory:&isDir] || !isDir)
        return dirNFErr;
    NSString *leaf = name ? (NSString *)name : [src lastPathComponent];
    if (![leaf length] || [leaf rangeOfString:@"/"].location != NSNotFound)
        return bdNamErr;
    NSString *dest = [folder stringByAppendingPathComponent:leaf];
    NSDictionary *there = [fm attributesOfItemAtPath:dest error:NULL];
    if (there) {
        if (!(options & kFSFileOperationOverwrite))
            return dupFNErr;
        NSError *error = nil;
        if (![fm removeItemAtPath:dest error:&error])
            return status_of(error);
    }
    NSError *error = nil;
    BOOL ok = move ? [fm moveItemAtPath:src toPath:dest error:&error] : [fm copyItemAtPath:src toPath:dest error:&error];
    if (!ok)
        return status_of(error);
    if (where)
        *where = dest;
    return noErr;
}

OSStatus FSCopyObjectSync(const FSRef *source, const FSRef *destDir, CFStringRef destName, FSRef *target,
                          OptionBits options)
{
    NSString *where = nil;
    OSStatus r = copy_or_move(NO, ref_path(source), ref_path(destDir), destName, &where, options);
    if (r == noErr && target)
        fill([where fileSystemRepresentation], NO, target, NULL);
    return r;
}

OSStatus FSMoveObjectSync(const FSRef *source, const FSRef *destDir, CFStringRef destName, FSRef *target,
                          OptionBits options)
{
    NSString *where = nil;
    OSStatus r = copy_or_move(YES, ref_path(source), ref_path(destDir), destName, &where, options);
    if (r == noErr && target)
        fill([where fileSystemRepresentation], NO, target, NULL);
    return r;
}

OSStatus FSPathCopyObjectSync(const char *sourcePath, const char *destDirPath, CFStringRef destName,
                              char **targetPath, OptionBits options)
{
    NSString *where = nil;
    OSStatus r = copy_or_move(NO, sourcePath, destDirPath, destName, &where, options);
    if (r == noErr && targetPath)
        *targetPath = strdup([where fileSystemRepresentation]);
    return r;
}

OSStatus FSPathMoveObjectSync(const char *sourcePath, const char *destDirPath, CFStringRef destName,
                              char **targetPath, OptionBits options)
{
    NSString *where = nil;
    OSStatus r = copy_or_move(YES, sourcePath, destDirPath, destName, &where, options);
    if (r == noErr && targetPath)
        *targetPath = strdup([where fileSystemRepresentation]);
    return r;
}

OSStatus FSPathMoveObjectToTrashSync(const char *sourcePath, char **targetPath, OptionBits options)
{
    FSRef ref;
    OSStatus r = fill(sourcePath, NO, &ref, NULL);
    if (r != noErr)
        return r;
    NSString *where = nil;
    r = trash(ref_path(&ref), &where);
    if (r == noErr && targetPath)
        *targetPath = strdup([where fileSystemRepresentation]);
    return r;
}

/* ---- catalog information ---------------------------------------------------
 * A file's kind, sizes and dates from stat. Mac dates count seconds from
 * 1904; the fraction is in 65536ths. */
static UTCDateTime utc(struct timespec t)
{
    UTCDateTime d;
    uint64_t secs = (uint64_t)t.tv_sec + 2082844800ull;
    d.highSeconds = (UInt16)(secs >> 32);
    d.lowSeconds = (UInt32)secs;
    d.fraction = (UInt16)(((uint64_t)t.tv_nsec << 16) / 1000000000ull);
    return d;
}

OSErr FSGetCatalogInfo(const FSRef *ref, FSCatalogInfoBitmap whichInfo, FSCatalogInfo *info, HFSUniStr255 *outName,
                       FSSpecPtr fsSpec, FSRef *parentRef)
{
    const char *p = ref_path(ref);
    if (!p)
        return errFSBadFSRef;
    struct stat st;
    if (stat(p, &st) != 0)
        return errno == ENOENT ? fnfErr : ioErr;
    @autoreleasepool {
        if (info) {
            memset(info, 0, sizeof *info);
            if (S_ISDIR(st.st_mode))
                info->nodeFlags |= kFSNodeIsDirectoryMask;
            info->nodeID = (UInt32)st.st_ino;
            info->createDate = utc(st.st_birthtimespec.tv_sec ? st.st_birthtimespec : st.st_mtimespec);
            info->contentModDate = utc(st.st_mtimespec);
            info->attributeModDate = utc(st.st_ctimespec);
            info->accessDate = utc(st.st_atimespec);
            info->permissions[0] = st.st_uid;
            info->permissions[1] = st.st_gid;
            info->permissions[2] = st.st_mode & 07777;
            if (!S_ISDIR(st.st_mode)) {
                info->dataLogicalSize = (UInt64)st.st_size;
                info->dataPhysicalSize = (UInt64)st.st_blocks * 512;
            } else if (whichInfo & kFSCatInfoValence) {
                NSArray *items = [[NSFileManager defaultManager]
                    contentsOfDirectoryAtPath:[NSString stringWithUTF8String:p] error:NULL];
                info->valence = (UInt32)[items count];
            }
        }
        if (outName) {
            NSString *name = [[NSString stringWithUTF8String:p] lastPathComponent] ?: @"";
            NSUInteger n = MIN([name length], (NSUInteger)255);
            [name getCharacters:outName->unicode range:NSMakeRange(0, n)];
            outName->length = (UInt16)n;
        }
        if (fsSpec)
            memset(fsSpec, 0, sizeof *fsSpec);
        if (parentRef) {
            NSString *parent = [[NSString stringWithUTF8String:p] stringByDeletingLastPathComponent];
            fill([parent fileSystemRepresentation], YES, parentRef, NULL);
        }
    }
    return noErr;
}

/* ---- icon references (freemac 1.223, Ferry 0.47.0) ------------------------------ */

/* An icon reference keeps the path of the file it was asked for, counted
 * as AcquireIconRef and ReleaseIconRef count it. */
OSErr GetIconRefFromFileInfo(const FSRef *ref, UniCharCount nameLength, const UniChar *name,
                             FSCatalogInfoBitmap whichInfo, const FSCatalogInfo *catalogInfo,
                             IconServicesUsageFlags flags, IconRef *out, SInt16 *label)
{
    if (!out)
        return paramErr;
    *out = NULL;
    const char *p = ref_path(ref);
    if (!p)
        return errFSBadFSRef;
    if (label)
        *label = 0;
    *out = (IconRef)[[NSString alloc] initWithUTF8String:p];
    return noErr;
}
/* A system icon's reference names its type as NSFileTypeForHFSTypeCode
 * writes one, 'ques' in single quotes, for PlotIconRefInContext to draw. */
OSErr GetIconRef(SInt16 vRefNum, OSType creator, OSType iconType, IconRef *out)
{
    (void)vRefNum;
    (void)creator;
    if (!out)
        return paramErr;
    char t[7] = { '\'', (char)(iconType >> 24), (char)(iconType >> 16), (char)(iconType >> 8), (char)iconType,
                  '\'', 0 };
    *out = (IconRef)[[NSString alloc] initWithBytes:t length:6 encoding:NSMacOSRomanStringEncoding];
    return *out ? noErr : paramErr;
}
OSErr AcquireIconRef(IconRef icon)
{
    if (!icon)
        return paramErr;
    [(id)icon retain];
    return noErr;
}
OSErr ReleaseIconRef(IconRef icon)
{
    if (!icon)
        return paramErr;
    [(id)icon release];
    return noErr;
}

/* No volume has a number Ferry hands out (freemac 1.233, VLC). */
OSStatus FSGetVolumeParms(FSVolumeRefNum volume, GetVolParmsInfoBuffer *buffer, unsigned long bufferSize)
{
    (void)volume;
    if (!buffer)
        return paramErr;
    memset(buffer, 0, bufferSize < sizeof *buffer ? bufferSize : sizeof *buffer);
    return nsvErr;
}

/* Result codes by name, for programs that show them (freemac 1.NEXT): the
 * names and meanings of MacErrors.h's codes that Ferry's own calls answer
 * with, from Apple's public result code list. send2trash (Python, which
 * Anki uses) looks the comment up when moving a file to the trash fails. */
static const struct {
    OSStatus code;
    const char *name, *comment;
} statuses[] = {
    {0, "noErr", "No error"},
    {-4, "unimpErr", "Unimplemented core routine"},
    {-35, "nsvErr", "No such volume"},
    {-36, "ioErr", "I/O error"},
    {-37, "bdNamErr", "Bad file name"},
    {-39, "eofErr", "End of file"},
    {-43, "fnfErr", "File not found"},
    {-48, "dupFNErr", "Duplicate file name"},
    {-50, "paramErr", "Error in user parameter list"},
    {-54, "permErr", "Permissions error"},
    {-108, "memFullErr", "Not enough room in heap zone"},
    {-120, "dirNFErr", "Directory not found"},
    {-128, "userCanceledErr", "User cancelled"},
    {-1401, "errFSBadFSRef", "FSRef parameter is bad"},
    {-1420, "errFSRefsDifferent", "FSRefs are different"},
    {-4960, "coreFoundationUnknownErr", "Unknown Core Foundation error"},
    {-5000, "afpAccessDenied", "Insufficient access privileges for operation"},
};

const char *GetMacOSStatusErrorString(OSStatus err)
{
    for (size_t i = 0; i < sizeof statuses / sizeof *statuses; i++)
        if (statuses[i].code == err)
            return statuses[i].name;
    return "";
}

const char *GetMacOSStatusCommentString(OSStatus err)
{
    for (size_t i = 0; i < sizeof statuses / sizeof *statuses; i++)
        if (statuses[i].code == err)
            return statuses[i].comment;
    return "";
}
