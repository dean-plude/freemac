/* SPDX-License-Identifier: GPL-3.0-or-later
 * More of the file calls (freemac 1.219, Ferry 0.43.0): directory
 * enumerators, display names, setting attributes, the trash, NSURL's
 * resource values, NSData's and NSBundle's URL calls, and NSFileCoordinator
 * with its file presenters. Written for freemac from Apple's public
 * documentation of NSFileManager, NSDirectoryEnumerator, NSURL, NSBundle,
 * NSFileCoordinator and NSFilePresenter.
 *
 * A directory enumerator lists each directory's entries in name order (a
 * Mac gives the file system's order, which no app can count on). The trash
 * is the freedesktop.org one in ~/.local/share/Trash, which this system's
 * file managers show. A file coordinator runs its accessor at once, on the
 * calling thread: only the presenters of this program are told of a change,
 * since nothing else here coordinates. */
#import "FInternal.h"
#include <sys/mount.h>
#include <sys/stat.h>
#include <unistd.h>
#include <pwd.h>

#include <sys/time.h>

NSString *const NSFileCreationDate = @"NSFileCreationDate";
NSString *const NSFileOwnerAccountID = @"NSFileOwnerAccountID";
NSString *const NSFileGroupOwnerAccountID = @"NSFileGroupOwnerAccountID";
NSString *const NSFileOwnerAccountName = @"NSFileOwnerAccountName";
NSString *const NSFileReferenceCount = @"NSFileReferenceCount";
NSString *const NSFileSystemNumber = @"NSFileSystemNumber";
NSString *const NSFileSystemFileNumber = @"NSFileSystemFileNumber";
NSString *const NSFileExtensionHidden = @"NSFileExtensionHidden";
NSString *const NSFileImmutable = @"NSFileImmutable";
NSString *const NSFileAppendOnly = @"NSFileAppendOnly";
NSString *const NSFileBusy = @"NSFileBusy";
NSString *const NSFileTypeCharacterSpecial = @"NSFileTypeCharacterSpecial";
NSString *const NSFileTypeBlockSpecial = @"NSFileTypeBlockSpecial";
NSString *const NSFileTypeSocket = @"NSFileTypeSocket";
NSString *const NSFileTypeUnknown = @"NSFileTypeUnknown";

NSString *const NSURLNameKey = @"NSURLNameKey";
NSString *const NSURLLocalizedNameKey = @"NSURLLocalizedNameKey";
NSString *const NSURLPathKey = @"_NSURLPathKey";
NSString *const NSURLIsRegularFileKey = @"NSURLIsRegularFileKey";
NSString *const NSURLIsDirectoryKey = @"NSURLIsDirectoryKey";
NSString *const NSURLIsSymbolicLinkKey = @"NSURLIsSymbolicLinkKey";
NSString *const NSURLIsVolumeKey = @"NSURLIsVolumeKey";
NSString *const NSURLIsPackageKey = @"NSURLIsPackageKey";
NSString *const NSURLIsHiddenKey = @"NSURLIsHiddenKey";
NSString *const NSURLIsAliasFileKey = @"NSURLIsAliasFileKey";
NSString *const NSURLIsReadableKey = @"NSURLIsReadableKey";
NSString *const NSURLIsWritableKey = @"NSURLIsWritableKey";
NSString *const NSURLIsExecutableKey = @"NSURLIsExecutableKey";
NSString *const NSURLHasHiddenExtensionKey = @"NSURLHasHiddenExtensionKey";
NSString *const NSURLFileSizeKey = @"NSURLFileSizeKey";
NSString *const NSURLFileAllocatedSizeKey = @"NSURLFileAllocatedSizeKey";
NSString *const NSURLTotalFileSizeKey = @"NSURLTotalFileSizeKey";
NSString *const NSURLTotalFileAllocatedSizeKey = @"NSURLTotalFileAllocatedSizeKey";
NSString *const NSURLCreationDateKey = @"NSURLCreationDateKey";
NSString *const NSURLContentModificationDateKey = @"NSURLContentModificationDateKey";
NSString *const NSURLContentAccessDateKey = @"NSURLContentAccessDateKey";
NSString *const NSURLAttributeModificationDateKey = @"NSURLAttributeModificationDateKey";
NSString *const NSURLParentDirectoryURLKey = @"NSURLParentDirectoryURLKey";
NSString *const NSURLTypeIdentifierKey = @"NSURLTypeIdentifierKey";
NSString *const NSURLLocalizedTypeDescriptionKey = @"NSURLLocalizedTypeDescriptionKey";
NSString *const NSURLLinkCountKey = @"NSURLLinkCountKey";
NSString *const NSURLFileResourceIdentifierKey = @"NSURLFileResourceIdentifierKey";
NSString *const NSURLVolumeIdentifierKey = @"NSURLVolumeIdentifierKey";
NSString *const NSURLVolumeIsLocalKey = @"NSURLVolumeIsLocalKey";
NSString *const NSURLVolumeURLKey = @"NSURLVolumeURLKey";
NSString *const NSURLVolumeSupportsCaseSensitiveNamesKey = @"NSURLVolumeSupportsCaseSensitiveNamesKey";
NSString *const NSURLIsSystemImmutableKey = @"NSURLIsSystemImmutableKey";
NSString *const NSURLIsUserImmutableKey = @"NSURLIsUserImmutableKey";
NSString *const NSURLVolumeTotalCapacityKey = @"NSURLVolumeTotalCapacityKey";
NSString *const NSURLVolumeAvailableCapacityKey = @"NSURLVolumeAvailableCapacityKey";
NSString *const NSURLVolumeAvailableCapacityForImportantUsageKey = @"NSURLVolumeAvailableCapacityForImportantUsageKey";
NSString *const NSURLVolumeAvailableCapacityForOpportunisticUsageKey =
    @"NSURLVolumeAvailableCapacityForOpportunisticUsageKey";
