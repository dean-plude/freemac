/* SPDX-License-Identifier: GPL-3.0-or-later
 * Calls Sparkle and the apps carrying it make that Ferry's Foundation lacked
 * (freemac 1.223, Ferry 0.47.0), each written from Apple's public
 * reference for it:
 *
 * - NSProcessInfo's sudden and automatic termination and its activities.
 *   freemac neither ends idle programs nor sleeps on a program's say, so
 *   these keep their counts and hand out tokens, and the thermal state is
 *   always nominal.
 * - NSBundle's localizations: the bundle's .lproj folders, and the best of
 *   a list for the user's languages (the language's own, then its base
 *   language, then English under either name, then the development
 *   localization).
 * - NSString's getFileSystemRepresentation:maxLength: and NSData's older
 *   base64 names.
 * - NSURLDownload, a URL saved to a file, on NSURLConnection. */
#import "FInternal.h"
#include <pwd.h>
#include <string.h>
#include <unistd.h>

/* ---- NSProcessInfo -------------------------------------------------------------------- */

static NSInteger sudden_disabled, automatic_disabled;
static BOOL automatic_support;

@interface FActivity : NSObject {
@public
    NSActivityOptions _options;
    NSString *_reason;
}
@end
@implementation FActivity
- (void)dealloc
{
    [_reason release];
    [super dealloc];
}
- (NSString *)description { return [NSString stringWithFormat:@"<activity: %@>", _reason]; }
@end

@implementation NSProcessInfo (FerryTermination)
- (void)disableSuddenTermination { __sync_fetch_and_add(&sudden_disabled, 1); }
- (void)enableSuddenTermination { __sync_fetch_and_sub(&sudden_disabled, 1); }
- (void)disableAutomaticTermination:(NSString *)reason { __sync_fetch_and_add(&automatic_disabled, 1); }
- (void)enableAutomaticTermination:(NSString *)reason { __sync_fetch_and_sub(&automatic_disabled, 1); }
- (BOOL)automaticTerminationSupportEnabled { return automatic_support; }
- (void)setAutomaticTerminationSupportEnabled:(BOOL)enabled { automatic_support = enabled; }
- (id<NSObject>)beginActivityWithOptions:(NSActivityOptions)options reason:(NSString *)reason
{
    if (!reason)
        [NSException raise:NSInvalidArgumentException format:@"an activity needs a reason"];
    FActivity *a = [[FActivity alloc] init];
    a->_options = options;
    a->_reason = [reason copy];
    if (options & NSActivitySuddenTerminationDisabled)
        [self disableSuddenTermination];
    if (options & NSActivityAutomaticTerminationDisabled)
        [self disableAutomaticTermination:reason];
    return [a autorelease];
}
- (void)endActivity:(id<NSObject>)activity
{
    if (![(id)activity isKindOfClass:[FActivity class]])
        return;
    FActivity *a = (FActivity *)activity;
    if (a->_options & NSActivitySuddenTerminationDisabled)
        [self enableSuddenTermination];
    if (a->_options & NSActivityAutomaticTerminationDisabled)
        [self enableAutomaticTermination:a->_reason];
    a->_options = 0;
}
- (void)performActivityWithOptions:(NSActivityOptions)options reason:(NSString *)reason usingBlock:(void (^)(void))block
{
    id a = [[self beginActivityWithOptions:options reason:reason] retain];
    block();
    [self endActivity:a];
    [a release];
}
- (NSProcessInfoThermalState)thermalState { return NSProcessInfoThermalStateNominal; }
- (BOOL)isLowPowerModeEnabled { return NO; }
- (BOOL)isMacCatalystApp { return NO; }
- (BOOL)isiOSAppOnMac { return NO; }
- (NSString *)userName
{
    struct passwd *pw = getpwuid(getuid());
    return pw ? [NSString stringWithUTF8String:pw->pw_name] : @"";
}
- (NSString *)fullUserName { return NSFullUserName(); }
@end

