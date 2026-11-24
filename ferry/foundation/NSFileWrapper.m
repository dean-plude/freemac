/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's Foundation: NSFileWrapper, a regular file, a folder of other
 * wrappers or a symbolic link, held in memory, which documents read and
 * write (NSDocument's file-wrapper methods). Ferry's own code, written from
 * Apple's public NSFileWrapper documentation; no Apple code was used. A
 * folder's children are keyed by file name; a child added under a name
 * that is taken gets a key of its own ("2 name", "3 name"...), and with
 * NSFileWrapperWritingWithNameUpdating its file name becomes that key.
 * The serialized representation is Ferry's own property list of the tree,
 * read back by Ferry alone. Built without ARC. */
#import "FInternal.h"
#include <sys/stat.h>
#include <errno.h>
#include <unistd.h>
#include <stdio.h>

enum { W_FILE, W_DIRECTORY, W_LINK };

@implementation NSFileWrapper {
    int _kind;
    NSData *_contents;
    NSMutableDictionary *_children;
    NSString *_destination;
    NSString *_preferred, *_filename;
    NSDictionary *_attributes;
}

static NSError *write_error(int err, NSString *path)
{
    NSError *under = [NSError errorWithDomain:NSPOSIXErrorDomain code:err userInfo:nil];
    NSInteger code = err == EACCES || err == EPERM ? NSFileWriteNoPermissionError
                     : err == EROFS                 ? NSFileWriteVolumeReadOnlyError
                                                    : NSFileWriteUnknownError;
    NSMutableDictionary *info = [NSMutableDictionary dictionaryWithObject:under forKey:NSUnderlyingErrorKey];
    if (path)
        [info setObject:path forKey:NSFilePathErrorKey];
    return [NSError errorWithDomain:NSCocoaErrorDomain code:code userInfo:info];
}

- (instancetype)init { return [self initDirectoryWithFileWrappers:@{}]; }

- (instancetype)initRegularFileWithContents:(NSData *)contents
{
    if ((self = [super init])) {
        _kind = W_FILE;
        _contents = [contents ?: [NSData data] copy];
    }
    return self;
}

- (instancetype)initDirectoryWithFileWrappers:(NSDictionary *)wrappers
{
    if ((self = [super init])) {
        _kind = W_DIRECTORY;
        _children = [[NSMutableDictionary alloc] init];
        for (NSString *key in wrappers) {
            NSFileWrapper *w = [wrappers objectForKey:key];
            if (![w preferredFilename])
                [w setPreferredFilename:key];
            [_children setObject:w forKey:key];
        }
    }
    return self;
}

- (instancetype)initSymbolicLinkWithDestinationURL:(NSURL *)url
{
    return [self initSymbolicLinkWithDestination:[url path]];
}
- (instancetype)initSymbolicLinkWithDestination:(NSString *)path
{
    if ((self = [super init])) {
        _kind = W_LINK;
        _destination = [path ?: @"" copy];
    }
    return self;
}

- (instancetype)initWithURL:(NSURL *)url options:(NSFileWrapperReadingOptions)options error:(NSError **)error
{
    if (!(self = [super init]))
        return nil;
    if (![self readFromURL:url options:options error:error]) {
        [self release];
        return nil;
    }
    return self;
}
- (instancetype)initWithPath:(NSString *)path
{
    return [self initWithURL:[NSURL fileURLWithPath:path] options:0 error:NULL];
}

- (void)dealloc
{
    [_contents release];
    [_children release];
    [_destination release];
    [_preferred release];
    [_filename release];
    [_attributes release];
    [super dealloc];
}

/* ---- reading ---- */

- (BOOL)readFromURL:(NSURL *)url options:(NSFileWrapperReadingOptions)options error:(NSError **)error
{
    NSString *path = [url path];
    struct stat st;
    if (![url isFileURL] || lstat([path fileSystemRepresentation], &st) != 0) {
        FSetError(error, FPosixError([url isFileURL] ? errno : ENOENT, path));
        return NO;
    }
    [_contents release];
    _contents = nil;
    [_children release];
    _children = nil;
    [_destination release];
    _destination = nil;
    if (S_ISLNK(st.st_mode)) {
        _kind = W_LINK;
        _destination = [[[NSFileManager defaultManager] destinationOfSymbolicLinkAtPath:path error:NULL] copy];
    } else if (S_ISDIR(st.st_mode)) {
        _kind = W_DIRECTORY;
        _children = [[NSMutableDictionary alloc] init];
        NSArray *names = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:path error:error];
        if (!names)
            return NO;
        for (NSString *name in names) {
            NSFileWrapper *child = [[NSFileWrapper alloc] initWithURL:[url URLByAppendingPathComponent:name]
                                                              options:options error:error];
            if (!child)
                return NO;
            [_children setObject:child forKey:name];
            [child release];
        }
    } else {
        _kind = W_FILE;
        _contents = [[NSData alloc] initWithContentsOfFile:path];
        if (!_contents) {
            FSetError(error, FPosixError(errno ? errno : EIO, path));
            return NO;
        }
    }
    NSString *name = [path lastPathComponent];
    [self setFilename:name];
    if (!_preferred)
        [self setPreferredFilename:name];
    [self setFileAttributes:[[NSFileManager defaultManager] attributesOfItemAtPath:path error:NULL]];
    return YES;
}