NSString *const NSURLVolumeNameKey = @"NSURLVolumeNameKey";
NSString *const NSURLVolumeLocalizedNameKey = @"NSURLVolumeLocalizedNameKey";
NSString *const NSURLVolumeIsReadOnlyKey = @"NSURLVolumeIsReadOnlyKey";
NSString *const NSURLVolumeIsRemovableKey = @"NSURLVolumeIsRemovableKey";
NSString *const NSURLFileResourceTypeKey = @"NSURLFileResourceTypeKey";
NSString *const NSURLFileResourceTypeNamedPipe = @"NSURLFileResourceTypeNamedPipe";
NSString *const NSURLFileResourceTypeCharacterSpecial = @"NSURLFileResourceTypeCharacterSpecial";
NSString *const NSURLFileResourceTypeDirectory = @"NSURLFileResourceTypeDirectory";
NSString *const NSURLFileResourceTypeBlockSpecial = @"NSURLFileResourceTypeBlockSpecial";
NSString *const NSURLFileResourceTypeRegular = @"NSURLFileResourceTypeRegular";
NSString *const NSURLFileResourceTypeSymbolicLink = @"NSURLFileResourceTypeSymbolicLink";
NSString *const NSURLFileResourceTypeSocket = @"NSURLFileResourceTypeSocket";
NSString *const NSURLFileResourceTypeUnknown = @"NSURLFileResourceTypeUnknown";

static NSDate *date_of(struct timespec t) { return [NSDate dateWithTimeIntervalSince1970:t.tv_sec + t.tv_nsec / 1e9]; }

static BOOL is_package(NSString *path, const struct stat *st)
{
    if (!S_ISDIR(st->st_mode))
        return NO;
    static NSArray *exts;
    if (!exts)
        exts = [[NSArray alloc] initWithObjects:@"app", @"bundle", @"framework", @"plugin", @"kext", @"rtfd", @"pkg",
                                                @"xcodeproj", @"wdgt", @"qlgenerator", @"prefPane", @"mdimporter", nil];
    return [exts containsObject:[path pathExtension]];
}

static NSError *cocoa_error(NSInteger code, NSString *path, int posix)
{
    NSMutableDictionary *info = [NSMutableDictionary dictionary];
    if (path) {
        [info setObject:path forKey:NSFilePathErrorKey];
        [info setObject:[NSURL fileURLWithPath:path] forKey:NSURLErrorKey];
    }
    if (posix)
        [info setObject:[NSError errorWithDomain:NSPOSIXErrorDomain code:posix userInfo:nil] forKey:NSUnderlyingErrorKey];
    return [NSError errorWithDomain:NSCocoaErrorDomain code:code userInfo:info];
}

/* ---- directory enumerators ----------------------------------------------------------------- */

@interface FDirectoryLevel : NSObject {
@public
    NSString *path, *relative;
    NSArray *names;
    NSUInteger next;
}
@end
@implementation FDirectoryLevel
- (void)dealloc
{
    [path release];
    [relative release];
    [names release];
    [super dealloc];
}
@end

@implementation NSDirectoryEnumerator {
    NSMutableArray *_stack;
    BOOL _urls, _skipNext;
    NSDirectoryEnumerationOptions _options;
    BOOL (^_errorHandler)(NSURL *, NSError *);
    NSDictionary *_attributes;
    NSString *_lastPath, *_lastFull;
    NSURL *_root;
}
- (instancetype)_initWithPath:(NSString *)path URLs:(BOOL)urls options:(NSDirectoryEnumerationOptions)options
                 errorHandler:(BOOL (^)(NSURL *, NSError *))handler
{
    if ((self = [super init])) {
        _stack = [[NSMutableArray alloc] init];
        _urls = urls;
        _options = options;
        _errorHandler = [handler copy];
        _root = [[NSURL fileURLWithPath:path isDirectory:YES] retain];
        if (![self _push:path relative:@""]) {
            [self release];
            return nil;
        }
    }
    return self;
}
- (void)dealloc
{
    [_stack release];
    [_errorHandler release];
    [_attributes release];
    [_lastPath release];
    [_lastFull release];
    [_root release];
    [super dealloc];
}
- (BOOL)_push:(NSString *)path relative:(NSString *)rel
{
    NSError *err = nil;
    NSArray *names = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:path error:&err];
    if (!names) {
        if (_errorHandler && !_errorHandler([NSURL fileURLWithPath:path], err))
            [_stack removeAllObjects];
        return NO;
    }
    FDirectoryLevel *l = [[FDirectoryLevel alloc] init];
    l->path = [path copy];
    l->relative = [rel copy];
    l->names = [[names sortedArrayUsingSelector:@selector(compare:)] retain];
    [_stack addObject:l];
    [l release];
    return YES;
}
- (id)nextObject
{
    /* go into the last directory given, unless told to skip it */
    if (_lastFull && !_skipNext && !(_options & NSDirectoryEnumerationSkipsSubdirectoryDescendants)) {
        struct stat st;
        if (lstat([_lastFull fileSystemRepresentation], &st) == 0 && S_ISDIR(st.st_mode) &&
            !((_options & NSDirectoryEnumerationSkipsPackageDescendants) && is_package(_lastFull, &st)))
            [self _push:_lastFull relative:_lastPath];
    }
    [_lastFull release];
    _lastFull = nil;
    _skipNext = NO;
    [_lastPath release];
    _lastPath = nil;
    [_attributes release];
    _attributes = nil;
    while ([_stack count]) {
        FDirectoryLevel *l = [_stack lastObject];
        if (l->next >= [l->names count]) {
            [_stack removeLastObject];
            continue;
        }
        NSString *name = [l->names objectAtIndex:l->next++];
        if ((_options & NSDirectoryEnumerationSkipsHiddenFiles) && [name hasPrefix:@"."])
            continue;
        NSString *rel = [l->relative length] ? [l->relative stringByAppendingPathComponent:name] : name;
        NSString *full = [l->path stringByAppendingPathComponent:name];
        _lastPath = [rel copy];
        _lastFull = [full copy];
        if (_urls) {
            BOOL dir = NO;
            [[NSFileManager defaultManager] fileExistsAtPath:full isDirectory:&dir];
            return [NSURL fileURLWithPath:full isDirectory:dir];
        }
        return rel;
    }
    return nil;
}
- (NSDictionary *)fileAttributes
{
    if (!_lastPath || ![_stack count])
        return nil;
    if (!_attributes) {
        NSString *full = [[_root path] stringByAppendingPathComponent:_lastPath];
        _attributes = [[[NSFileManager defaultManager] attributesOfItemAtPath:full error:NULL] retain];
    }
    return _attributes;
}
- (NSDictionary *)directoryAttributes
{
    return [[NSFileManager defaultManager] attributesOfItemAtPath:[_root path] error:NULL];
}
/* One at a time, so that -level, -fileAttributes and -skipDescendants in the
 * body of a for-in loop are about the item it was given. */
