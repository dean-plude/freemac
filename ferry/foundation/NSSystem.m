/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's Foundation: NSProcessInfo, NSBundle, NSUserDefaults and
 * NSFileManager. These map a Mac app's view of the system onto freemac:
 * bundles are read from the .app folder the program sits in, preferences
 * are kept as XML property lists under ~/.config/ferry/preferences, and the
 * Mac's standard folders become their usual Linux places. */
#import "FInternal.h"
#include <dirent.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/stat.h>

int *_NSGetArgc(void);
char ***_NSGetArgv(void);
char ***_NSGetEnviron(void);
int _NSGetExecutablePath(char *buf, uint32_t *size);
NSString *FUserFolder(NSSearchPathDirectory dir);

NSString *const NSFileSize = @"NSFileSize";
NSString *const NSFileType = @"NSFileType";
NSString *const NSFileModificationDate = @"NSFileModificationDate";
NSString *const NSFilePosixPermissions = @"NSFilePosixPermissions";
NSString *const NSFileTypeDirectory = @"NSFileTypeDirectory";
NSString *const NSFileTypeRegular = @"NSFileTypeRegular";
NSString *const NSFileTypeSymbolicLink = @"NSFileTypeSymbolicLink";

/* ---- NSProcessInfo --------------------------------------------------------------------- */

const char *ferry_macos_version(const char **build); /* src/sysversion.c */

/* "14.7" as numbers, and the build ("23H124"). */
static NSOperatingSystemVersion FSystemVersion(const char **build)
{
    NSOperatingSystemVersion v = {0, 0, 0};
    const char *s = ferry_macos_version(build);
    char *end;
    v.majorVersion = strtol(s, &end, 10);
    if (*end == '.')
        v.minorVersion = strtol(end + 1, &end, 10);
    if (*end == '.')
        v.patchVersion = strtol(end + 1, &end, 10);
    return v;
}

@implementation NSProcessInfo {
    NSString *_name;
}
+ (NSProcessInfo *)processInfo
{
    static NSProcessInfo *shared;
    if (!shared)
        shared = [[NSProcessInfo alloc] init];
    return shared;
}
- (NSArray *)arguments
{
    int argc = *_NSGetArgc();
    char **argv = *_NSGetArgv();
    NSMutableArray *a = [NSMutableArray array];
    for (int i = 0; i < argc; i++)
        [a addObject:[NSString stringWithUTF8String:argv[i]]];
    return a;
}
- (NSDictionary *)environment
{
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    for (char **e = *_NSGetEnviron(); e && *e; e++) {
        const char *eq = strchr(*e, '=');
        if (eq)
            [d setObject:[NSString stringWithUTF8String:eq + 1] forKey:FStringFromUTF8(*e, eq - *e)];
    }
    return d;
}
- (NSString *)processName
{
    if (!_name) {
        char **argv = *_NSGetArgv();
        _name = [[[NSString stringWithUTF8String:argv && argv[0] ? argv[0] : "program"] lastPathComponent] copy];
    }
    return _name;
}
- (void)setProcessName:(NSString *)name
{
    [_name release];
    _name = [name copy];
}
- (int)processIdentifier { return getpid(); }
- (NSString *)hostName
{
    char buf[256] = "localhost";
    gethostname(buf, sizeof buf - 1);
    return [NSString stringWithUTF8String:buf];
}
- (NSString *)globallyUniqueString
{
    unsigned char b[16];
    arc4random_buf(b, sizeof b);
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    return [NSString stringWithFormat:@"%02X%02X%02X%02X-%02X%02X-%02X%02X-%02X%02X-%02X%02X%02X%02X%02X%02X", b[0],
                                      b[1], b[2], b[3], b[4], b[5], b[6], b[7], b[8], b[9], b[10], b[11], b[12], b[13],
                                      b[14], b[15]];
}
- (NSUInteger)processorCount { return (NSUInteger)sysconf(_SC_NPROCESSORS_CONF); }
- (NSUInteger)activeProcessorCount { return (NSUInteger)sysconf(_SC_NPROCESSORS_ONLN); }
- (unsigned long long)physicalMemory
{
    return (unsigned long long)sysconf(_SC_PHYS_PAGES) * (unsigned long long)sysconf(_SC_PAGESIZE);
}
- (NSTimeInterval)systemUptime
{
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec + ts.tv_nsec / 1e9;
}
/* The version comes from Ferry itself (src/sysversion.c), which answers
 * uname and serves the Mac's version file from the same numbers. */
