/* SPDX-License-Identifier: GPL-3.0-or-later
 * More of CoreServices and CoreFoundation, for apps built with wxWidgets
 * such as Audacity (freemac 1.263, Ferry 0.86.0), written from Apple's
 * public documentation of each call.
 *
 * - FSFindFolder: the Folder Manager's standard folders (preferences,
 *   application support, caches, temporary items, the desktop, documents
 *   and the rest) for the user's domain, found where NSFileManager finds
 *   the same folders on freemac. Asked to, it makes the folder first.
 * - InstallDebugAssertOutputHandler: AssertMacros' report handler. Ferry
 *   keeps it and calls it as a Mac does when an assertion fails in a
 *   program that reports through DebugAssert.
 * - CFBundleGetVersionNumber: the bundle's version as a NumVersion.
 * - kCFAllocatorMalloc and two more uniform type constants. */
#import "FInternal.h"
#include <CoreServices/CoreServices.h>
#include <sys/stat.h>
#include <errno.h>
#include <limits.h>
#include <stdlib.h>

/* ---- the Folder Manager ------------------------------------------------------- */

enum {
    kSystemDomain = -32766, kLocalDomain = -32765,
    kNetworkDomain = -32764, kUserDomain = -32763, kClassicDomain = -32762, kLastDomainConstant = -32760,
};

static NSString *standard(NSSearchPathDirectory which)
{
    NSArray *a = NSSearchPathForDirectoriesInDomains(which, NSUserDomainMask, YES);
    return a.count ? a[0] : nil;
}

static NSString *folder_for(OSType type)
{
    switch (type) {
    case 'pref': return [standard(NSLibraryDirectory) stringByAppendingPathComponent:@"Preferences"];
    case 'asup': return standard(NSApplicationSupportDirectory);
    case 'cach': return standard(NSCachesDirectory);
    case 'temp':
    case 'chew':
    case 'trsh':
        if (type == 'trsh')
            return [NSHomeDirectory() stringByAppendingPathComponent:@".local/share/Trash/files"];
        return [NSTemporaryDirectory() stringByStandardizingPath];
    case 'desk': return standard(NSDesktopDirectory);
    case 'docs': return standard(NSDocumentDirectory);
    case 'dlib': return standard(NSLibraryDirectory);
    case 'cusr': return NSHomeDirectory();
    case 'down': return standard(NSDownloadsDirectory);
    case 'mdoc': return standard(NSMoviesDirectory);
    case 'mmus': return standard(NSMusicDirectory);
    case 'pdoc': return standard(NSPicturesDirectory);
    case 'apps': return standard(NSApplicationDirectory);
    case 'fnts': return [standard(NSLibraryDirectory) stringByAppendingPathComponent:@"Fonts"];
    case 'logs': return [standard(NSLibraryDirectory) stringByAppendingPathComponent:@"Logs"];
    case 'pubb': return [NSHomeDirectory() stringByAppendingPathComponent:@"Public"];
    case 'audi': return [standard(NSLibraryDirectory) stringByAppendingPathComponent:@"Audio"];
    case 'aplg':
    case 'audp': return [standard(NSLibraryDirectory) stringByAppendingPathComponent:@"Audio/Plug-Ins"];
    case 'acmp': return [standard(NSLibraryDirectory) stringByAppendingPathComponent:@"Audio/Plug-Ins/Components"];
    default: return nil;
    }
}