- (NSUInteger)countByEnumeratingWithState:(NSFastEnumerationState *)state objects:(id __unsafe_unretained[])buffer
                                    count:(NSUInteger)len
{
    state->mutationsPtr = &state->extra[0];
    state->itemsPtr = buffer;
    id o = len ? [self nextObject] : nil;
    if (!o)
        return 0;
    buffer[0] = o;
    return 1;
}
- (void)skipDescendents { _skipNext = YES; }
- (void)skipDescendants { _skipNext = YES; }
- (NSUInteger)level { return _lastPath ? [[_lastPath pathComponents] count] : 0; }
- (BOOL)isEnumeratingDirectoryPostOrder { return NO; }
@end

/* ---- the file manager ---------------------------------------------------------------------- */

NSString *const NSUbiquityIdentityDidChangeNotification = @"NSUbiquityIdentityDidChangeNotification";

@implementation NSFileManager (FerryFileAccess)
- (id<NSObject, NSCopying, NSCoding>)ubiquityIdentityToken { return nil; }
- (NSURL *)URLForUbiquityContainerIdentifier:(NSString *)containerIdentifier { return nil; }
- (BOOL)isUbiquitousItemAtURL:(NSURL *)url { return NO; }

/* The mounted volumes, the system disk first, as a Finder sidebar or a
 * program's own volume list shows them (freemac Godot work). Skipping the
 * hidden ones leaves the system disk and what is mounted where disks and
 * shares show up (/media, /run/media, /mnt), as a Mac leaves out its own
 * system volumes. The resource values are read when asked for. */
- (NSArray<NSURL *> *)mountedVolumeURLsIncludingResourceValuesForKeys:(NSArray *)propertyKeys
                                                              options:(NSVolumeEnumerationOptions)options
{
    int n = getfsstat(NULL, 0, MNT_NOWAIT);
    if (n <= 0)
        return [NSArray arrayWithObject:[NSURL fileURLWithPath:@"/" isDirectory:YES]];
    struct statfs *all = calloc((size_t)n + 8, sizeof *all);
    if (!all)
        return nil;
    n = getfsstat(all, (int)(((size_t)n + 8) * sizeof *all), MNT_NOWAIT);
    NSMutableArray *out = [NSMutableArray arrayWithObject:[NSURL fileURLWithPath:@"/" isDirectory:YES]];
    for (int i = 0; i < n; i++) {
        NSString *point = [NSString stringWithUTF8String:all[i].f_mntonname];
        if (![point length] || [point isEqualToString:@"/"])
            continue;
        if ((options & NSVolumeEnumerationSkipHiddenVolumes) &&
            ((all[i].f_flags & MNT_DONTBROWSE) ||
             !([point hasPrefix:@"/media/"] || [point hasPrefix:@"/run/media/"] || [point hasPrefix:@"/mnt/"])))
            continue;
        [out addObject:[NSURL fileURLWithPath:point isDirectory:YES]];
    }
    free(all);
    return out;
}
- (NSDirectoryEnumerator *)enumeratorAtPath:(NSString *)path
{
    return [[[NSDirectoryEnumerator alloc] _initWithPath:path URLs:NO options:0 errorHandler:nil] autorelease];
}
- (NSDirectoryEnumerator *)enumeratorAtURL:(NSURL *)url includingPropertiesForKeys:(NSArray *)keys
                                   options:(NSDirectoryEnumerationOptions)mask
                              errorHandler:(BOOL (^)(NSURL *url, NSError *error))handler
{
    return [[[NSDirectoryEnumerator alloc] _initWithPath:[url path] URLs:YES options:mask
                                            errorHandler:handler] autorelease];
}
/* The name Finder shows: the last component, without the extension of an
 * application. */
- (NSString *)displayNameAtPath:(NSString *)path
{
    NSString *name = [path lastPathComponent];
    if ([path isEqualToString:@"/"])
        return @"/";
    if ([[[path pathExtension] lowercaseString] isEqualToString:@"app"])
        return [name stringByDeletingPathExtension];
    return name;
}
- (NSArray *)componentsToDisplayForPath:(NSString *)path
{
    if (![self fileExistsAtPath:path])
        return nil;
    NSMutableArray *out = [NSMutableArray array];
    NSString *p = [path stringByStandardizingPath];
    while ([p length] && ![p isEqualToString:@"/"]) {
        [out insertObject:[self displayNameAtPath:p] atIndex:0];
        p = [p stringByDeletingLastPathComponent];
    }
    return out;
}
/* Permissions, the modification date and the owner account IDs; the other
 * attributes (creation date, hidden extension, immutable) are accepted and
 * left as the file system keeps them. */
- (BOOL)setAttributes:(NSDictionary *)attributes ofItemAtPath:(NSString *)path error:(NSError **)error
{
    const char *p = [path fileSystemRepresentation];
    NSNumber *perm = [attributes objectForKey:NSFilePosixPermissions];
    if (perm && chmod(p, (mode_t)[perm unsignedShortValue]) != 0) {
        FSetError(error, FPosixError(errno, path));
        return NO;
    }
    NSNumber *uid = [attributes objectForKey:NSFileOwnerAccountID], *gid = [attributes objectForKey:NSFileGroupOwnerAccountID];
    if ((uid || gid) && chown(p, uid ? (uid_t)[uid unsignedIntValue] : (uid_t)-1, gid ? (gid_t)[gid unsignedIntValue] : (gid_t)-1) != 0) {
        FSetError(error, FPosixError(errno, path));
        return NO;
    }
    NSDate *mod = [attributes objectForKey:NSFileModificationDate];
    if (mod) {
        struct stat st;
        if (stat(p, &st) != 0) {
            FSetError(error, FPosixError(errno, path));
            return NO;
        }
        NSTimeInterval t = [mod timeIntervalSince1970];
        struct timeval times[2] = {{st.st_atimespec.tv_sec, (suseconds_t)(st.st_atimespec.tv_nsec / 1000)},
                                   {(time_t)floor(t), (suseconds_t)((t - floor(t)) * 1e6)}};
        if (utimes(p, times) != 0) {
            FSetError(error, FPosixError(errno, path));
            return NO;
        }
    }
    return YES;
}
- (BOOL)linkItemAtPath:(NSString *)src toPath:(NSString *)dst error:(NSError **)error
{
    if (link([src fileSystemRepresentation], [dst fileSystemRepresentation]) != 0) {
        FSetError(error, FPosixError(errno, dst));
        return NO;
    }
    return YES;
}
- (BOOL)createSymbolicLinkAtURL:(NSURL *)url withDestinationURL:(NSURL *)dest error:(NSError **)error
{
    return [self createSymbolicLinkAtPath:[url path] withDestinationPath:[dest path] error:error];
}
/* Into the freedesktop.org trash: the file goes to Trash/files, and a
 * .trashinfo note of where it was and when to Trash/info. */