- (NSOperatingSystemVersion)operatingSystemVersion { return FSystemVersion(NULL); }
- (BOOL)isOperatingSystemAtLeastVersion:(NSOperatingSystemVersion)v
{
    NSOperatingSystemVersion me = FSystemVersion(NULL);
    if (me.majorVersion != v.majorVersion)
        return me.majorVersion > v.majorVersion;
    if (me.minorVersion != v.minorVersion)
        return me.minorVersion > v.minorVersion;
    return me.patchVersion >= v.patchVersion;
}
- (NSString *)operatingSystemVersionString
{
    const char *build;
    NSOperatingSystemVersion v = FSystemVersion(&build);
    if (v.patchVersion)
        return [NSString stringWithFormat:@"Version %ld.%ld.%ld (Build %s)", (long)v.majorVersion,
                                          (long)v.minorVersion, (long)v.patchVersion, build];
    return [NSString stringWithFormat:@"Version %ld.%ld (Build %s)", (long)v.majorVersion, (long)v.minorVersion,
                                      build];
}
@end

/* ---- Gestalt ------------------------------------------------------------------------------
 * The one Carbon (CoreServices) call that is still about the system's
 * version, served from here, next to NSProcessInfo, so that it answers the
 * same; the loader serves CoreServices from Foundation's file, and Carbon's
 * link stub lists it too. Written from Apple's documentation of the
 * selectors. */

typedef int16_t OSErr;
typedef uint32_t OSType;
enum {
    gestaltSystemVersion = 'sysv',
    gestaltSystemVersionMajor = 'sys1',
    gestaltSystemVersionMinor = 'sys2',
    gestaltSystemVersionBugFix = 'sys3',
    gestaltUndefSelectorErr = -5551,
};

F_EXPORT OSErr Gestalt(OSType selector, int32_t *response)
{
    NSOperatingSystemVersion v = FSystemVersion(NULL);
    int32_t value;
    switch (selector) {
    case gestaltSystemVersionMajor: value = (int32_t)v.majorVersion; break;
    case gestaltSystemVersionMinor: value = (int32_t)v.minorVersion; break;
    case gestaltSystemVersionBugFix: value = (int32_t)v.patchVersion; break;
    case gestaltSystemVersion: {
        /* binary-coded decimal, 0xMMmb, with a minor or bug fix number above
         * 9 shown as 9, as documented */
        int major = (int)(v.majorVersion % 100), minor = v.minorVersion > 9 ? 9 : (int)v.minorVersion,
            fix = v.patchVersion > 9 ? 9 : (int)v.patchVersion;
        value = (major / 10) << 12 | (major % 10) << 8 | minor << 4 | fix;
        break;
    }
    default: return gestaltUndefSelectorErr;
    }
    if (response)
        *response = value;
    return 0;
}

/* ---- NSBundle ---------------------------------------------------------------------------- */

static NSArray *preferred_languages(void)
{
    NSMutableArray *langs = [NSMutableArray array];
    const char *vars[] = {"LC_ALL", "LC_MESSAGES", "LANG"};
    for (int i = 0; i < 3; i++) {
        const char *v = getenv(vars[i]);
        if (v && *v && strcmp(v, "C") && strcmp(v, "POSIX")) {
            NSString *s = [NSString stringWithUTF8String:v];
            s = [[s componentsSeparatedByString:@"."] objectAtIndex:0];
            [langs addObject:s];
            NSString *base = [[s componentsSeparatedByString:@"_"] objectAtIndex:0];
            if (![base isEqualToString:s])
                [langs addObject:base];
            break;
        }
    }
    [langs addObjectsFromArray:[NSArray arrayWithObjects:@"en", @"English", @"Base", nil]];
    return langs;
}