/* ---- NSBundle's localizations ---------------------------------------------------------- */

/* "en", "en-GB", "en_GB" and "English" as a language and region. */
static NSString *language_of(NSString *name)
{
    NSDictionary *old = @{
        @"English" : @"en", @"French" : @"fr", @"German" : @"de", @"Japanese" : @"ja", @"Spanish" : @"es",
        @"Italian" : @"it", @"Dutch" : @"nl", @"Swedish" : @"sv", @"Portuguese" : @"pt", @"Russian" : @"ru",
        @"Chinese" : @"zh", @"Korean" : @"ko", @"Danish" : @"da", @"Finnish" : @"fi", @"Norwegian" : @"nb",
        @"Polish" : @"pl",
    };
    NSString *s = old[name] ?: name;
    return [[s stringByReplacingOccurrencesOfString:@"_" withString:@"-"] lowercaseString];
}

static NSString *base_language(NSString *tag)
{
    NSRange r = [tag rangeOfString:@"-"];
    return r.location == NSNotFound ? tag : [tag substringToIndex:r.location];
}

@implementation NSBundle (FerryLocalizations)
- (NSArray *)localizations
{
    NSMutableArray *out = [NSMutableArray array];
    NSString *res = [self resourcePath];
    for (NSString *f in [[[NSFileManager defaultManager] contentsOfDirectoryAtPath:res error:NULL]
             sortedArrayUsingSelector:@selector(compare:)])
        if ([[f pathExtension] isEqualToString:@"lproj"])
            [out addObject:[f stringByDeletingPathExtension]];
    return out;
}
- (NSString *)developmentLocalization
{
    NSString *d = [self objectForInfoDictionaryKey:@"CFBundleDevelopmentRegion"];
    return [d isKindOfClass:[NSString class]] ? d : nil;
}
- (NSArray *)preferredLocalizations
{
    NSMutableArray *locs = [[[self localizations] mutableCopy] autorelease];
    [locs removeObject:@"Base"];
    NSString *dev = [self developmentLocalization];
    if (![locs count] && dev)
        [locs addObject:dev];
    NSArray *out = [NSBundle preferredLocalizationsFromArray:locs];
    return [out count] ? out : (dev ? @[ dev ] : @[]);
}
+ (NSArray *)preferredLocalizationsFromArray:(NSArray *)localizations
{
    return [self preferredLocalizationsFromArray:localizations forPreferences:nil];
}
+ (NSArray *)preferredLocalizationsFromArray:(NSArray *)localizations forPreferences:(NSArray *)preferences
{
    if (![localizations count])
        return @[];
    NSArray *prefs = preferences ?: [NSLocale preferredLanguages];
    for (NSString *pref in prefs) {
        NSString *want = language_of(pref), *want_base = base_language(want);
        /* the language and region the user asked for, then the language */
        for (NSString *l in localizations)
            if ([language_of(l) isEqualToString:want])
                return @[ l ];
        for (NSString *l in localizations)
            if ([base_language(language_of(l)) isEqualToString:want_base])
                return @[ l ];
    }
    for (NSString *l in localizations)
        if ([base_language(language_of(l)) isEqualToString:@"en"])
            return @[ l ];
    NSString *dev = [[NSBundle mainBundle] developmentLocalization];
    if (dev && [localizations containsObject:dev])
        return @[ dev ];
    return @[ [localizations objectAtIndex:0] ];
}
/* A resource in one localization's .lproj folder, then outside any. */
- (NSString *)pathForResource:(NSString *)name
                       ofType:(NSString *)ext
                  inDirectory:(NSString *)subpath
              forLocalization:(NSString *)localization
{
    if ([localization length]) {
        NSString *dir = [localization stringByAppendingPathExtension:@"lproj"];
        NSString *in = subpath ? [subpath stringByAppendingPathComponent:dir] : dir;
        NSString *p = [self pathForResource:name ofType:ext inDirectory:in];
        if (p)
            return p;
        in = subpath ? [dir stringByAppendingPathComponent:subpath] : dir;
        if ((p = [self pathForResource:name ofType:ext inDirectory:in]))
            return p;
    }
    return [self pathForResource:name ofType:ext inDirectory:subpath];
}
- (NSArray *)pathsForResourcesOfType:(NSString *)ext
                         inDirectory:(NSString *)subpath
                     forLocalization:(NSString *)localization
{
    if (![localization length])
        return [self pathsForResourcesOfType:ext inDirectory:subpath];
    NSString *dir = [localization stringByAppendingPathExtension:@"lproj"];
    return [self pathsForResourcesOfType:ext inDirectory:subpath ? [subpath stringByAppendingPathComponent:dir] : dir];
}
- (NSURL *)URLForResource:(NSString *)name
            withExtension:(NSString *)ext
             subdirectory:(NSString *)subpath
             localization:(NSString *)localization
{
    NSString *p = [self pathForResource:name ofType:ext inDirectory:subpath forLocalization:localization];
    return p ? [NSURL fileURLWithPath:p] : nil;
}
@end