- (BOOL)trashItemAtURL:(NSURL *)url resultingItemURL:(NSURL **)outURL error:(NSError **)error
{
    NSString *path = [[url path] stringByStandardizingPath];
    struct stat st;
    if (lstat([path fileSystemRepresentation], &st) != 0) {
        FSetError(error, cocoa_error(NSFileNoSuchFileError, path, errno));
        return NO;
    }
    NSString *data = [[[NSProcessInfo processInfo] environment] objectForKey:@"XDG_DATA_HOME"];
    if (![data length])
        data = [NSHomeDirectory() stringByAppendingPathComponent:@".local/share"];
    NSString *trash = [data stringByAppendingPathComponent:@"Trash"];
    NSString *files = [trash stringByAppendingPathComponent:@"files"], *info = [trash stringByAppendingPathComponent:@"info"];
    if (![self createDirectoryAtPath:files withIntermediateDirectories:YES attributes:nil error:error] ||
        ![self createDirectoryAtPath:info withIntermediateDirectories:YES attributes:nil error:error])
        return NO;
    NSString *name = [path lastPathComponent], *base = [name stringByDeletingPathExtension], *ext = [name pathExtension];
    NSString *target = [files stringByAppendingPathComponent:name];
    for (int i = 2; [self fileExistsAtPath:target] ||
                    [self fileExistsAtPath:[[info stringByAppendingPathComponent:[target lastPathComponent]]
                                               stringByAppendingPathExtension:@"trashinfo"]];
         i++) {
        NSString *n = [NSString stringWithFormat:@"%@ %d", base, i];
        if ([ext length])
            n = [n stringByAppendingPathExtension:ext];
        target = [files stringByAppendingPathComponent:n];
    }
    time_t now = time(NULL);
    struct tm tm;
    localtime_r(&now, &tm);
    char when[32];
    strftime(when, sizeof when, "%Y-%m-%dT%H:%M:%S", &tm);
    NSString *escaped = [path stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLPathAllowedCharacterSet]];
    NSString *note = [NSString stringWithFormat:@"[Trash Info]\nPath=%@\nDeletionDate=%s\n", escaped, when];
    NSString *notePath = [[info stringByAppendingPathComponent:[target lastPathComponent]]
        stringByAppendingPathExtension:@"trashinfo"];
    if (![note writeToFile:notePath atomically:NO encoding:NSUTF8StringEncoding error:error])
        return NO;
    if (rename([path fileSystemRepresentation], [target fileSystemRepresentation]) != 0) {
        int e = errno;
        unlink([notePath fileSystemRepresentation]);
        if (e != EXDEV || ![self moveItemAtPath:path toPath:target error:error]) {
            if (e != EXDEV)
                FSetError(error, FPosixError(e, path));
            return NO;
        }
    }
    if (outURL)
        *outURL = [NSURL fileURLWithPath:target];
    return YES;
}
@end

/* The attributes of a file, the keys attributesOfItemAtPath:error: gives. */
NSDictionary *FFileAttributes(NSString *path, NSError **error)
{
    struct stat st;
    if (lstat([path fileSystemRepresentation], &st) != 0) {
        FSetError(error, FPosixError(errno, path));
        return nil;
    }
    NSString *type = S_ISDIR(st.st_mode)    ? NSFileTypeDirectory
                     : S_ISLNK(st.st_mode)  ? NSFileTypeSymbolicLink
                     : S_ISREG(st.st_mode)  ? NSFileTypeRegular
                     : S_ISCHR(st.st_mode)  ? NSFileTypeCharacterSpecial
                     : ((st.st_mode & S_IFMT) == S_IFBLK) ? NSFileTypeBlockSpecial
                     : ((st.st_mode & S_IFMT) == S_IFSOCK) ? NSFileTypeSocket
                                                          : NSFileTypeUnknown;
    struct timespec born = st.st_birthtimespec.tv_sec ? st.st_birthtimespec : st.st_ctimespec;
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    [d setObject:[NSNumber numberWithUnsignedLongLong:(unsigned long long)st.st_size] forKey:NSFileSize];
    [d setObject:type forKey:NSFileType];
    [d setObject:date_of(st.st_mtimespec) forKey:NSFileModificationDate];
    [d setObject:date_of(born) forKey:NSFileCreationDate];
    [d setObject:[NSNumber numberWithUnsignedShort:st.st_mode & 07777] forKey:NSFilePosixPermissions];
    [d setObject:[NSNumber numberWithUnsignedInt:st.st_uid] forKey:NSFileOwnerAccountID];
    [d setObject:[NSNumber numberWithUnsignedInt:st.st_gid] forKey:NSFileGroupOwnerAccountID];
    [d setObject:[NSNumber numberWithUnsignedLong:(unsigned long)st.st_nlink] forKey:NSFileReferenceCount];
    [d setObject:[NSNumber numberWithUnsignedLongLong:(unsigned long long)st.st_dev] forKey:NSFileSystemNumber];
    [d setObject:[NSNumber numberWithUnsignedLongLong:(unsigned long long)st.st_ino] forKey:NSFileSystemFileNumber];
    [d setObject:[NSNumber numberWithBool:NO] forKey:NSFileExtensionHidden];
    [d setObject:[NSNumber numberWithBool:NO] forKey:NSFileImmutable];
    [d setObject:[NSNumber numberWithBool:NO] forKey:NSFileAppendOnly];
    [d setObject:[NSNumber numberWithBool:NO] forKey:NSFileBusy];
    struct passwd *pw = getpwuid(st.st_uid);
    if (pw && pw->pw_name)
        [d setObject:[NSString stringWithUTF8String:pw->pw_name] forKey:NSFileOwnerAccountName];
    return d;
}