@implementation NSBundle {
    NSString *_path, *_resources, *_executable;
    NSDictionary *_info;
    NSMutableDictionary *_tables;
}
+ (NSBundle *)mainBundle
{
    static NSBundle *main;
    if (!main) {
        char buf[4096];
        uint32_t size = sizeof buf;
        NSString *exe = nil;
        if (_NSGetExecutablePath(buf, &size) == 0) {
            char real[4096];
            exe = [NSString stringWithUTF8String:realpath(buf, real) ? real : buf];
        }
        NSString *dir = [exe stringByDeletingLastPathComponent];
        NSString *path = dir;
        if ([[dir lastPathComponent] isEqualToString:@"MacOS"] &&
            [[[dir stringByDeletingLastPathComponent] lastPathComponent] isEqualToString:@"Contents"])
            path = [[dir stringByDeletingLastPathComponent] stringByDeletingLastPathComponent];
        main = [[NSBundle alloc] initWithPath:path];
        if (!main->_executable)
            main->_executable = [exe copy];
    }
    return main;
}
+ (NSBundle *)bundleWithPath:(NSString *)path { return [[[self alloc] initWithPath:path] autorelease]; }
+ (NSBundle *)bundleForClass:(Class)cls
{
    /* Ferry doesn't yet track which loaded image defines a class. */
    return [self mainBundle];
}
- (instancetype)initWithPath:(NSString *)path
{
    BOOL dir = NO;
    if (!path || ![[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&dir] || !dir) {
        [self release];
        return nil;
    }
    _path = [[path stringByStandardizingPath] copy];
    NSString *contents = [_path stringByAppendingPathComponent:@"Contents"];
    BOOL app = [[NSFileManager defaultManager] fileExistsAtPath:[contents stringByAppendingPathComponent:@"Info.plist"]];
    NSString *infoPath = app ? [contents stringByAppendingPathComponent:@"Info.plist"]
                             : [_path stringByAppendingPathComponent:@"Info.plist"];
    _resources = [(app ? [contents stringByAppendingPathComponent:@"Resources"] : _path) copy];
    _info = [[NSDictionary dictionaryWithContentsOfFile:infoPath] retain];
    NSString *exeName = [_info objectForKey:@"CFBundleExecutable"];
    if (exeName)
        _executable = [[[contents stringByAppendingPathComponent:@"MacOS"] stringByAppendingPathComponent:exeName] copy];
    _tables = [[NSMutableDictionary alloc] init];
    return self;
}
- (void)dealloc
{
    [_path release];
    [_resources release];
    [_executable release];
    [_info release];
    [_tables release];
    [super dealloc];
}
- (NSString *)bundlePath { return _path; }
- (NSString *)resourcePath { return _resources; }
- (NSString *)executablePath { return _executable; }
- (NSURL *)bundleURL { return [NSURL fileURLWithPath:_path isDirectory:YES]; }
- (NSURL *)resourceURL { return [NSURL fileURLWithPath:_resources isDirectory:YES]; }
- (NSString *)bundleIdentifier { return [_info objectForKey:@"CFBundleIdentifier"]; }
- (NSDictionary *)infoDictionary { return _info ?: [NSDictionary dictionary]; }
- (NSDictionary *)localizedInfoDictionary { return [self infoDictionary]; }
- (id)objectForInfoDictionaryKey:(NSString *)key { return [_info objectForKey:key]; }
- (NSString *)description { return [NSString stringWithFormat:@"NSBundle <%@> (loaded)", _path]; }
- (NSString *)pathForResource:(NSString *)name ofType:(NSString *)ext inDirectory:(NSString *)subpath
{
    NSString *file = name;
    if ([ext length])
        file = [name stringByAppendingPathExtension:ext];
    NSString *base = subpath ? [_resources stringByAppendingPathComponent:subpath] : _resources;
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *p = [base stringByAppendingPathComponent:file];
    if ([fm fileExistsAtPath:p])
        return p;
    for (NSString *lang in preferred_languages()) {
        p = [[base stringByAppendingPathComponent:[lang stringByAppendingPathExtension:@"lproj"]]
            stringByAppendingPathComponent:file];
        if ([fm fileExistsAtPath:p])
            return p;
    }
    return nil;
}
- (NSString *)pathForResource:(NSString *)name ofType:(NSString *)ext
{
    return [self pathForResource:name ofType:ext inDirectory:nil];
}
- (NSArray *)pathsForResourcesOfType:(NSString *)ext inDirectory:(NSString *)subpath
{
    NSString *base = subpath ? [_resources stringByAppendingPathComponent:subpath] : _resources;
    NSMutableArray *out = [NSMutableArray array];
    for (NSString *f in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:base error:NULL])
        if (![ext length] || [[f pathExtension] isEqualToString:ext])
            [out addObject:[base stringByAppendingPathComponent:f]];
    return out;
}
- (NSURL *)URLForResource:(NSString *)name withExtension:(NSString *)ext
{
    NSString *p = [self pathForResource:name ofType:ext];
    return p ? [NSURL fileURLWithPath:p] : nil;
}
- (NSString *)localizedStringForKey:(NSString *)key value:(NSString *)value table:(NSString *)tableName
{
    if (!tableName)
        tableName = @"Localizable";
    NSDictionary *table = [_tables objectForKey:tableName];
    if (!table) {
        NSString *p = [self pathForResource:tableName ofType:@"strings"];
        NSData *d = p ? [NSData dataWithContentsOfFile:p] : nil;
        table = d ? FParsePlist(d, NSPropertyListImmutable, NULL) : nil;
        if (![table isKindOfClass:[NSDictionary class]])
            table = [NSDictionary dictionary];
        [_tables setObject:table forKey:tableName];
    }
    NSString *s = key ? [table objectForKey:key] : nil;
    if (s)
        return s;
    return [value length] ? value : key;
}
- (BOOL)load { return YES; }
- (BOOL)isLoaded { return YES; }
@end