- (BOOL)matchesContentsOfURL:(NSURL *)url
{
    NSFileWrapper *now = [[[NSFileWrapper alloc] initWithURL:url options:0 error:NULL] autorelease];
    return now && [self _sameAs:now];
}
- (BOOL)_sameAs:(NSFileWrapper *)o
{
    if (o->_kind != _kind)
        return NO;
    if (_kind == W_FILE)
        return [_contents isEqualToData:o->_contents];
    if (_kind == W_LINK)
        return [_destination isEqualToString:o->_destination];
    if ([_children count] != [o->_children count])
        return NO;
    for (NSString *key in _children) {
        NSFileWrapper *theirs = [o->_children objectForKey:key];
        if (!theirs || ![[_children objectForKey:key] _sameAs:theirs])
            return NO;
    }
    return YES;
}

/* ---- what it holds ---- */

- (BOOL)isDirectory { return _kind == W_DIRECTORY; }
- (BOOL)isRegularFile { return _kind == W_FILE; }
- (BOOL)isSymbolicLink { return _kind == W_LINK; }
- (NSString *)preferredFilename { return _preferred; }
- (void)setPreferredFilename:(NSString *)name
{
    if (name == _preferred)
        return;
    [_preferred release];
    _preferred = [name copy];
}
- (NSString *)filename { return _filename; }
- (void)setFilename:(NSString *)name
{
    if (name == _filename)
        return;
    [_filename release];
    _filename = [name copy];
}
- (NSDictionary *)fileAttributes { return _attributes ?: @{}; }
- (void)setFileAttributes:(NSDictionary *)attributes
{
    [_attributes release];
    _attributes = [attributes copy];
}
- (NSData *)regularFileContents
{
    if (_kind != W_FILE)
        FRaise(NSInternalInconsistencyException, @"-[NSFileWrapper regularFileContents] sent to a wrapper that "
                                                 @"isn't a regular file");
    return _contents;
}
- (NSDictionary *)fileWrappers
{
    if (_kind != W_DIRECTORY)
        return nil;
    return [[_children copy] autorelease];
}
- (NSString *)symbolicLinkDestination { return _kind == W_LINK ? _destination : nil; }
- (NSURL *)symbolicLinkDestinationURL
{
    if (_kind != W_LINK)
        return nil;
    /* a relative link is taken from the folder it would be in */
    return [_destination isAbsolutePath] ? [NSURL fileURLWithPath:_destination]
                                         : [NSURL fileURLWithPath:[[[NSFileManager defaultManager] currentDirectoryPath]
                                                                      stringByAppendingPathComponent:_destination]];
}