@implementation NSDictionary (FerryFileAttributes)
- (NSUInteger)filePosixPermissions { return [[self objectForKey:NSFilePosixPermissions] unsignedIntegerValue]; }
- (NSDate *)fileCreationDate { return [self objectForKey:NSFileCreationDate]; }
- (NSNumber *)fileOwnerAccountID { return [self objectForKey:NSFileOwnerAccountID]; }
- (NSNumber *)fileGroupOwnerAccountID { return [self objectForKey:NSFileGroupOwnerAccountID]; }
- (NSString *)fileOwnerAccountName { return [self objectForKey:NSFileOwnerAccountName]; }
- (NSUInteger)fileSystemNumber { return [[self objectForKey:NSFileSystemNumber] unsignedIntegerValue]; }
- (NSUInteger)fileSystemFileNumber { return [[self objectForKey:NSFileSystemFileNumber] unsignedIntegerValue]; }
- (BOOL)fileExtensionHidden { return [[self objectForKey:NSFileExtensionHidden] boolValue]; }
- (BOOL)fileIsImmutable { return [[self objectForKey:NSFileImmutable] boolValue]; }
- (BOOL)fileIsAppendOnly { return [[self objectForKey:NSFileAppendOnly] boolValue]; }
@end

/* ---- NSURL ----------------------------------------------------------------------------- */

@implementation NSURL (FerryFileAccess)
+ (NSURL *)fileURLWithPathComponents:(NSArray *)components
{
    if (![components count])
        return nil;
    return [NSURL fileURLWithPath:[NSString pathWithComponents:components]];
}
+ (NSURL *)fileURLWithFileSystemRepresentation:(const char *)path isDirectory:(BOOL)isDir relativeToURL:(NSURL *)base
{
    NSString *p = [NSString stringWithUTF8String:path];
    if (base && ![p isAbsolutePath])
        p = [[base path] stringByAppendingPathComponent:p];
    return [NSURL fileURLWithPath:p isDirectory:isDir];
}
- (instancetype)initFileURLWithFileSystemRepresentation:(const char *)path isDirectory:(BOOL)isDir
                                          relativeToURL:(NSURL *)base
{
    NSURL *url = [NSURL fileURLWithFileSystemRepresentation:path isDirectory:isDir relativeToURL:base];
    [self release];
    return [url retain];
}
- (BOOL)getFileSystemRepresentation:(char *)buffer maxLength:(NSUInteger)maxLength
{
    return [self isFileURL] && [[self path] getFileSystemRepresentation:buffer maxLength:maxLength];
}
- (BOOL)isFileReferenceURL { return NO; }
- (NSURL *)fileReferenceURL { return [self isFileURL] ? self : nil; }
- (NSURL *)filePathURL { return [self isFileURL] ? self : nil; }
- (BOOL)checkResourceIsReachableAndReturnError:(NSError **)error
{
    if (![self isFileURL]) {
        FSetError(error, [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadUnsupportedSchemeError
                                         userInfo:[NSDictionary dictionaryWithObject:self forKey:NSURLErrorKey]]);
        return NO;
    }
    struct stat st;
    if (stat([[self path] fileSystemRepresentation], &st) != 0) {
        FSetError(error, cocoa_error(NSFileReadNoSuchFileError, [self path], errno));
        return NO;
    }
    return YES;
}
/* A Mac caches a URL's resource values and these clear the cache; Ferry
 * reads them fresh each time, so there is nothing to clear (freemac 1.264,
 * HandBrake before it encodes). */
- (void)removeCachedResourceValueForKey:(NSURLResourceKey)key {}
- (void)removeAllCachedResourceValues {}
- (void)setTemporaryResourceValue:(id)value forKey:(NSURLResourceKey)key {}
- (NSDictionary *)resourceValuesForKeys:(NSArray *)keys error:(NSError **)error
{
    NSMutableDictionary *out = [NSMutableDictionary dictionary];
    for (NSString *k in keys) {
        id v = nil;
        if (![self getResourceValue:&v forKey:k error:error])
            return nil;
        if (v)
            [out setObject:v forKey:k];
    }
    return out;
}
/* A value the file has, or nil (with YES) for a key it has none for, as
 * on a Mac. */