/* ---- strings and data ---------------------------------------------------------------- */

@implementation NSString (FerryFileSystemBuffer)
- (BOOL)getFileSystemRepresentation:(char *)buffer maxLength:(NSUInteger)maxLength
{
    const char *s = [self fileSystemRepresentation];
    if (!s || !buffer || strlen(s) + 1 > maxLength)
        return NO;
    memcpy(buffer, s, strlen(s) + 1);
    return YES;
}
@end

@implementation NSData (FerryOlderBase64)
- (instancetype)initWithBase64Encoding:(NSString *)string
{
    /* the older call skipped characters outside the alphabet */
    return [self initWithBase64EncodedString:string options:NSDataBase64DecodingIgnoreUnknownCharacters];
}
- (NSString *)base64Encoding { return [self base64EncodedStringWithOptions:0]; }
@end

/* ---- NSURLDownload ------------------------------------------------------------------ */

@implementation NSURLDownload {
    NSURLRequest *_request;
    id<NSURLDownloadDelegate> _delegate;
    NSURLConnection *_connection;
    NSString *_path;
    NSFileHandle *_file;
    BOOL _overwrite, _deletes, _created, _done;
}
+ (BOOL)canResumeDownloadDecodedWithEncodingMIMEType:(NSString *)MIMEType { return NO; }
- (instancetype)initWithRequest:(NSURLRequest *)request delegate:(id<NSURLDownloadDelegate>)delegate
{
    if (!(self = [super init]))
        return nil;
    _request = [request copy];
    _delegate = delegate;
    _deletes = YES;
    /* the connection keeps this download (its delegate) until it ends */
    _connection = [[NSURLConnection alloc] initWithRequest:request delegate:self startImmediately:NO];
    [self performSelector:@selector(_begin) withObject:nil afterDelay:0];
    return self;
}
- (instancetype)initWithResumeData:(NSData *)resumeData delegate:(id<NSURLDownloadDelegate>)delegate path:(NSString *)path
{
    [self release];
    return nil;
}
- (void)dealloc
{
    [_request release];
    [_connection release];
    [_path release];
    [_file release];
    [super dealloc];
}
- (NSURLRequest *)request { return _request; }
- (NSData *)resumeData { return nil; }
- (BOOL)deletesFileUponFailure { return _deletes; }
- (void)setDeletesFileUponFailure:(BOOL)deletes { _deletes = deletes; }
- (void)setDestination:(NSString *)path allowOverwrite:(BOOL)allowOverwrite
{
    if (_created)
        return;
    [_path release];
    _path = [path copy];
    _overwrite = allowOverwrite;
}
- (void)_begin
{
    if (_done)
        return;
    [_connection start];
    if ([_delegate respondsToSelector:@selector(downloadDidBegin:)])
        [_delegate downloadDidBegin:self];
}
/* The file: the destination the delegate chose, or one in the temporary
 * folder, named "name-2.ext" and so on when it may not be overwritten. */