/* ---- a folder's children ---- */

- (NSString *)_freeKeyFor:(NSString *)name
{
    if (![_children objectForKey:name])
        return name;
    for (int n = 2;; n++) {
        NSString *key = [NSString stringWithFormat:@"%d %@", n, name];
        if (![_children objectForKey:key])
            return key;
    }
}
- (NSString *)addFileWrapper:(NSFileWrapper *)child
{
    if (_kind != W_DIRECTORY)
        FRaise(NSInternalInconsistencyException, @"-[NSFileWrapper addFileWrapper:] sent to a wrapper that "
                                                 @"isn't a directory");
    NSString *name = [child preferredFilename] ?: [child filename];
    if (![name length])
        FRaise(NSInvalidArgumentException, @"-[NSFileWrapper addFileWrapper:]: the child has no preferred file name");
    NSString *key = [self _freeKeyFor:name];
    [_children setObject:child forKey:key];
    return key;
}
- (NSString *)addRegularFileWithContents:(NSData *)data preferredFilename:(NSString *)name
{
    NSFileWrapper *w = [[NSFileWrapper alloc] initRegularFileWithContents:data];
    [w setPreferredFilename:name];
    NSString *key = [self addFileWrapper:w];
    [w release];
    return key;
}
- (void)removeFileWrapper:(NSFileWrapper *)child
{
    NSString *key = [self keyForFileWrapper:child];
    if (key)
        [_children removeObjectForKey:key];
}
- (NSString *)keyForFileWrapper:(NSFileWrapper *)child
{
    for (NSString *key in _children)
        if ([_children objectForKey:key] == child)
            return key;
    return nil;
}

/* ---- writing ---- */