- (BOOL)getResourceValue:(id *)value forKey:(NSString *)key error:(NSError **)error
{
    *value = nil;
    if (![self isFileURL]) {
        FSetError(error, [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadUnsupportedSchemeError
                                         userInfo:[NSDictionary dictionaryWithObject:self forKey:NSURLErrorKey]]);
        return NO;
    }
    NSString *path = [self path];
    if ([key isEqualToString:NSURLNameKey] || [key isEqualToString:NSURLLocalizedNameKey]) {
        *value = [key isEqualToString:NSURLNameKey] ? [path lastPathComponent]
                                                    : [[NSFileManager defaultManager] displayNameAtPath:path];
        return YES;
    }
    if ([key isEqualToString:NSURLPathKey]) {
        *value = path;
        return YES;
    }
    if ([key isEqualToString:NSURLParentDirectoryURLKey]) {
        *value = [NSURL fileURLWithPath:[path stringByDeletingLastPathComponent] isDirectory:YES];
        return YES;
    }
    struct stat st, target;
    if (lstat([path fileSystemRepresentation], &st) != 0) {
        FSetError(error, cocoa_error(NSFileReadNoSuchFileError, path, errno));
        return NO;
    }
    if (S_ISLNK(st.st_mode) && stat([path fileSystemRepresentation], &target) == 0)
        ; /* a link is described as a link, as lstat gives it */
    BOOL dir = S_ISDIR(st.st_mode);
    id v = nil;
#define IS(k) [key isEqualToString:(k)]
#define BOOLV(b) [NSNumber numberWithBool:(b)]
    if (IS(NSURLIsRegularFileKey))
        v = BOOLV(S_ISREG(st.st_mode));
    else if (IS(NSURLIsDirectoryKey))
        v = BOOLV(dir);
    else if (IS(NSURLIsSymbolicLinkKey))
        v = BOOLV(S_ISLNK(st.st_mode));
    else if (IS(NSURLIsVolumeKey))
        v = BOOLV([path isEqualToString:@"/"]);
    else if (IS(NSURLIsPackageKey))
        v = BOOLV(is_package(path, &st));
    else if (IS(NSURLIsHiddenKey))
        v = BOOLV([[path lastPathComponent] hasPrefix:@"."]);
    else if (IS(NSURLIsAliasFileKey))
        v = BOOLV(S_ISLNK(st.st_mode));
    else if (IS(NSURLHasHiddenExtensionKey))
        v = BOOLV(NO);
    else if (IS(NSURLIsReadableKey))
        v = BOOLV(access([path fileSystemRepresentation], R_OK) == 0);
    else if (IS(NSURLIsWritableKey))
        v = BOOLV(access([path fileSystemRepresentation], W_OK) == 0);
    else if (IS(NSURLIsExecutableKey))
        v = BOOLV(access([path fileSystemRepresentation], X_OK) == 0);
    else if (IS(NSURLFileSizeKey) || IS(NSURLTotalFileSizeKey))
        v = dir ? nil : [NSNumber numberWithUnsignedLongLong:(unsigned long long)st.st_size];
    else if (IS(NSURLFileAllocatedSizeKey) || IS(NSURLTotalFileAllocatedSizeKey))
        v = dir ? nil : [NSNumber numberWithUnsignedLongLong:(unsigned long long)st.st_blocks * 512];
    else if (IS(NSURLCreationDateKey))
        v = date_of(st.st_birthtimespec.tv_sec ? st.st_birthtimespec : st.st_ctimespec);
    else if (IS(NSURLContentModificationDateKey))
        v = date_of(st.st_mtimespec);
    else if (IS(NSURLContentAccessDateKey))
        v = date_of(st.st_atimespec);
    else if (IS(NSURLAttributeModificationDateKey))
        v = date_of(st.st_ctimespec);
    else if (IS(NSURLLinkCountKey))
        v = [NSNumber numberWithUnsignedLong:(unsigned long)st.st_nlink];
    else if (IS(NSURLVolumeIdentifierKey))
        v = [NSNumber numberWithUnsignedLongLong:(unsigned long long)st.st_dev];
    else if (IS(NSURLVolumeIsLocalKey)) {
        /* freemac 1.262: a volume is local unless it is a network share */
        struct statfs fs;
        if (statfs([path fileSystemRepresentation], &fs) == 0) {
            unsigned long t = (unsigned long)fs.f_type;
            BOOL remote = t == 0x6969 /* NFS */ || t == 0xFF534D42 /* CIFS */ || t == 0xFE534D42 /* SMB2 */ ||
                          t == 0x517B /* SMB */ || t == 0x65735546 /* FUSE */;
            v = [NSNumber numberWithBool:!remote];
        }
    }
    else if (IS(NSURLVolumeTotalCapacityKey) || IS(NSURLVolumeAvailableCapacityKey) ||
             IS(NSURLVolumeAvailableCapacityForImportantUsageKey) ||
             IS(NSURLVolumeAvailableCapacityForOpportunisticUsageKey)) {
        struct statfs fs;
        if (statfs([path fileSystemRepresentation], &fs) == 0) {
            unsigned long long block = fs.f_bsize ? fs.f_bsize : 512;
            unsigned long long n = IS(NSURLVolumeTotalCapacityKey) ? fs.f_blocks : fs.f_bavail;
            /* the important- and opportunistic-use figures are signed on a Mac */
            v = IS(NSURLVolumeTotalCapacityKey) || IS(NSURLVolumeAvailableCapacityKey)
                    ? [NSNumber numberWithUnsignedLongLong:n * block]
                    : [NSNumber numberWithLongLong:(long long)(n * block)];
        }
    }
    else if (IS(NSURLIsSystemImmutableKey) || IS(NSURLIsUserImmutableKey))
        /* freemac Godot work: this system's immutable flag (chattr +i) is
         * the system one; nothing here sets a user one */
        v = BOOLV(IS(NSURLIsSystemImmutableKey) && (st.st_flags & 0x00020000 /* SF_IMMUTABLE */));
    else if (IS(NSURLVolumeURLKey) || IS(NSURLVolumeNameKey) || IS(NSURLVolumeLocalizedNameKey) ||
             IS(NSURLVolumeIsReadOnlyKey) || IS(NSURLVolumeSupportsCaseSensitiveNamesKey) ||
             IS(NSURLVolumeIsRemovableKey)) {
        BOOL known;
        v = FVolumeResourceValue(path, key, &known);
    }
    else if (IS(NSURLFileResourceIdentifierKey))
        v = [NSString stringWithFormat:@"%llu:%llu", (unsigned long long)st.st_dev, (unsigned long long)st.st_ino];
    else if (IS(NSURLFileResourceTypeKey))
        v = dir                                  ? NSURLFileResourceTypeDirectory
            : S_ISREG(st.st_mode)                ? NSURLFileResourceTypeRegular
            : S_ISLNK(st.st_mode)                ? NSURLFileResourceTypeSymbolicLink
            : S_ISFIFO(st.st_mode)               ? NSURLFileResourceTypeNamedPipe
            : S_ISCHR(st.st_mode)                ? NSURLFileResourceTypeCharacterSpecial
            : (st.st_mode & S_IFMT) == S_IFBLK   ? NSURLFileResourceTypeBlockSpecial
            : (st.st_mode & S_IFMT) == S_IFSOCK  ? NSURLFileResourceTypeSocket
                                                 : NSURLFileResourceTypeUnknown;
    else if (IS(NSURLTypeIdentifierKey) || IS(NSURLLocalizedTypeDescriptionKey)) {
        /* AppKit's NSWorkspace knows the types, when the program has AppKit */
        Class ws = NSClassFromString(@"NSWorkspace");
        id shared = ws ? [ws performSelector:@selector(sharedWorkspace)] : nil;
        NSString *uti = shared ? [shared performSelector:@selector(typeOfFile:error:) withObject:path withObject:nil]
                               : dir ? (is_package(path, &st) ? @"com.apple.package" : @"public.folder")
                                     : @"public.data";
        if (IS(NSURLLocalizedTypeDescriptionKey))
            v = shared ? [shared performSelector:@selector(localizedDescriptionForType:) withObject:uti]
                       : dir ? @"Folder" : @"Document";
        else
            v = uti;
    }
#undef IS
#undef BOOLV
    *value = v;
    return YES;
}
/* Of the values that can be set, a date and the hidden flag of a name that
 * starts with a dot: the rest are accepted and kept by nothing. */