/* ---- NSUserDefaults --------------------------------------------------------------------- */

NSNotificationName const NSUserDefaultsDidChangeNotification = @"NSUserDefaultsDidChangeNotification";
static NSUserDefaults *standard_defaults;

@implementation NSUserDefaults {
    NSString *_domain, *_file;
    NSMutableDictionary *_values, *_registered;
    NSDictionary *_arguments;
}
+ (NSUserDefaults *)standardUserDefaults
{
    if (!standard_defaults)
        standard_defaults = [[NSUserDefaults alloc] initWithSuiteName:nil];
    return standard_defaults;
}
+ (void)resetStandardUserDefaults
{
    [standard_defaults release];
    standard_defaults = nil;
}
- (instancetype)init { return [self initWithSuiteName:nil]; }
- (instancetype)initWithSuiteName:(NSString *)name
{
    _domain = [(name ?: [[NSBundle mainBundle] bundleIdentifier] ?: [[NSProcessInfo processInfo] processName]) copy];
    NSString *dir = [[FConfigHome() stringByAppendingPathComponent:@"ferry"] stringByAppendingPathComponent:@"preferences"];
    _file = [[dir stringByAppendingPathComponent:[_domain stringByAppendingPathExtension:@"plist"]] copy];
    NSDictionary *saved = [NSDictionary dictionaryWithContentsOfFile:_file];
    _values = saved ? [saved mutableCopy] : [[NSMutableDictionary alloc] init];
    _registered = [[NSMutableDictionary alloc] init];
    /* "-Key value" on the command line overrides a default, as on a Mac. */
    NSMutableDictionary *args = [NSMutableDictionary dictionary];
    NSArray *argv = [[NSProcessInfo processInfo] arguments];
    for (NSUInteger i = 1; i + 1 < [argv count]; i++) {
        NSString *a = [argv objectAtIndex:i];
        if ([a length] > 1 && [a hasPrefix:@"-"] && ![a hasPrefix:@"--"]) {
            NSString *v = [argv objectAtIndex:++i];
            id parsed = FParsePlist([v dataUsingEncoding:NSUTF8StringEncoding], NSPropertyListImmutable, NULL);
            [args setObject:parsed && ![parsed isKindOfClass:[NSString class]] ? parsed : v
                     forKey:[a substringFromIndex:1]];
        }
    }
    _arguments = [args copy];
    return self;
}
- (void)dealloc
{
    [_domain release];
    [_file release];
    [_values release];
    [_registered release];
    [_arguments release];
    [super dealloc];
}
/* Key-value coding on the defaults reads and writes the defaults themselves. */
- (id)valueForKey:(NSString *)key { return [self objectForKey:key]; }
- (void)setValue:(id)value forKey:(NSString *)key
{
    if (value)
        [self setObject:value forKey:key];
    else
        [self removeObjectForKey:key];
}
- (id)objectForKey:(NSString *)key
{
    return [_arguments objectForKey:key] ?: [_values objectForKey:key] ?: [_registered objectForKey:key];
}
- (BOOL)save
{
    NSString *dir = [_file stringByDeletingLastPathComponent];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL];
    NSData *d = FWriteXMLPlist(_values);
    return d && [d writeToFile:_file atomically:YES];
}
- (void)setObject:(id)value forKey:(NSString *)key
{
    if (!value) {
        [self removeObjectForKey:key];
        return;
    }
    if (![NSPropertyListSerialization propertyList:value isValidForFormat:NSPropertyListXMLFormat_v1_0])
        FRaise(NSInvalidArgumentException, @"Attempt to insert non-property list object %@ for key %@", value, key);
    id copy = [value copy];
    [self willChangeValueForKey:key];
    [_values setObject:copy forKey:key];
    [copy release];
    [self save];
    [self didChangeValueForKey:key];
    [[NSNotificationCenter defaultCenter] postNotificationName:NSUserDefaultsDidChangeNotification object:self];
}
- (void)removeObjectForKey:(NSString *)key
{
    [self willChangeValueForKey:key];
    [_values removeObjectForKey:key];
    [self save];
    [self didChangeValueForKey:key];
    [[NSNotificationCenter defaultCenter] postNotificationName:NSUserDefaultsDidChangeNotification object:self];
}
/* A default's observers hear of its changes from setObject:forKey: and
 * removeObjectForKey:, which announce them themselves. */