/* Writes the tree at path, which mustn't exist yet. */
- (BOOL)_writeAt:(NSString *)path updateNames:(BOOL)update error:(NSError **)error
{
    const char *fs = [path fileSystemRepresentation];
    switch (_kind) {
    case W_FILE:
        if (![_contents writeToFile:path options:0 error:error])
            return NO;
        break;
    case W_LINK:
        if (symlink([_destination fileSystemRepresentation], fs) != 0) {
            FSetError(error, write_error(errno, path));
            return NO;
        }
        break;
    default:
        if (mkdir(fs, 0777) != 0) {
            FSetError(error, write_error(errno, path));
            return NO;
        }
        for (NSString *key in [[_children allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
            NSFileWrapper *child = [_children objectForKey:key];
            if (![child _writeAt:[path stringByAppendingPathComponent:key] updateNames:update error:error])
                return NO;
            if (update)
                [child setFilename:key];
        }
        break;
    }
    NSNumber *perm = [_attributes objectForKey:NSFilePosixPermissions];
    if (perm && _kind != W_LINK)
        chmod(fs, (mode_t)[perm unsignedShortValue]);
    return YES;
}

static void remove_tree(NSString *path)
{
    [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
}

- (BOOL)writeToURL:(NSURL *)url options:(NSFileWrapperWritingOptions)options
    originalContentsURL:(NSURL *)original error:(NSError **)error
{
    if (![url isFileURL]) {
        FSetError(error, [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileWriteUnknownError userInfo:nil]);
        return NO;
    }
    NSString *path = [[url path] stringByStandardizingPath];
    BOOL update = (options & NSFileWrapperWritingWithNameUpdating) != 0;
    struct stat st;
    BOOL exists = lstat([path fileSystemRepresentation], &st) == 0;
    if (!(options & NSFileWrapperWritingAtomic)) {
        if (exists && (S_ISDIR(st.st_mode) || _kind != W_FILE))
            remove_tree(path);
        if (![self _writeAt:path updateNames:update error:error])
            return NO;
    } else {
        /* written beside it, then put in its place */
        NSString *dir = [path stringByDeletingLastPathComponent];
        NSString *temp = [dir stringByAppendingPathComponent:
                                  [NSString stringWithFormat:@".%@.%d.ferry-writing", [path lastPathComponent],
                                                             (int)getpid()]];
        remove_tree(temp);
        if (![self _writeAt:temp updateNames:update error:error]) {
            remove_tree(temp);
            return NO;
        }
        if (exists && S_ISDIR(st.st_mode)) {
            NSString *old = [temp stringByAppendingString:@"-old"];
            remove_tree(old);
            if (rename([path fileSystemRepresentation], [old fileSystemRepresentation]) != 0 ||
                rename([temp fileSystemRepresentation], [path fileSystemRepresentation]) != 0) {
                FSetError(error, write_error(errno, path));
                remove_tree(temp);
                return NO;
            }
            remove_tree(old);
        } else if (rename([temp fileSystemRepresentation], [path fileSystemRepresentation]) != 0) {
            FSetError(error, write_error(errno, path));
            remove_tree(temp);
            return NO;
        }
    }
    if (update)
        [self setFilename:[path lastPathComponent]];
    return YES;
}

- (BOOL)writeToFile:(NSString *)path atomically:(BOOL)atomically updateFilenames:(BOOL)update
{
    NSFileWrapperWritingOptions o = (atomically ? NSFileWrapperWritingAtomic : 0) |
                                    (update ? NSFileWrapperWritingWithNameUpdating : 0);
    return [self writeToURL:[NSURL fileURLWithPath:path] options:o originalContentsURL:nil error:NULL];
}

/* ---- the serialized representation: Ferry's own property list ---- */

- (id)_plist
{
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    if (_preferred)
        [d setObject:_preferred forKey:@"name"];
    if (_kind == W_FILE) {
        [d setObject:_contents forKey:@"contents"];
    } else if (_kind == W_LINK) {
        [d setObject:_destination forKey:@"link"];
    } else {
        NSMutableDictionary *kids = [NSMutableDictionary dictionary];
        for (NSString *key in _children)
            [kids setObject:[[_children objectForKey:key] _plist] forKey:key];
        [d setObject:kids forKey:@"children"];
    }
    return d;
}
- (instancetype)_initWithPlist:(NSDictionary *)d
{
    if (![d isKindOfClass:[NSDictionary class]]) {
        [self release];
        return nil;
    }
    if ([d objectForKey:@"contents"])
        self = [self initRegularFileWithContents:[d objectForKey:@"contents"]];
    else if ([d objectForKey:@"link"])
        self = [self initSymbolicLinkWithDestination:[d objectForKey:@"link"]];
    else {
        self = [self initDirectoryWithFileWrappers:@{}];
        NSDictionary *kids = [d objectForKey:@"children"];
        for (NSString *key in kids) {
            NSFileWrapper *k = [[NSFileWrapper alloc] _initWithPlist:[kids objectForKey:key]];
            if (k)
                [_children setObject:k forKey:key];
            [k release];
        }
    }
    [self setPreferredFilename:[d objectForKey:@"name"]];
    return self;
}
- (NSData *)serializedRepresentation
{
    return [NSPropertyListSerialization dataWithPropertyList:[self _plist] format:NSPropertyListBinaryFormat_v1_0
                                                     options:0 error:NULL];
}
- (instancetype)initWithSerializedRepresentation:(NSData *)data
{
    id plist = [NSPropertyListSerialization propertyListWithData:data options:0 format:NULL error:NULL];
    return [self _initWithPlist:plist];
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    [coder encodeObject:[self serializedRepresentation] forKey:@"NSFileWrapperSerialized"];
}
- (instancetype)initWithCoder:(NSCoder *)coder
{
    return [self initWithSerializedRepresentation:[coder decodeObjectForKey:@"NSFileWrapperSerialized"]];
}
@end