OSErr FSFindFolder(FSVolumeRefNum vRefNum, OSType folderType, Boolean createFolder, FSRef *foundRef)
{
    if (!foundRef)
        return paramErr;
    if (vRefNum != kUserDomain && vRefNum != kOnAppropriateDisk && vRefNum != kOnSystemDisk &&
        vRefNum != kLocalDomain)
        return fnfErr;
    NSString *path = folder_for(folderType);
    if (!path)
        return fnfErr;
    BOOL isDir = NO;
    if (![[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDir]) {
        if (!createFolder)
            return fnfErr;
        if (![[NSFileManager defaultManager] createDirectoryAtPath:path withIntermediateDirectories:YES
                                                        attributes:nil error:NULL])
            return permErr;
    } else if (!isDir)
        return dirNFErr;
    return FSPathMakeRef((const UInt8 *)[path fileSystemRepresentation], foundRef, NULL);
}

OSErr FSFindFolderExtended(FSVolumeRefNum vRefNum, OSType folderType, Boolean createFolder, UInt32 flags,
                           void *data, FSRef *foundRef)
{
    return FSFindFolder(vRefNum, folderType, createFolder, foundRef);
}

/* ---- AssertMacros' output handler ------------------------------------------------- */

typedef void (*DebugAssertOutputHandlerUPP)(OSType componentSignature, UInt32 options, const char *assertionString,
                                            const char *exceptionLabelString, const char *errorString,
                                            const char *fileName, long lineNumber, void *value,
                                            const unsigned char *outputMsg);

static DebugAssertOutputHandlerUPP assert_handler;

void InstallDebugAssertOutputHandler(DebugAssertOutputHandlerUPP handler) { assert_handler = handler; }
void RemoveDebugAssertOutputHandler(DebugAssertOutputHandlerUPP handler)
{
    if (assert_handler == handler)
        assert_handler = NULL;
}
DebugAssertOutputHandlerUPP NewDebugAssertOutputHandlerUPP(DebugAssertOutputHandlerUPP p) { return p; }
void DisposeDebugAssertOutputHandlerUPP(DebugAssertOutputHandlerUPP p) {}

void DebugAssert(OSType componentSignature, UInt32 options, const char *assertionString,
                 const char *exceptionLabelString, const char *errorString, const char *fileName, long lineNumber,
                 void *value)
{
    if (assert_handler)
        assert_handler(componentSignature, options, assertionString, exceptionLabelString, errorString, fileName,
                       lineNumber, value, NULL);
    else
        fprintf(stderr, "AssertMacros: %s, %s file: %s, line: %ld\n", assertionString ? assertionString : "",
                errorString ? errorString : "", fileName ? fileName : "", lineNumber);
}

/* ---- CoreFoundation ----------------------------------------------------------------- */

/* Every allocator is the default one here (CoreFoundation.m). */
const CFAllocatorRef kCFAllocatorMalloc = NULL;
const CFAllocatorRef kCFAllocatorMallocZone = NULL;

/* "1.2.3" as a NumVersion: major in BCD, then minor and bug-fix in a
 * nibble each, then the stage (final, 0x80) and the build. */
UInt32 CFBundleGetVersionNumber(CFBundleRef bundle)
{
    NSString *v = [(NSBundle *)bundle objectForInfoDictionaryKey:@"CFBundleVersion"];
    if (![v isKindOfClass:[NSString class]])
        return 0;
    int major = 0, minor = 0, bug = 0;
    if (sscanf([v UTF8String], "%d.%d.%d", &major, &minor, &bug) < 1)
        return 0;
    major %= 100;
    UInt32 bcd = (UInt32)((major / 10) << 4 | (major % 10));
    return bcd << 24 | (UInt32)(minor & 15) << 20 | (UInt32)(bug & 15) << 16 | 0x80u << 8;
}

/* two type identifiers that wxWidgets' clipboard names */
const CFStringRef kUTTypePICT = (CFStringRef)@"com.apple.pict";
const CFStringRef kUTTypeUTF16ExternalPlainText = (CFStringRef)@"public.utf16-external-plain-text";

/* ---- the Memory Manager's handles ---------------------------------------------------- */

/* A handle points at a master pointer that points at the block; Ferry keeps
 * the master pointer and the size together. */
struct ferry_handle {
    char *block;
    size_t size;
};

static OSErr last_mem_error;
OSErr MemError(void) { return last_mem_error; }

Handle NewHandle(long size)
{
    struct ferry_handle *h = calloc(1, sizeof *h);
    if (!h || size < 0 || !(h->block = calloc(1, size ? (size_t)size : 1))) {
        free(h);
        last_mem_error = -108; /* memFullErr */
        return NULL;
    }
    h->size = (size_t)size;
    last_mem_error = noErr;
    return (Handle)&h->block;
}

Handle NewHandleClear(long size) { return NewHandle(size); }

void DisposeHandle(Handle h)
{
    if (!h)
        return;
    struct ferry_handle *fh = (struct ferry_handle *)h;
    free(fh->block);
    free(fh);
    last_mem_error = noErr;
}

long GetHandleSize(Handle h)
{
    if (!h) {
        last_mem_error = -109; /* nilHandleErr */
        return 0;
    }
    last_mem_error = noErr;
    return (long)((struct ferry_handle *)h)->size;
}

void SetHandleSize(Handle h, long size)
{
    if (!h || size < 0) {
        last_mem_error = h ? -50 : -109;
        return;
    }
    struct ferry_handle *fh = (struct ferry_handle *)h;
    char *p = realloc(fh->block, size ? (size_t)size : 1);
    if (!p) {
        last_mem_error = -108;
        return;
    }
    if ((size_t)size > fh->size)
        memset(p + fh->size, 0, (size_t)size - fh->size);
    fh->block = p;
    fh->size = (size_t)size;
    last_mem_error = noErr;
}

OSErr PtrToHand(const void *src, Handle *out, long size)
{
    if (!out)
        return paramErr;
    Handle h = NewHandle(size);
    if (!h)
        return -108;
    if (size)
        memcpy(*h, src, (size_t)size);
    *out = h;
    return noErr;
}

OSErr HandToHand(Handle *h)
{
    if (!h || !*h)
        return -109;
    Handle copy;
    OSErr e = PtrToHand(**h, &copy, GetHandleSize(*h));
    if (e == noErr)
        *h = copy;
    return e;
}

void HLock(Handle h) {}
void HUnlock(Handle h) {}
void HLockHi(Handle h) {}

/* ---- more of the File Manager and Launch Services ------------------------------------ */

/* No volume reference numbers here: asked about one, the volume isn't found. */
OSErr FSGetVolumeInfo(FSVolumeRefNum volume, long volumeIndex, FSVolumeRefNum *actualVolume, UInt32 whichInfo,
                      void *info, void *volumeName, FSRef *rootDirectory)
{
    return nsvErr;
}

/* An alias file here is a symbolic link, which the reference follows. */
OSErr FSResolveAliasFile(FSRef *ref, Boolean resolveChains, Boolean *targetIsFolder, Boolean *wasAliased)
{
    UInt8 path[PATH_MAX];
    OSStatus e = FSRefMakePath(ref, path, sizeof path);
    if (e != noErr)
        return (OSErr)e;
    char resolved[PATH_MAX];
    Boolean aliased = false;
    struct stat st;
    if (lstat((const char *)path, &st) == 0 && S_ISLNK(st.st_mode) && realpath((const char *)path, resolved)) {
        aliased = true;
        e = FSPathMakeRef((const UInt8 *)resolved, ref, targetIsFolder);
        if (e != noErr)
            return (OSErr)e;
    } else if (targetIsFolder) {
        *targetIsFolder = stat((const char *)path, &st) == 0 && S_ISDIR(st.st_mode);
    }
    if (wasAliased)
        *wasAliased = aliased;
    return noErr;
}


/* Finding an app by creator, bundle id or name: none is registered with
 * Launch Services here. */
OSStatus LSGetApplicationForInfo(OSType inType, OSType inCreator, CFStringRef inExtension, UInt32 inRoleMask,
                                 FSRef *outAppRef, CFURLRef *outAppURL)
{
    if (outAppURL)
        *outAppURL = NULL;
    return kLSApplicationNotFoundErr;
}

/* Where the extension of a name begins (its index), or kLSInvalidExtensionIndex. */
OSStatus LSGetExtensionInfo(UniCharCount nameLen, const UniChar *name, UniCharCount *outExtStartIndex)
{
    if (!name || !outExtStartIndex)
        return paramErr;
    *outExtStartIndex = (UniCharCount)-1;
    for (UniCharCount i = nameLen; i > 1; i--)
        if (name[i - 1] == '.') {
            if (i < nameLen)
                *outExtStartIndex = i;
            break;
        }
    return noErr;
}

/* ---- more of CoreFoundation ----------------------------------------------------------- */

CFTypeID CFNullGetTypeID(void) { return (CFTypeID)(uintptr_t)[NSNull class]; }

/* CFGregorianUnits: years, months and days as 32-bit numbers, then hours,
 * minutes (32-bit) and seconds (a double), as documented */
typedef struct {
    SInt32 years, months, days, hours, minutes;
    double seconds;
} FerryGregorianUnits;

CFAbsoluteTime CFAbsoluteTimeAddGregorianUnits(CFAbsoluteTime at, CFTimeZoneRef tz, FerryGregorianUnits units)
{
    NSCalendar *cal = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
    if (tz)
        cal.timeZone = (NSTimeZone *)tz;
    NSDateComponents *c = [[NSDateComponents alloc] init];
    c.year = units.years;
    c.month = units.months;
    c.day = units.days;
    c.hour = units.hours;
    c.minute = units.minutes;
    NSDate *d = [cal dateByAddingComponents:c toDate:[NSDate dateWithTimeIntervalSinceReferenceDate:at] options:0];
    CFAbsoluteTime r = (d ? [d timeIntervalSinceReferenceDate] : at) + units.seconds;
    [c release];
    [cal release];
    return r;
}

CFStringRef CFLocaleCreateCanonicalLanguageIdentifierFromString(CFAllocatorRef allocator, CFStringRef string)
{
    if (!string)
        return NULL;
    NSString *s = [(NSString *)string stringByReplacingOccurrencesOfString:@"_" withString:@"-"];
    NSArray *parts = [s componentsSeparatedByString:@"-"];
    NSMutableArray *out = [NSMutableArray array];
    for (NSUInteger i = 0; i < parts.count; i++) {
        NSString *p = parts[i];
        if (!p.length)
            continue;
        if (i == 0)
            [out addObject:p.lowercaseString];
        else if (p.length == 2)
            [out addObject:p.uppercaseString];
        else if (p.length == 4)
            [out addObject:[p.capitalizedString copy]];
        else
            [out addObject:p];
    }
    return (CFStringRef)[[out componentsJoinedByString:@"-"] copy];
}

/* the URL's text in the given encoding (with its base's, when asked) */
CFDataRef CFURLCreateData(CFAllocatorRef allocator, CFURLRef url, CFStringEncoding encoding, Boolean escapeWhitespace)
{
    if (!url)
        return NULL;
    NSString *s = [(NSURL *)url relativeString];
    NSStringEncoding enc = CFStringConvertEncodingToNSStringEncoding(encoding);
    NSData *d = [s dataUsingEncoding:enc ? enc : NSUTF8StringEncoding allowLossyConversion:YES];
    return (CFDataRef)[d copy];
}

/* a file URL's contents (the old, deprecated call): properties aren't read */
Boolean CFURLCreateDataAndPropertiesFromResource(CFAllocatorRef alloc, CFURLRef url, CFDataRef *resourceData,
                                                 CFDictionaryRef *properties, CFArrayRef desiredProperties,
                                                 SInt32 *errorCode)
{
    if (properties)
        *properties = NULL;
    NSData *d = url ? [NSData dataWithContentsOfURL:(NSURL *)url] : nil;
    if (errorCode)
        *errorCode = d ? 0 : -10; /* kCFURLResourceNotFoundError */
    if (resourceData)
        *resourceData = d ? (CFDataRef)[d copy] : NULL;
    return d != nil;
}

/* The bundle's localizations that suit the user's preferred languages. */
CFArrayRef CFBundleCopyLocalizationsForPreferences(CFArrayRef locArray, CFArrayRef prefArray)
{
    NSArray *have = (NSArray *)locArray;
    if (!have.count)
        return (CFArrayRef)[[NSArray array] retain];
    NSArray *want = prefArray ? (NSArray *)prefArray : [NSLocale preferredLanguages];
    return (CFArrayRef)[[NSBundle preferredLocalizationsFromArray:have forPreferences:want] retain];
}

/* the architectures of a bundle's program: Ferry runs Intel ones */
CFArrayRef CFBundleCopyExecutableArchitecturesForURL(CFURLRef url)
{
    return (CFArrayRef)[@[ @0x01000007 ] retain]; /* kCFBundleExecutableArchitectureX86_64 */
}

/* Resource Manager forks don't exist here. */
SInt32 CFBundleOpenBundleResourceMap(CFBundleRef bundle) { return -1; }
void CFBundleCloseBundleResourceMap(CFBundleRef bundle, SInt32 refNum) {}

/* An alert the program shows without AppKit: written to the log, and
 * answered as if its default button were pressed (CFUserNotification has
 * no window of its own here). */
SInt32 CFUserNotificationDisplayAlert(CFTimeInterval timeout, CFOptionFlags flags, CFURLRef iconURL,
                                      CFURLRef soundURL, CFURLRef localizationURL, CFStringRef alertHeader,
                                      CFStringRef alertMessage, CFStringRef defaultButtonTitle,
                                      CFStringRef alternateButtonTitle, CFStringRef otherButtonTitle,
                                      CFOptionFlags *responseFlags)
{
    NSLog(@"%@: %@", alertHeader ? (NSString *)alertHeader : @"", alertMessage ? (NSString *)alertMessage : @"");
    if (responseFlags)
        *responseFlags = 0; /* kCFUserNotificationDefaultResponse */
    return 0;
}