+ (BOOL)automaticallyNotifiesObserversForKey:(NSString *)key { return NO; }
- (NSString *)stringForKey:(NSString *)key
{
    id v = [self objectForKey:key];
    if ([v isKindOfClass:[NSString class]])
        return v;
    if ([v isKindOfClass:[NSNumber class]])
        return [v stringValue];
    return nil;
}
- (NSArray *)arrayForKey:(NSString *)key
{
    id v = [self objectForKey:key];
    return [v isKindOfClass:[NSArray class]] ? v : nil;
}
- (NSDictionary *)dictionaryForKey:(NSString *)key
{
    id v = [self objectForKey:key];
    return [v isKindOfClass:[NSDictionary class]] ? v : nil;
}
- (NSData *)dataForKey:(NSString *)key
{
    id v = [self objectForKey:key];
    return [v isKindOfClass:[NSData class]] ? v : nil;
}
- (NSArray *)stringArrayForKey:(NSString *)key
{
    NSArray *a = [self arrayForKey:key];
    for (id o in a)
        if (![o isKindOfClass:[NSString class]])
            return nil;
    return a;
}
- (NSInteger)integerForKey:(NSString *)key
{
    id v = [self objectForKey:key];
    return [v respondsToSelector:@selector(integerValue)] ? [v integerValue] : 0;
}
- (float)floatForKey:(NSString *)key { return (float)[self doubleForKey:key]; }
- (double)doubleForKey:(NSString *)key
{
    id v = [self objectForKey:key];
    return [v respondsToSelector:@selector(doubleValue)] ? [v doubleValue] : 0;
}
- (BOOL)boolForKey:(NSString *)key
{
    id v = [self objectForKey:key];
    if ([v isKindOfClass:[NSString class]])
        return [v caseInsensitiveCompare:@"YES"] == NSOrderedSame || [v caseInsensitiveCompare:@"true"] == NSOrderedSame ||
               [v integerValue] != 0;
    return [v respondsToSelector:@selector(boolValue)] ? [v boolValue] : NO;
}
- (NSURL *)URLForKey:(NSString *)key
{
    id v = [self objectForKey:key];
    if ([v isKindOfClass:[NSString class]])
        return [v hasPrefix:@"/"] ? [NSURL fileURLWithPath:v] : [NSURL URLWithString:v];
    return nil;
}
- (void)setInteger:(NSInteger)value forKey:(NSString *)key { [self setObject:[NSNumber numberWithInteger:value] forKey:key]; }
- (void)setFloat:(float)value forKey:(NSString *)key { [self setObject:[NSNumber numberWithFloat:value] forKey:key]; }
- (void)setDouble:(double)value forKey:(NSString *)key { [self setObject:[NSNumber numberWithDouble:value] forKey:key]; }
- (void)setBool:(BOOL)value forKey:(NSString *)key { [self setObject:[NSNumber numberWithBool:value] forKey:key]; }
- (void)setURL:(NSURL *)url forKey:(NSString *)key
{
    [self setObject:[url isFileURL] ? [url path] : [url absoluteString] forKey:key];
}
- (void)registerDefaults:(NSDictionary *)defaults { [_registered addEntriesFromDictionary:defaults]; }
- (NSDictionary *)dictionaryRepresentation
{
    NSMutableDictionary *d = [NSMutableDictionary dictionaryWithDictionary:_registered];
    [d addEntriesFromDictionary:_values];
    [d addEntriesFromDictionary:_arguments];
    return d;
}
- (NSDictionary *)persistentDomainForName:(NSString *)name
{
    return [name isEqualToString:_domain] ? [NSDictionary dictionaryWithDictionary:_values] : nil;
}
- (void)removePersistentDomainForName:(NSString *)name
{
    if ([name isEqualToString:_domain]) {
        [_values removeAllObjects];
        [self save];
    }
}
- (BOOL)synchronize { return YES; }
- (NSString *)_ferryDomain { return _domain; }
@end