- (BOOL)_createFile:(NSString *)suggested
{
    NSFileManager *fm = [NSFileManager defaultManager];
    if (!_path) {
        NSString *name = [suggested length] ? [suggested lastPathComponent] : @"download";
        _path = [[NSTemporaryDirectory() stringByAppendingPathComponent:name] copy];
    }
    if (!_overwrite) {
        NSString *base = [_path stringByDeletingPathExtension], *ext = [_path pathExtension];
        for (int n = 2; [fm fileExistsAtPath:_path]; n++) {
            NSString *p = [NSString stringWithFormat:@"%@-%d", base, n];
            if ([ext length])
                p = [p stringByAppendingPathExtension:ext];
            [_path release];
            _path = [p copy];
        }
    }
    if (![fm createFileAtPath:_path contents:nil attributes:nil])
        return NO;
    _file = [[NSFileHandle fileHandleForWritingAtPath:_path] retain];
    _created = _file != nil;
    if (_created && [_delegate respondsToSelector:@selector(download:didCreateDestination:)])
        [_delegate download:self didCreateDestination:_path];
    return _created;
}
- (void)_failWith:(NSError *)error
{
    if (_done)
        return;
    _done = YES;
    [_file closeFile];
    if (_created && _deletes)
        [[NSFileManager defaultManager] removeItemAtPath:_path error:NULL];
    [self retain];
    if ([_delegate respondsToSelector:@selector(download:didFailWithError:)])
        [_delegate download:self didFailWithError:error];
    [self release];
}
- (void)cancel
{
    if (_done)
        return;
    _done = YES;
    [_connection cancel];
    [_file closeFile];
    if (_created)
        [[NSFileManager defaultManager] removeItemAtPath:_path error:NULL];
}
- (NSURLRequest *)connection:(NSURLConnection *)connection
             willSendRequest:(NSURLRequest *)request
            redirectResponse:(NSURLResponse *)response
{
    if ([_delegate respondsToSelector:@selector(download:willSendRequest:redirectResponse:)])
        return [_delegate download:self willSendRequest:request redirectResponse:response];
    return request;
}
- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response
{
    if (_done)
        return;
    if ([_delegate respondsToSelector:@selector(download:didReceiveResponse:)])
        [_delegate download:self didReceiveResponse:response];
    if (!_created) {
        if (!_path && [_delegate respondsToSelector:@selector(download:decideDestinationWithSuggestedFilename:)])
            [_delegate download:self decideDestinationWithSuggestedFilename:[response suggestedFilename]];
        if (!_done && ![self _createFile:[response suggestedFilename]]) {
            [_connection cancel];
            [self _failWith:[NSError errorWithDomain:NSCocoaErrorDomain code:NSFileWriteUnknownError
                                            userInfo:@{NSFilePathErrorKey : _path ?: @""}]];
        }
    }
}
- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data
{
    if (_done || !_file)
        return;
    [_file writeData:data];
    if ([_delegate respondsToSelector:@selector(download:didReceiveDataOfLength:)])
        [_delegate download:self didReceiveDataOfLength:[data length]];
}
- (void)connectionDidFinishLoading:(NSURLConnection *)connection
{
    if (_done)
        return;
    if (!_created && ![self _createFile:nil]) {
        [self _failWith:[NSError errorWithDomain:NSCocoaErrorDomain code:NSFileWriteUnknownError userInfo:nil]];
        return;
    }
    _done = YES;
    [_file closeFile];
    [self retain];
    if ([_delegate respondsToSelector:@selector(downloadDidFinish:)])
        [_delegate downloadDidFinish:self];
    [self release];
}
- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error
{
    [self _failWith:error];
}
@end