- (BOOL)setResourceValue:(id)value forKey:(NSString *)key error:(NSError **)error
{
    if ([key isEqualToString:NSURLContentModificationDateKey] && [value isKindOfClass:[NSDate class]])
        return [[NSFileManager defaultManager]
            setAttributes:[NSDictionary dictionaryWithObject:value forKey:NSFileModificationDate]
             ofItemAtPath:[self path]
                    error:error];
    return [self checkResourceIsReachableAndReturnError:error];
}
- (BOOL)setResourceValues:(NSDictionary *)values error:(NSError **)error
{
    for (NSString *k in values)
        if (![self setResourceValue:[values objectForKey:k] forKey:k error:error])
            return NO;
    return YES;
}
@end

/* Bookmarks (freemac 1.224): a property list holding the item's absolute
 * path, under a key of Ferry's own; resolving one finds whatever is at that
 * path now. */
static NSString *const bookmark_path_key = @"FerryBookmarkPath";
@implementation NSURL (FerryBookmarks)
- (NSData *)bookmarkDataWithOptions:(NSURLBookmarkCreationOptions)options
     includingResourceValuesForKeys:(NSArray *)keys
                      relativeToURL:(NSURL *)relativeURL
                              error:(NSError **)error
{
    if (![self isFileURL] || ![self checkResourceIsReachableAndReturnError:error]) {
        if (error && ![self isFileURL])
            *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadUnsupportedSchemeError userInfo:nil];
        return nil;
    }
    NSDictionary *plist = [NSDictionary dictionaryWithObject:[[self path] stringByStandardizingPath] forKey:bookmark_path_key];
    return [NSPropertyListSerialization dataWithPropertyList:plist format:NSPropertyListBinaryFormat_v1_0
                                                     options:0 error:error];
}
- (instancetype)initByResolvingBookmarkData:(NSData *)data options:(NSURLBookmarkResolutionOptions)options
                              relativeToURL:(NSURL *)relativeURL bookmarkDataIsStale:(BOOL *)isStale
                                      error:(NSError **)error
{
    [self release];
    id plist = data ? [NSPropertyListSerialization propertyListWithData:data options:0 format:NULL error:NULL] : nil;
    NSString *path = [plist isKindOfClass:[NSDictionary class]] ? [plist objectForKey:bookmark_path_key] : nil;
    if (![path isKindOfClass:[NSString class]]) {
        if (error)
            *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadCorruptFileError userInfo:nil];
        return nil;
    }
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        if (error)
            *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileNoSuchFileError
                                     userInfo:[NSDictionary dictionaryWithObject:path forKey:NSFilePathErrorKey]];
        return nil;
    }
    if (isStale)
        *isStale = NO;
    return [[NSURL fileURLWithPath:path] retain];
}
+ (instancetype)URLByResolvingBookmarkData:(NSData *)data options:(NSURLBookmarkResolutionOptions)options
                             relativeToURL:(NSURL *)relativeURL bookmarkDataIsStale:(BOOL *)isStale
                                     error:(NSError **)error
{
    return [[[NSURL alloc] initByResolvingBookmarkData:data options:options relativeToURL:relativeURL
                                   bookmarkDataIsStale:isStale error:error] autorelease];
}
/* there is no sandbox to step out of */
- (BOOL)startAccessingSecurityScopedResource { return YES; }
- (void)stopAccessingSecurityScopedResource {}
@end

@implementation NSData (FerryFileAccess)
- (BOOL)writeToURL:(NSURL *)url options:(NSDataWritingOptions)options error:(NSError **)error
{
    if (![url isFileURL]) {
        FSetError(error, [NSError errorWithDomain:NSCocoaErrorDomain code:518 /* NSFileWriteUnsupportedSchemeError */
                                         userInfo:[NSDictionary dictionaryWithObject:url forKey:NSURLErrorKey]]);
        return NO;
    }
    return [self writeToFile:[url path] options:options error:error];
}
@end

@implementation NSBundle (FerryFileAccess)
- (NSURL *)URLForResource:(NSString *)name withExtension:(NSString *)ext subdirectory:(NSString *)subpath
{
    NSString *p = [self pathForResource:name ofType:ext inDirectory:subpath];
    return p ? [NSURL fileURLWithPath:p] : nil;
}
- (NSArray *)URLsForResourcesWithExtension:(NSString *)ext subdirectory:(NSString *)subpath
{
    NSMutableArray *out = [NSMutableArray array];
    for (NSString *p in [self pathsForResourcesOfType:ext inDirectory:subpath])
        [out addObject:[NSURL fileURLWithPath:p]];
    return out;
}
+ (NSURL *)URLForResource:(NSString *)name withExtension:(NSString *)ext subdirectory:(NSString *)subpath
          inBundleWithURL:(NSURL *)bundleURL
{
    return [[NSBundle bundleWithURL:bundleURL] URLForResource:name withExtension:ext subdirectory:subpath];
}
+ (NSString *)pathForResource:(NSString *)name ofType:(NSString *)ext inDirectory:(NSString *)bundlePath
{
    return [[NSBundle bundleWithPath:bundlePath] pathForResource:name ofType:ext];
}
@end

/* ---- file coordination ----------------------------------------------------------------- */

static NSMutableArray *presenters(void)
{
    static NSMutableArray *list;
    if (!list)
        list = [[NSMutableArray alloc] init];
    return list;
}
static os_unfair_lock presenters_lock = OS_UNFAIR_LOCK_INIT;