/* ---- NSFileManager ------------------------------------------------------------------------ */

@implementation NSFileManager
+ (NSFileManager *)defaultManager
{
    static NSFileManager *shared;
    if (!shared)
        shared = [[NSFileManager alloc] init];
    return shared;
}
- (NSString *)currentDirectoryPath
{
    char buf[4096];
    return getcwd(buf, sizeof buf) ? [NSString stringWithUTF8String:buf] : nil;
}
- (BOOL)changeCurrentDirectoryPath:(NSString *)path { return chdir([path fileSystemRepresentation]) == 0; }
- (NSURL *)homeDirectoryForCurrentUser { return [NSURL fileURLWithPath:FHome() isDirectory:YES]; }
- (NSURL *)temporaryDirectory { return [NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES]; }
- (BOOL)fileExistsAtPath:(NSString *)path { return [self fileExistsAtPath:path isDirectory:NULL]; }
- (BOOL)fileExistsAtPath:(NSString *)path isDirectory:(BOOL *)isDirectory
{
    struct stat st;
    if (!path || stat([path fileSystemRepresentation], &st) != 0)
        return NO;
    if (isDirectory)
        *isDirectory = S_ISDIR(st.st_mode);
    return YES;
}
- (BOOL)isReadableFileAtPath:(NSString *)path { return access([path fileSystemRepresentation], R_OK) == 0; }
- (BOOL)isWritableFileAtPath:(NSString *)path { return access([path fileSystemRepresentation], W_OK) == 0; }
- (BOOL)isExecutableFileAtPath:(NSString *)path { return access([path fileSystemRepresentation], X_OK) == 0; }
- (BOOL)isDeletableFileAtPath:(NSString *)path
{
    return access([[path stringByDeletingLastPathComponent] fileSystemRepresentation], W_OK) == 0;
}
- (BOOL)createDirectoryAtPath:(NSString *)path withIntermediateDirectories:(BOOL)create attributes:(NSDictionary *)attributes
                        error:(NSError **)error
{
    BOOL dir = NO;
    if (create && [self fileExistsAtPath:path isDirectory:&dir] && dir)
        return YES;
    if (create) {
        NSString *parent = [path stringByDeletingLastPathComponent];
        if ([parent length] && ![parent isEqualToString:path] && ![self fileExistsAtPath:parent] &&
            ![self createDirectoryAtPath:parent withIntermediateDirectories:YES attributes:attributes error:error])
            return NO;
    }
    mode_t mode = 0777;
    if ([attributes objectForKey:NSFilePosixPermissions])
        mode = (mode_t)[[attributes objectForKey:NSFilePosixPermissions] unsignedIntValue];
    if (mkdir([path fileSystemRepresentation], mode) != 0) {
        if (create && errno == EEXIST && [self fileExistsAtPath:path isDirectory:&dir] && dir)
            return YES;
        FSetError(error, FPosixError(errno, path));
        return NO;
    }
    return YES;
}
- (BOOL)createDirectoryAtURL:(NSURL *)url withIntermediateDirectories:(BOOL)create attributes:(NSDictionary *)attributes
                       error:(NSError **)error
{
    return [self createDirectoryAtPath:[url path] withIntermediateDirectories:create attributes:attributes error:error];
}
- (BOOL)createFileAtPath:(NSString *)path contents:(NSData *)data attributes:(NSDictionary *)attr
{
    return [data ?: [NSData data] writeToFile:path atomically:YES];
}
- (NSData *)contentsAtPath:(NSString *)path { return [NSData dataWithContentsOfFile:path]; }
- (BOOL)contentsEqualAtPath:(NSString *)a andPath:(NSString *)b
{
    NSData *x = [NSData dataWithContentsOfFile:a], *y = [NSData dataWithContentsOfFile:b];
    return x && y && [x isEqualToData:y];
}
- (NSArray *)contentsOfDirectoryAtPath:(NSString *)path error:(NSError **)error
{
    DIR *d = opendir([path fileSystemRepresentation]);
    if (!d) {
        FSetError(error, FPosixError(errno, path));
        return nil;
    }
    NSMutableArray *names = [NSMutableArray array];
    struct dirent *e;
    while ((e = readdir(d))) {
        if (!strcmp(e->d_name, ".") || !strcmp(e->d_name, ".."))
            continue;
        [names addObject:[NSString stringWithUTF8String:e->d_name]];
    }
    closedir(d);
    [names sortUsingSelector:@selector(compare:)];
    return names;
}
- (NSArray *)contentsOfDirectoryAtURL:(NSURL *)url includingPropertiesForKeys:(NSArray *)keys options:(NSUInteger)mask
                                error:(NSError **)error
{
    NSArray *names = [self contentsOfDirectoryAtPath:[url path] error:error];
    if (!names)
        return nil;
    NSMutableArray *urls = [NSMutableArray array];
    for (NSString *n in names) {
        if ((mask & 4) && [n hasPrefix:@"."]) /* NSDirectoryEnumerationSkipsHiddenFiles */
            continue;
        [urls addObject:[url URLByAppendingPathComponent:n]];
    }
    return urls;
}
- (void)collect:(NSString *)base prefix:(NSString *)prefix into:(NSMutableArray *)out
{
    for (NSString *n in [self contentsOfDirectoryAtPath:base error:NULL]) {
        NSString *rel = prefix ? [prefix stringByAppendingPathComponent:n] : n;
        [out addObject:rel];
        struct stat st;
        NSString *full = [base stringByAppendingPathComponent:n];
        if (lstat([full fileSystemRepresentation], &st) == 0 && S_ISDIR(st.st_mode))
            [self collect:full prefix:rel into:out];
    }
}
- (NSArray *)subpathsOfDirectoryAtPath:(NSString *)path error:(NSError **)error
{
    BOOL dir = NO;
    if (![self fileExistsAtPath:path isDirectory:&dir] || !dir) {
        FSetError(error, FPosixError(dir ? ENOTDIR : ENOENT, path));
        return nil;
    }
    NSMutableArray *out = [NSMutableArray array];
    [self collect:path prefix:nil into:out];
    return out;
}
- (NSArray *)subpathsAtPath:(NSString *)path { return [self subpathsOfDirectoryAtPath:path error:NULL]; }
- (BOOL)removeItemAtPath:(NSString *)path error:(NSError **)error
{
    struct stat st;
    const char *fs = [path fileSystemRepresentation];
    if (lstat(fs, &st) != 0) {
        FSetError(error, FPosixError(errno, path));
        return NO;
    }
    if (S_ISDIR(st.st_mode)) {
        for (NSString *n in [self contentsOfDirectoryAtPath:path error:NULL])
            if (![self removeItemAtPath:[path stringByAppendingPathComponent:n] error:error])
                return NO;
        if (rmdir(fs) != 0) {
            FSetError(error, FPosixError(errno, path));
            return NO;
        }
        return YES;
    }
    if (unlink(fs) != 0) {
        FSetError(error, FPosixError(errno, path));
        return NO;
    }
    return YES;
}
- (BOOL)removeItemAtURL:(NSURL *)url error:(NSError **)error { return [self removeItemAtPath:[url path] error:error]; }
- (BOOL)copyItemAtPath:(NSString *)src toPath:(NSString *)dst error:(NSError **)error
{
    struct stat st;
    if (lstat([src fileSystemRepresentation], &st) != 0) {
        FSetError(error, FPosixError(errno, src));
        return NO;
    }
    if (lstat([dst fileSystemRepresentation], &(struct stat){0}) == 0) {
        FSetError(error, FPosixError(EEXIST, dst));
        return NO;
    }
    if (S_ISLNK(st.st_mode)) {
        char target[4096];
        ssize_t n = readlink([src fileSystemRepresentation], target, sizeof target - 1);
        if (n < 0 || (target[n] = 0, symlink(target, [dst fileSystemRepresentation])) != 0) {
            FSetError(error, FPosixError(errno, dst));
            return NO;
        }
        return YES;
    }
    if (S_ISDIR(st.st_mode)) {
        if (mkdir([dst fileSystemRepresentation], st.st_mode & 07777) != 0) {
            FSetError(error, FPosixError(errno, dst));
            return NO;
        }
        for (NSString *n in [self contentsOfDirectoryAtPath:src error:NULL])
            if (![self copyItemAtPath:[src stringByAppendingPathComponent:n]
                               toPath:[dst stringByAppendingPathComponent:n]
                                error:error])
                return NO;
        return YES;
    }
    NSData *d = [NSData dataWithContentsOfFile:src];
    if (!d || ![d writeToFile:dst options:0 error:error]) {
        if (!d)
            FSetError(error, FPosixError(errno, src));
        return NO;
    }
    chmod([dst fileSystemRepresentation], st.st_mode & 07777);
    return YES;
}
- (BOOL)moveItemAtPath:(NSString *)src toPath:(NSString *)dst error:(NSError **)error
{
    if (lstat([dst fileSystemRepresentation], &(struct stat){0}) == 0) {
        FSetError(error, FPosixError(EEXIST, dst));
        return NO;
    }
    if (rename([src fileSystemRepresentation], [dst fileSystemRepresentation]) == 0)
        return YES;
    if (errno != EXDEV) {
        FSetError(error, FPosixError(errno, src));
        return NO;
    }
    return [self copyItemAtPath:src toPath:dst error:error] && [self removeItemAtPath:src error:error];
}
- (BOOL)copyItemAtURL:(NSURL *)src toURL:(NSURL *)dst error:(NSError **)error
{
    return [self copyItemAtPath:[src path] toPath:[dst path] error:error];
}
- (BOOL)moveItemAtURL:(NSURL *)src toURL:(NSURL *)dst error:(NSError **)error
{
    return [self moveItemAtPath:[src path] toPath:[dst path] error:error];
}
- (BOOL)createSymbolicLinkAtPath:(NSString *)path withDestinationPath:(NSString *)dest error:(NSError **)error
{
    if (symlink([dest fileSystemRepresentation], [path fileSystemRepresentation]) != 0) {
        FSetError(error, FPosixError(errno, path));
        return NO;
    }
    return YES;
}
- (NSString *)destinationOfSymbolicLinkAtPath:(NSString *)path error:(NSError **)error
{
    char buf[4096];
    ssize_t n = readlink([path fileSystemRepresentation], buf, sizeof buf - 1);
    if (n < 0) {
        FSetError(error, FPosixError(errno, path));
        return nil;
    }
    return FStringFromUTF8(buf, n);
}
- (NSDictionary *)attributesOfItemAtPath:(NSString *)path error:(NSError **)error
{
    struct stat st;
    if (lstat([path fileSystemRepresentation], &st) != 0) {
        FSetError(error, FPosixError(errno, path));
        return nil;
    }
    NSString *type = S_ISDIR(st.st_mode) ? NSFileTypeDirectory : S_ISLNK(st.st_mode) ? NSFileTypeSymbolicLink
                                                                                    : NSFileTypeRegular;
    NSDate *mod = [NSDate dateWithTimeIntervalSince1970:st.st_mtimespec.tv_sec + st.st_mtimespec.tv_nsec / 1e9];
    return [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithUnsignedLongLong:(unsigned long long)st.st_size],
                                                      NSFileSize, type, NSFileType, mod, NSFileModificationDate,
                                                      [NSNumber numberWithUnsignedShort:st.st_mode & 07777],
                                                      NSFilePosixPermissions, nil];
}
- (NSArray *)URLsForDirectory:(NSSearchPathDirectory)directory inDomains:(NSSearchPathDomainMask)mask
{
    NSString *p = (mask & NSUserDomainMask) ? FUserFolder(directory) : nil;
    return p ? [NSArray arrayWithObject:[NSURL fileURLWithPath:p isDirectory:YES]] : [NSArray array];
}
- (NSURL *)URLForDirectory:(NSSearchPathDirectory)directory inDomain:(NSSearchPathDomainMask)domain
         appropriateForURL:(NSURL *)url create:(BOOL)create error:(NSError **)error
{
    NSURL *u = [[self URLsForDirectory:directory inDomains:domain] firstObject];
    if (u && create && ![self createDirectoryAtURL:u withIntermediateDirectories:YES attributes:nil error:error])
        return nil;
    return u;
}
- (NSString *)stringWithFileSystemRepresentation:(const char *)s length:(NSUInteger)len
{
    return FStringFromUTF8(s, len);
}
- (const char *)fileSystemRepresentationWithPath:(NSString *)path { return [path fileSystemRepresentation]; }
@end
