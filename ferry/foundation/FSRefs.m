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