/* The presenters of an item or of a folder holding it, other than skip. */
static NSArray *presenters_of(NSURL *url, id skip)
{
    NSString *path = [[[url URLByResolvingSymlinksInPath] path] stringByStandardizingPath];
    NSMutableArray *out = [NSMutableArray array];
    os_unfair_lock_lock(&presenters_lock);
    NSArray *all = [[presenters() copy] autorelease];
    os_unfair_lock_unlock(&presenters_lock);
    for (id p in all) {
        if (p == skip)
            continue;
        NSString *mine = [[[[p presentedItemURL] URLByResolvingSymlinksInPath] path] stringByStandardizingPath];
        if (mine && ([mine isEqualToString:path] || [path hasPrefix:[mine stringByAppendingString:@"/"]]))
            [out addObject:p];
    }
    return out;
}
static void on_queue(id presenter, void (^block)(void))
{
    NSOperationQueue *q = [presenter respondsToSelector:@selector(presentedItemOperationQueue)]
                              ? [presenter presentedItemOperationQueue]
                              : nil;
    if (q && q != [NSOperationQueue currentQueue])
        [q addOperationWithBlock:block];
    else
        block();
}

@implementation NSFileCoordinator {
    id _presenter;
    NSString *_purpose;
}
+ (void)addFilePresenter:(id<NSFilePresenter>)presenter
{
    os_unfair_lock_lock(&presenters_lock);
    if ([presenters() indexOfObjectIdenticalTo:presenter] == NSNotFound)
        [presenters() addObject:presenter];
    os_unfair_lock_unlock(&presenters_lock);
}
+ (void)removeFilePresenter:(id<NSFilePresenter>)presenter
{
    os_unfair_lock_lock(&presenters_lock);
    [presenters() removeObjectIdenticalTo:presenter];
    os_unfair_lock_unlock(&presenters_lock);
}
+ (NSArray *)filePresenters
{
    os_unfair_lock_lock(&presenters_lock);
    NSArray *a = [[presenters() copy] autorelease];
    os_unfair_lock_unlock(&presenters_lock);
    return a;
}
- (instancetype)initWithFilePresenter:(id<NSFilePresenter>)presenter
{
    if ((self = [super init])) {
        _presenter = presenter; /* not retained, as on a Mac */
        _purpose = [[[NSUUID UUID] UUIDString] copy];
    }
    return self;
}
- (instancetype)init { return [self initWithFilePresenter:nil]; }
- (void)dealloc
{
    [_purpose release];
    [super dealloc];
}
- (NSString *)purposeIdentifier { return _purpose; }
- (void)setPurposeIdentifier:(NSString *)p
{
    id wasPurpose = _purpose;
    _purpose = [p copy];
    [wasPurpose release];
}
- (void)cancel {}
- (void)coordinateReadingItemAtURL:(NSURL *)url options:(NSFileCoordinatorReadingOptions)options
                             error:(NSError **)error byAccessor:(void (^)(NSURL *newURL))reader
{
    if (!(options & NSFileCoordinatorReadingWithoutChanges))
        for (id p in presenters_of(url, _presenter))
            if ([p respondsToSelector:@selector(savePresentedItemChangesWithCompletionHandler:)])
                on_queue(p, ^{
                    [p savePresentedItemChangesWithCompletionHandler:^(NSError *e) {}];
                });
    reader(url);
}
/* Each other presenter of the item lets go before the writer runs, and is
 * told afterwards what happened to it. */
- (void)coordinateWritingItemAtURL:(NSURL *)url options:(NSFileCoordinatorWritingOptions)options
                             error:(NSError **)error byAccessor:(void (^)(NSURL *newURL))writer
{
    NSArray *others = presenters_of(url, _presenter);
    NSMutableArray *reacquire = [NSMutableArray array];
    for (id p in others)
        if ([p respondsToSelector:@selector(relinquishPresentedItemToWriter:)])
            [p relinquishPresentedItemToWriter:^(void (^r)(void)) {
                if (r)
                    [reacquire addObject:[[r copy] autorelease]];
            }];
    writer(url);
    for (id p in others) {
        if ((options & NSFileCoordinatorWritingForDeleting) &&
            [p respondsToSelector:@selector(accommodatePresentedItemDeletionWithCompletionHandler:)])
            on_queue(p, ^{
                [p accommodatePresentedItemDeletionWithCompletionHandler:^(NSError *e) {}];
            });
        else if (!(options & NSFileCoordinatorWritingForDeleting) &&
                 [p respondsToSelector:@selector(presentedItemDidChange)])
            on_queue(p, ^{
                [p presentedItemDidChange];
            });
    }
    for (void (^r)(void) in reacquire)
        r();
}
- (void)coordinateReadingItemAtURL:(NSURL *)readingURL options:(NSFileCoordinatorReadingOptions)readingOptions
                  writingItemAtURL:(NSURL *)writingURL options:(NSFileCoordinatorWritingOptions)writingOptions
                             error:(NSError **)error
                        byAccessor:(void (^)(NSURL *newReadingURL, NSURL *newWritingURL))accessor
{
    [self coordinateWritingItemAtURL:writingURL options:writingOptions error:error byAccessor:^(NSURL *w) {
        accessor(readingURL, w);
    }];
}
- (void)coordinateWritingItemAtURL:(NSURL *)url1 options:(NSFileCoordinatorWritingOptions)options1
                  writingItemAtURL:(NSURL *)url2 options:(NSFileCoordinatorWritingOptions)options2
                             error:(NSError **)error
                        byAccessor:(void (^)(NSURL *newURL1, NSURL *newURL2))writer
{
    [self coordinateWritingItemAtURL:url1 options:options1 error:error byAccessor:^(NSURL *a) {
        [self coordinateWritingItemAtURL:url2 options:options2 error:error byAccessor:^(NSURL *b) {
            writer(a, b);
        }];
    }];
}
- (void)prepareForReadingItemsAtURLs:(NSArray *)readingURLs options:(NSFileCoordinatorReadingOptions)readingOptions
                  writingItemsAtURLs:(NSArray *)writingURLs options:(NSFileCoordinatorWritingOptions)writingOptions
                               error:(NSError **)error
                          byAccessor:(void (^)(void (^completionHandler)(void)))batchAccessor
{
    batchAccessor(^{
    });
}
/* A move another presenter of the old place hears of. */
- (void)itemAtURL:(NSURL *)oldURL didMoveToURL:(NSURL *)newURL
{
    for (id p in presenters_of(oldURL, _presenter))
        if ([p respondsToSelector:@selector(presentedItemDidMoveToURL:)])
            on_queue(p, ^{
                [p presentedItemDidMoveToURL:newURL];
            });
}
- (void)itemAtURL:(NSURL *)oldURL willMoveToURL:(NSURL *)newURL {}
@end
