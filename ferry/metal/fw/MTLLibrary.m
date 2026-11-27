/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's Metal.framework: shader libraries, functions and pipelines.
 * A program hands Metal its shaders as Metal Shading Language source;
 * ferry-mslc (Ferry's shader compiler, a separate program) turns that into
 * a library of ordinary processor code, which is kept in ~/.cache/ferry/metal
 * so the same source compiles once. A pipeline joins a vertex function's
 * results to the fragment function's inputs by name, as the Metal Shading
 * Language specification describes. Written from Apple's public Metal
 * documentation. Built without ARC. */
#import "MTLObjC.h"
#import <objc/runtime.h>
#include <dlfcn.h>
#include <errno.h>
#include <fcntl.h>
#include <spawn.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>

extern char **environ;
id FerryMTLCopyDescriptor(id self, NSZone *zone);
void FerryMTLReleaseIvars(id self);

/* ---- small reflection classes --------------------------------------------------------- */
static MTLDataType data_type_named(NSString *s)
{
    static const struct { const char *name; MTLDataType t; } base[] = {
        {"float", MTLDataTypeFloat}, {"half", MTLDataTypeHalf}, {"int", MTLDataTypeInt}, {"uint", MTLDataTypeUInt},
        {"short", MTLDataTypeShort}, {"ushort", MTLDataTypeUShort}, {"char", MTLDataTypeChar},
        {"uchar", MTLDataTypeUChar}, {"bool", MTLDataTypeBool}, {"long", MTLDataTypeLong},
        {"ulong", MTLDataTypeULong}, {"int32_t", MTLDataTypeInt}, {"uint32_t", MTLDataTypeUInt},
    };
    const char *c = [[s stringByReplacingOccurrencesOfString:@"constant" withString:@""] UTF8String];
    while (*c == ' ') c++;
    for (size_t i = 0; i < sizeof base / sizeof base[0]; i++) {
        size_t n = strlen(base[i].name);
        if (!strncmp(c, base[i].name, n)) {
            int k = c[n] >= '2' && c[n] <= '4' ? c[n] - '1' : 0;
            return base[i].t + (MTLDataType)k;
        }
    }
    return MTLDataTypeNone;
}

@interface MTLFunctionConstant () {
@public
    NSString *_name;
    MTLDataType _type;
    NSUInteger _index;
    BOOL _required;
}
@end
@implementation MTLFunctionConstant
- (void)dealloc { [_name release]; [super dealloc]; }
- (NSString *)name { return _name; }
- (MTLDataType)type { return _type; }
- (NSUInteger)index { return _index; }
- (BOOL)required { return _required; }
@end

@interface MTLVertexAttribute () {
@public
    NSString *_name;
    NSUInteger _attributeIndex;
    MTLDataType _attributeType;
}
@end
@implementation MTLVertexAttribute
- (void)dealloc { [_name release]; [super dealloc]; }
- (NSString *)name { return _name; }
- (NSUInteger)attributeIndex { return _attributeIndex; }
- (MTLDataType)attributeType { return _attributeType; }
- (BOOL)isActive { return YES; }
@end
@interface MTLAttribute () {
@public
    NSString *_name;
    NSUInteger _attributeIndex;
    MTLDataType _attributeType;
}
@end
@implementation MTLAttribute
- (void)dealloc { [_name release]; [super dealloc]; }
- (NSString *)name { return _name; }
- (NSUInteger)attributeIndex { return _attributeIndex; }
- (MTLDataType)attributeType { return _attributeType; }
- (BOOL)isActive { return YES; }
@end

@implementation MTLType
- (MTLDataType)dataType { return MTLDataTypeNone; }
@end
@implementation MTLStructMember
- (NSString *)name { return @""; }
- (NSUInteger)offset { return 0; }
- (MTLDataType)dataType { return MTLDataTypeNone; }
- (NSUInteger)argumentIndex { return 0; }
- (MTLStructType *)structType { return nil; }
- (MTLArrayType *)arrayType { return nil; }
@end
@implementation MTLStructType
- (MTLDataType)dataType { return MTLDataTypeStruct; }
- (NSArray *)members { return @[]; }
- (MTLStructMember *)memberByName:(NSString *)name { return nil; }
@end
@implementation MTLArrayType
- (MTLDataType)dataType { return MTLDataTypeArray; }
- (MTLDataType)elementType { return MTLDataTypeNone; }
- (NSUInteger)arrayLength { return 0; }
- (NSUInteger)stride { return 0; }
- (NSUInteger)argumentIndexStride { return 0; }
- (MTLStructType *)elementStructType { return nil; }
- (MTLArrayType *)elementArrayType { return nil; }
@end
@implementation MTLPointerType
- (MTLDataType)dataType { return MTLDataTypePointer; }
- (MTLDataType)elementType { return MTLDataTypeNone; }
- (MTLArgumentAccess)access { return MTLArgumentAccessReadWrite; }
- (NSUInteger)alignment { return 16; }
- (NSUInteger)dataSize { return 0; }
- (BOOL)elementIsArgumentBuffer { return NO; }
@end

@interface MTLArgument () {
@public
    NSString *_name;
    MTLArgumentType _type;
    NSUInteger _index;
}
@end
@implementation MTLArgument
- (void)dealloc { [_name release]; [super dealloc]; }
- (NSString *)name { return _name; }
- (MTLArgumentType)type { return _type; }
- (MTLArgumentAccess)access { return MTLArgumentAccessReadWrite; }
- (NSUInteger)index { return _index; }
- (BOOL)isActive { return YES; }
- (BOOL)isUsed { return YES; }
- (BOOL)isArgument { return NO; }
- (NSUInteger)bufferAlignment { return 16; }
- (NSUInteger)bufferDataSize { return 0; }
- (MTLDataType)bufferDataType { return MTLDataTypeNone; }
- (MTLStructType *)bufferStructType { return nil; }
- (MTLPointerType *)bufferPointerType { return nil; }
- (NSUInteger)threadgroupMemoryAlignment { return 16; }
- (NSUInteger)threadgroupMemoryDataSize { return 0; }
- (MTLTextureType)textureType { return MTLTextureType2D; }
- (MTLDataType)textureDataType { return MTLDataTypeFloat; }
- (BOOL)isDepthTexture { return NO; }
- (NSUInteger)arrayLength { return 1; }
@end

/* The arguments a function's reflection lists, as MTLArgument objects. */
static NSArray *arguments_of(NSDictionary *info)
{
    NSMutableArray *out = [NSMutableArray array];
    static NSString *const keys[4] = {@"buffers", @"threadgroup", @"textures", @"samplers"};
    static const MTLArgumentType types[4] = {MTLArgumentTypeBuffer, MTLArgumentTypeThreadgroupMemory,
                                             MTLArgumentTypeTexture, MTLArgumentTypeSampler};
    for (int k = 0; k < 4; k++)
        for (NSDictionary *b in info[keys[k]]) {
            MTLArgument *a = [[MTLArgument alloc] init];
            a->_name = [b[@"name"] copy];
            a->_type = types[k];
            id index = b[@"index"]; /* null: set by a function constant not yet given */
            a->_index = [index isKindOfClass:[NSNumber class]] ? [index unsignedIntegerValue] : 0;
            [out addObject:a];
            [a release];
        }
    return out;
}

@interface MTLRenderPipelineReflection () {
@public
    NSArray *_vertexArguments, *_fragmentArguments;
}
@end
@implementation MTLRenderPipelineReflection
- (void)dealloc { [_vertexArguments release]; [_fragmentArguments release]; [super dealloc]; }
- (NSArray *)vertexArguments { return _vertexArguments; }
- (NSArray *)fragmentArguments { return _fragmentArguments; }
- (NSArray *)tileArguments { return @[]; }
- (NSArray *)vertexBindings { return _vertexArguments; }
- (NSArray *)fragmentBindings { return _fragmentArguments; }
@end
@interface MTLComputePipelineReflection () {
@public
    NSArray *_arguments;
}
@end
@implementation MTLComputePipelineReflection
- (void)dealloc { [_arguments release]; [super dealloc]; }
- (NSArray *)arguments { return _arguments; }
- (NSArray *)bindings { return _arguments; }
@end

/* ---- compile options and function constants ------------------------------------------- */
@implementation MTLCompileOptions
@synthesize preprocessorMacros = _preprocessorMacros, fastMathEnabled = _fastMathEnabled, mathMode = _mathMode,
            mathFloatingPointFunctions = _mathFloatingPointFunctions, languageVersion = _languageVersion,
            libraryType = _libraryType, installName = _installName, libraries = _libraries,
            preserveInvariance = _preserveInvariance, optimizationLevel = _optimizationLevel,
            compileSymbolVisibility = _compileSymbolVisibility,
            allowReferencingUndefinedSymbols = _allowReferencingUndefinedSymbols,
            maxTotalThreadsPerThreadgroup = _maxTotalThreadsPerThreadgroup, enableLogging = _enableLogging;
- (instancetype)init
{
    if ((self = [super init])) {
        _fastMathEnabled = YES;
        _mathMode = MTLMathModeFast;
        _languageVersion = MTLLanguageVersion3_0;
    }
    return self;
}
- (void)dealloc { FerryMTLReleaseIvars(self); [super dealloc]; }
- (id)copyWithZone:(NSZone *)zone { return FerryMTLCopyDescriptor(self, zone); }
@end

/* A constant's value as an expression of its own type, for ferry-mslc. */
static NSString *constant_literal(const void *p, MTLDataType type)
{
    MTLDataType base;
    int n;
    if (type >= MTLDataTypeFloat && type <= MTLDataTypeFloat4) { base = MTLDataTypeFloat; n = (int)(type - base) + 1; }
    else if (type >= MTLDataTypeHalf && type <= MTLDataTypeHalf4) { base = MTLDataTypeHalf; n = (int)(type - base) + 1; }
    else if (type >= MTLDataTypeInt && type <= MTLDataTypeBool4) { base = MTLDataTypeInt + (type - MTLDataTypeInt) / 4 * 4; n = (int)(type - base) + 1; }
    else if (type >= MTLDataTypeLong && type <= MTLDataTypeULong4) { base = MTLDataTypeLong + (type - MTLDataTypeLong) / 4 * 4; n = (int)(type - base) + 1; }
    else return nil;
    const char *tname;
    switch (base) {
    case MTLDataTypeFloat: tname = "float"; break;
    case MTLDataTypeHalf: tname = "half"; break;
    case MTLDataTypeInt: tname = "int"; break;
    case MTLDataTypeUInt: tname = "uint"; break;
    case MTLDataTypeShort: tname = "short"; break;
    case MTLDataTypeUShort: tname = "ushort"; break;
    case MTLDataTypeChar: tname = "char"; break;
    case MTLDataTypeUChar: tname = "uchar"; break;
    case MTLDataTypeBool: tname = "bool"; break;
    case MTLDataTypeLong: tname = "long"; break;
    default: tname = "ulong"; break;
    }
    NSMutableArray *parts = [NSMutableArray array];
    const unsigned char *b = p;
    for (int i = 0; i < n; i++) {
        switch (base) {
        case MTLDataTypeFloat: { float f; memcpy(&f, b + 4 * i, 4); [parts addObject:[NSString stringWithFormat:@"%.9g", f]]; break; }
        case MTLDataTypeHalf: { uint16_t h; memcpy(&h, b + 2 * i, 2); [parts addObject:[NSString stringWithFormat:@"%.9g", mtl_half_to_float(h)]]; break; }
        case MTLDataTypeInt: { int32_t v; memcpy(&v, b + 4 * i, 4); [parts addObject:[NSString stringWithFormat:@"%d", v]]; break; }
        case MTLDataTypeUInt: { uint32_t v; memcpy(&v, b + 4 * i, 4); [parts addObject:[NSString stringWithFormat:@"%uu", v]]; break; }
        case MTLDataTypeShort: { int16_t v; memcpy(&v, b + 2 * i, 2); [parts addObject:[NSString stringWithFormat:@"%d", v]]; break; }
        case MTLDataTypeUShort: { uint16_t v; memcpy(&v, b + 2 * i, 2); [parts addObject:[NSString stringWithFormat:@"%u", v]]; break; }
        case MTLDataTypeChar: [parts addObject:[NSString stringWithFormat:@"%d", (signed char)b[i]]]; break;
        case MTLDataTypeUChar: [parts addObject:[NSString stringWithFormat:@"%u", b[i]]]; break;
        case MTLDataTypeBool: [parts addObject:b[i] ? @"true" : @"false"]; break;
        case MTLDataTypeLong: { int64_t v; memcpy(&v, b + 8 * i, 8); [parts addObject:[NSString stringWithFormat:@"%lldll", (long long)v]]; break; }
        default: { uint64_t v; memcpy(&v, b + 8 * i, 8); [parts addObject:[NSString stringWithFormat:@"%llullu", (unsigned long long)v]]; break; }
        }
    }
    if (n == 1) return parts[0];
    return [NSString stringWithFormat:@"%s%d(%@)", tname, n, [parts componentsJoinedByString:@", "]];
}
static NSUInteger data_type_size(MTLDataType t)
{
    if (t >= MTLDataTypeFloat && t <= MTLDataTypeFloat4) return 4 * (t - MTLDataTypeFloat + 1);
    if (t >= MTLDataTypeHalf && t <= MTLDataTypeHalf4) return 2 * (t - MTLDataTypeHalf + 1);
    if (t >= MTLDataTypeInt && t <= MTLDataTypeUInt4) return 4 * ((t - MTLDataTypeInt) % 4 + 1);
    if (t >= MTLDataTypeShort && t <= MTLDataTypeUShort4) return 2 * ((t - MTLDataTypeShort) % 4 + 1);
    if (t >= MTLDataTypeChar && t <= MTLDataTypeBool4) return (t - MTLDataTypeChar) % 4 + 1;
    if (t >= MTLDataTypeLong && t <= MTLDataTypeULong4) return 8 * ((t - MTLDataTypeLong) % 4 + 1);
    return 4;
}

@implementation MTLFunctionConstantValues
- (instancetype)init
{
    if ((self = [super init])) {
        _byIndex = [[NSMutableDictionary alloc] init];
        _byName = [[NSMutableDictionary alloc] init];
    }
    return self;
}
- (void)dealloc { [_byIndex release]; [_byName release]; [super dealloc]; }
- (id)copyWithZone:(NSZone *)zone
{
    MTLFunctionConstantValues *c = [[MTLFunctionConstantValues allocWithZone:zone] init];
    [c->_byIndex addEntriesFromDictionary:_byIndex];
    [c->_byName addEntriesFromDictionary:_byName];
    return c;
}
- (void)setConstantValue:(const void *)value type:(MTLDataType)type atIndex:(NSUInteger)index
{
    NSString *lit = constant_literal(value, type);
    if (lit) _byIndex[@(index)] = lit;
    else mtl_log("a function constant of type %lu isn't done yet", (unsigned long)type);
}
- (void)setConstantValues:(const void *)values type:(MTLDataType)type withRange:(NSRange)range
{
    NSUInteger size = data_type_size(type);
    for (NSUInteger i = 0; i < range.length; i++)
        [self setConstantValue:(const char *)values + i * size type:type atIndex:range.location + i];
}
- (void)setConstantValue:(const void *)value type:(MTLDataType)type withName:(NSString *)name
{
    NSString *lit = constant_literal(value, type);
    if (lit && name) _byName[name] = lit;
}
- (void)reset
{
    [_byIndex removeAllObjects];
    [_byName removeAllObjects];
}
/* ferry-mslc's arguments for these values, in a fixed order */
- (NSArray *)ferryArguments
{
    NSMutableArray *a = [NSMutableArray array];
    for (NSNumber *k in [[_byIndex allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
        [a addObject:@"--fc"];
        [a addObject:[NSString stringWithFormat:@"%@=%@", k, _byIndex[k]]];
    }
    for (NSString *k in [[_byName allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
        [a addObject:@"--fcname"];
        [a addObject:[NSString stringWithFormat:@"%@=%@", k, _byName[k]]];
    }
    return a;
}
@end

@implementation MTLFunctionDescriptor
@synthesize name = _name, specializedName = _specializedName, constantValues = _constantValues, options = _options;
+ (MTLFunctionDescriptor *)functionDescriptor { return [[[self alloc] init] autorelease]; }
- (void)dealloc { FerryMTLReleaseIvars(self); [super dealloc]; }
- (id)copyWithZone:(NSZone *)zone { return FerryMTLCopyDescriptor(self, zone); }
@end

/* ---- compiling ----------------------------------------------------------------------------- */
static NSString *find_mslc(void)
{
    NSMutableArray *c = [NSMutableArray array];
    const char *e = getenv("FERRY_MSLC");
    if (e && *e) [c addObject:@(e)];
    const char *fw = getenv("FERRY_FRAMEWORKS");
    if (fw && *fw) {
        [c addObject:[NSString stringWithFormat:@"%s/../metal/ferry-mslc", fw]];
        [c addObject:[NSString stringWithFormat:@"%s/../../metal/ferry-mslc", fw]];
    }
    /* next to this framework: frameworks/Metal.framework/Metal -> ../metal */
    Dl_info di;
    if (dladdr((const void *)find_mslc, &di) && di.dli_fname) {
        NSString *me = [@(di.dli_fname) stringByDeletingLastPathComponent];
        [c addObject:[me stringByAppendingPathComponent:@"../../metal/ferry-mslc"]];
        [c addObject:[me stringByAppendingPathComponent:@"../../../metal/ferry-mslc"]];
    }
    [c addObject:@"/usr/lib/ferry/metal/ferry-mslc"];
    [c addObject:@"/usr/local/lib/ferry/metal/ferry-mslc"];
    for (NSString *p in c)
        if (access([p fileSystemRepresentation], X_OK) == 0) return [p stringByStandardizingPath];
    return nil;
}

static NSString *cache_dir(void)
{
    const char *x = getenv("XDG_CACHE_HOME"), *h = getenv("HOME");
    NSString *d = x && *x ? [NSString stringWithFormat:@"%s/ferry/metal", x]
                 : [NSString stringWithFormat:@"%s/.cache/ferry/metal", h && *h ? h : "/tmp"];
    [[NSFileManager defaultManager] createDirectoryAtPath:d withIntermediateDirectories:YES attributes:nil error:NULL];
    return d;
}

static void fnv(uint64_t *h, const void *p, size_t n)
{
    const unsigned char *b = p;
    for (size_t i = 0; i < n; i++) { *h ^= b[i]; *h *= 0x100000001b3ull; }
}

static NSString *read_text(NSString *path, NSUInteger max)
{
    NSData *d = [NSData dataWithContentsOfFile:path];
    if (!d) return @"";
    if ([d length] > max) d = [d subdataWithRange:NSMakeRange(0, max)];
    NSString *s = [[[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] autorelease];
    return s ? s : @"";
}

/* Build source (with ferry-mslc's extra arguments) into a library in the
 * cache, or find it there; answers the library's path. */
static NSString *compile(NSString *source, MTLCompileOptions *options, NSArray *extra, NSError **error)
{
    NSString *mslc = find_mslc();
    if (!mslc) {
        mtl_log("Ferry's Metal shader compiler (ferry-mslc) isn't installed");
        if (error)
            *error = FerryMTLError(MTLLibraryErrorDomain, MTLLibraryErrorInternal,
                                   @"Ferry's Metal shader compiler (ferry-mslc) isn't installed");
        return nil;
    }
    NSMutableArray *args = [NSMutableArray array];
    for (NSString *k in [[options.preprocessorMacros allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
        id v = options.preprocessorMacros[k];
        [args addObject:@"-D"];
        [args addObject:[NSString stringWithFormat:@"%@=%@", k, [v description]]];
    }
    [args addObjectsFromArray:extra];
    uint64_t h = 0xcbf29ce484222325ull;
    fnv(&h, "ferry-metal-1", 14);
    struct stat st;
    if (stat([mslc fileSystemRepresentation], &st) == 0) {
        fnv(&h, &st.st_mtime, sizeof st.st_mtime);
        fnv(&h, &st.st_size, sizeof st.st_size);
    }
    const char *src = [source UTF8String];
    fnv(&h, src, strlen(src) + 1);
    for (NSString *a in args) {
        const char *s = [a UTF8String];
        fnv(&h, s, strlen(s) + 1);
    }
    NSString *dir = cache_dir();
    NSString *lib = [dir stringByAppendingPathComponent:[NSString stringWithFormat:@"%016llx.dylib", (unsigned long long)h]];
    NSString *json = [lib stringByAppendingString:@".json"];
    NSFileManager *fm = [NSFileManager defaultManager];
    if ([fm fileExistsAtPath:lib] && [fm fileExistsAtPath:json]) return lib;

    NSString *tag = [NSString stringWithFormat:@"%016llx.%d.%p", (unsigned long long)h, getpid(), (void *)&h];
    NSString *srcPath = [dir stringByAppendingPathComponent:[tag stringByAppendingString:@".metal"]];
    NSString *tmpLib = [dir stringByAppendingPathComponent:[tag stringByAppendingString:@".dylib"]];
    NSString *logPath = [dir stringByAppendingPathComponent:[tag stringByAppendingString:@".log"]];
    [[source dataUsingEncoding:NSUTF8StringEncoding] writeToFile:srcPath atomically:NO];

    NSMutableArray *argv = [NSMutableArray arrayWithObjects:mslc, @"build", srcPath, @"-o", tmpLib, nil];
    [argv addObjectsFromArray:args];
    size_t n = [argv count];
    char **av = calloc(n + 1, sizeof(char *));
    for (size_t i = 0; i < n; i++) av[i] = strdup([argv[i] UTF8String]);
    posix_spawn_file_actions_t fa;
    posix_spawn_file_actions_init(&fa);
    posix_spawn_file_actions_addopen(&fa, 1, "/dev/null", O_WRONLY, 0);
    posix_spawn_file_actions_addopen(&fa, 2, [logPath fileSystemRepresentation], O_WRONLY | O_CREAT | O_TRUNC, 0644);
    pid_t pid;
    int rc = posix_spawn(&pid, av[0], &fa, NULL, av, environ);
    posix_spawn_file_actions_destroy(&fa);
    for (size_t i = 0; i < n; i++) free(av[i]);
    free(av);
    int status = -1;
    if (rc == 0)
        while (waitpid(pid, &status, 0) < 0 && errno == EINTR) {}
    NSString *log = read_text(logPath, 16384);
    [fm removeItemAtPath:logPath error:NULL];
    if (rc != 0 || !WIFEXITED(status) || WEXITSTATUS(status) != 0) {
        NSString *keep = [dir stringByAppendingPathComponent:@"last-failed.metal"];
        [fm removeItemAtPath:keep error:NULL];
        [fm moveItemAtPath:srcPath toPath:keep error:NULL];
        [fm removeItemAtPath:tmpLib error:NULL];
        [fm removeItemAtPath:[tmpLib stringByAppendingString:@".json"] error:NULL];
        if (rc != 0) log = [NSString stringWithFormat:@"couldn't run %@: %s", mslc, strerror(rc)];
        mtl_log("a shader didn't compile (its source is in %s):\n%s", [keep fileSystemRepresentation], [log UTF8String]);
        if (error)
            *error = FerryMTLError(MTLLibraryErrorDomain, MTLLibraryErrorCompileFailure, @"Compilation failed: \n\n%@",
                                   log);
        return nil;
    }
    [fm removeItemAtPath:srcPath error:NULL];
    rename([[tmpLib stringByAppendingString:@".json"] fileSystemRepresentation], [json fileSystemRepresentation]);
    rename([tmpLib fileSystemRepresentation], [lib fileSystemRepresentation]);
    if (mtl_verbose && [log length]) mtl_log("%s", [log UTF8String]);
    return lib;
}

static FerryMTLLibrary *load_library(NSString *path, NSError **error)
{
    void *h = dlopen([path fileSystemRepresentation], RTLD_NOW | RTLD_LOCAL);
    if (!h) {
        const char *e = dlerror();
        mtl_log("a compiled shader library didn't load: %s", e ? e : "?");
        if (error)
            *error = FerryMTLError(MTLLibraryErrorDomain, MTLLibraryErrorInternal,
                                   @"the compiled shader library didn't load: %s", e ? e : "?");
        return nil;
    }
    NSData *d = [NSData dataWithContentsOfFile:[path stringByAppendingString:@".json"]];
    NSDictionary *refl = d ? [NSJSONSerialization JSONObjectWithData:d options:0 error:NULL] : nil;
    if (![refl isKindOfClass:[NSDictionary class]]) {
        if (error)
            *error = FerryMTLError(MTLLibraryErrorDomain, MTLLibraryErrorInternal,
                                   @"the compiled shader library has no description");
        return nil;
    }
    FerryMTLLibrary *lib = [[FerryMTLLibrary alloc] init];
    lib->_handle = h;
    lib->_path = [path copy];
    lib->_reflection = [refl retain];
    lib->_specialized = [[NSMutableDictionary alloc] init];
    return lib;
}

id<MTLLibrary> FerryMTLNewLibraryWithSource(NSString *source, MTLCompileOptions *options, NSError **error)
{
    if (error) *error = nil;
    if (!source) {
        if (error) *error = FerryMTLError(MTLLibraryErrorDomain, MTLLibraryErrorCompileFailure, @"no source");
        return nil;
    }
    NSString *path = compile(source, options, @[], error);
    if (!path) return nil;
    FerryMTLLibrary *lib = load_library(path, error);
    if (lib) {
        lib->_source = [source copy];
        lib->_options = [options copy];
    }
    return lib;
}

/* ---- libraries and functions ------------------------------------------------------------- */
static id nonnull(id v) { return v == [NSNull null] ? nil : v; }

static FerryMTLFunction *make_function(FerryMTLLibrary *lib, NSDictionary *info)
{
    NSString *stage = info[@"stage"];
    FerryMTLFunction *f = [[FerryMTLFunction alloc] init];
    f->_library = [lib retain];
    f->_info = [info retain];
    f->_name = [info[@"name"] copy];
    f->_fn.stage = [stage isEqualToString:@"vertex"] ? 1 : [stage isEqualToString:@"fragment"] ? 2 : 3;
    NSString *sym = nonnull(info[@"symbol"]), *inf = nonnull(info[@"info"]);
    void *entry = sym ? dlsym(lib->_handle, [sym UTF8String]) : NULL;
    if (!entry) mtl_log("%s: the compiled shader has no entry point", [f->_name UTF8String]);
    if (f->_fn.stage == 1) f->_fn.vs = entry;
    else if (f->_fn.stage == 2) f->_fn.fs = entry;
    else f->_fn.cs = entry;
    if (inf) {
        int (*fill)(struct ferry_slot *, int) = dlsym(lib->_handle, [inf UTF8String]);
        if (fill) {
            int n = fill(f->_fn.slots.s, 96);
            f->_fn.slots.n = n < 0 ? 0 : n > 96 ? 96 : n;
        }
    }
    NSNumber *mt = nonnull(info[@"max_threads"]);
    f->_fn.max_threads = [mt isKindOfClass:[NSNumber class]] ? [mt unsignedIntValue] : 1024;
    if (!f->_fn.max_threads || f->_fn.max_threads > 1024) f->_fn.max_threads = 1024;
    return f;
}

@implementation FerryMTLLibrary
- (void)dealloc
{
    /* (the shader code stays loaded: a pipeline made from it may outlive us) */
    [_path release];
    [_reflection release];
    [_source release];
    [_options release];
    [_specialized release];
    [super dealloc];
}
- (NSArray *)functionNames
{
    NSMutableArray *a = [NSMutableArray array];
    for (NSDictionary *f in _reflection[@"functions"]) [a addObject:f[@"name"]];
    return a;
}
- (MTLLibraryType)type { return MTLLibraryTypeExecutable; }
- (NSString *)installName { return nil; }
- (NSDictionary *)ferryInfoFor:(NSString *)name
{
    for (NSDictionary *f in _reflection[@"functions"])
        if ([f[@"name"] isEqualToString:name]) return f;
    return nil;
}
- (id<MTLFunction>)newFunctionWithName:(NSString *)name
{
    NSDictionary *info = [self ferryInfoFor:name];
    return info ? make_function(self, info) : nil;
}
- (id<MTLFunction>)newFunctionWithName:(NSString *)name constantValues:(MTLFunctionConstantValues *)values
                                 error:(NSError **)error
{
    if (error) *error = nil;
    if (![self ferryInfoFor:name]) {
        if (error)
            *error = FerryMTLError(MTLLibraryErrorDomain, MTLLibraryErrorFunctionNotFound,
                                   @"Function %@ was not found in the library", name);
        return nil;
    }
    NSArray *extra = [values ferryArguments];
    if (![extra count] || !_source) {
        FerryMTLFunction *f = (FerryMTLFunction *)[self newFunctionWithName:name];
        f->_constants = [values copy];
        return f;
    }
    NSString *key = [extra componentsJoinedByString:@" "];
    FerryMTLLibrary *spec;
    @synchronized(self) { spec = [[_specialized objectForKey:key] retain]; }
    if (!spec) {
        NSString *path = compile(_source, _options, extra, error);
        if (!path) return nil;
        spec = load_library(path, error);
        if (!spec) return nil;
        @synchronized(self) { [_specialized setObject:spec forKey:key]; }
    }
    FerryMTLFunction *f = (FerryMTLFunction *)[spec newFunctionWithName:name];
    [spec release];
    if (f) f->_constants = [values copy];
    return f;
}
- (void)newFunctionWithName:(NSString *)name constantValues:(MTLFunctionConstantValues *)values
          completionHandler:(void (^)(id<MTLFunction>, NSError *))handler
{
    NSError *err = nil;
    id<MTLFunction> f = [self newFunctionWithName:name constantValues:values error:&err];
    handler(f, err);
    [f release];
}
- (id<MTLFunction>)newFunctionWithDescriptor:(MTLFunctionDescriptor *)d error:(NSError **)error
{
    if (d.constantValues) return [self newFunctionWithName:d.name constantValues:d.constantValues error:error];
    id<MTLFunction> f = [self newFunctionWithName:d.name];
    if (!f && error)
        *error = FerryMTLError(MTLLibraryErrorDomain, MTLLibraryErrorFunctionNotFound,
                               @"Function %@ was not found in the library", d.name);
    return f;
}
@end

static MTLDataType slot_type(const struct ferry_slot *s)
{
    int n = s->ncomp < 1 ? 1 : s->ncomp > 4 ? 4 : s->ncomp;
    switch (s->kind) {
    case FERRY_K_HALF: return MTLDataTypeHalf + (MTLDataType)(n - 1);
    case FERRY_K_INT: return MTLDataTypeInt + (MTLDataType)(n - 1);
    case FERRY_K_UINT: return MTLDataTypeUInt + (MTLDataType)(n - 1);
    default: return MTLDataTypeFloat + (MTLDataType)(n - 1);
    }
}

@implementation FerryMTLFunction
- (void)dealloc
{
    [_library release];
    [_info release];
    [_name release];
    [_constants release];
    [super dealloc];
}
- (MTLFunctionType)functionType { return (MTLFunctionType)_fn.stage; }
- (MTLPatchType)patchType { return MTLPatchTypeNone; }
- (NSInteger)patchControlPointCount { return -1; }
- (NSString *)name { return _name; }
- (NSUInteger)options { return 0; }
- (NSArray *)ferryAttributesOfClass:(Class)cls
{
    NSMutableArray *a = [NSMutableArray array];
    if (_fn.stage != 1) return a;
    for (NSDictionary *s in _info[@"stage_in"]) {
        NSUInteger idx = [s[@"attribute"] unsignedIntegerValue];
        MTLDataType t = MTLDataTypeFloat4;
        for (int i = 0; i < _fn.slots.n; i++)
            if (_fn.slots.s[i].what == FERRY_W_ATTRIBUTE && (NSUInteger)_fn.slots.s[i].index == idx)
                t = slot_type(&_fn.slots.s[i]);
        MTLVertexAttribute *v = [[cls alloc] init];
        /* (both classes have the same three fields first) */
        ((MTLVertexAttribute *)v)->_name = [s[@"name"] copy];
        ((MTLVertexAttribute *)v)->_attributeIndex = idx;
        ((MTLVertexAttribute *)v)->_attributeType = t;
        [a addObject:v];
        [v release];
    }
    return a;
}
- (NSArray *)vertexAttributes { return [self ferryAttributesOfClass:[MTLVertexAttribute class]]; }
- (NSArray *)stageInputAttributes { return [self ferryAttributesOfClass:[MTLAttribute class]]; }
- (NSDictionary *)functionConstantsDictionary
{
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    for (NSDictionary *c in _library->_reflection[@"function_constants"]) {
        MTLFunctionConstant *k = [[MTLFunctionConstant alloc] init];
        k->_name = [c[@"name"] copy];
        k->_type = data_type_named(c[@"type"]);
        id idx = nonnull(c[@"index"]);
        k->_index = idx ? (NSUInteger)[idx integerValue] : 0;
        k->_required = NO;
        d[k->_name] = k;
        [k release];
    }
    return d;
}
id<MTLArgumentEncoder> FerryMTLNewArgumentEncoder(NSArray *arguments);
id<MTLArgumentEncoder> FerryMTLNewArgumentEncoderLaidOut(const struct ferry_arg *a, int n, int size);
- (id<MTLArgumentEncoder>)newArgumentEncoderWithBufferIndex:(NSUInteger)index
{
    /* the shader lists where its struct's [[id(n)]] members are */
    for (NSDictionary *b in _info[@"buffers"]) {
        NSNumber *bi = nonnull(b[@"index"]);
        NSString *sym = nonnull(b[@"arguments"]);
        if (![bi isKindOfClass:[NSNumber class]] || [bi unsignedIntegerValue] != index || !sym) continue;
        int (*fill)(struct ferry_arg *, int, int *) = dlsym(_library->_handle, [sym UTF8String]);
        if (!fill) break;
        struct ferry_arg a[64];
        int size = 0, n = fill(a, 64, &size);
        return FerryMTLNewArgumentEncoderLaidOut(a, n < 0 ? 0 : n > 64 ? 64 : n, size);
    }
    mtl_log("%s: buffer %lu isn't an argument buffer (a struct with [[id(n)]] members)", [_name UTF8String],
            (unsigned long)index);
    return FerryMTLNewArgumentEncoder(@[]);
}
- (id<MTLArgumentEncoder>)newArgumentEncoderWithBufferIndex:(NSUInteger)index
                                                 reflection:(MTLAutoreleasedArgument *)reflection
{
    if (reflection) *reflection = nil;
    return [self newArgumentEncoderWithBufferIndex:index];
}
@end

/* ---- descriptor arrays ------------------------------------------------------------------- */

@implementation MTLVertexAttributeDescriptor
@synthesize format = _format, offset = _offset, bufferIndex = _bufferIndex;
- (id)copyWithZone:(NSZone *)zone { return FerryMTLCopyDescriptor(self, zone); }
@end
FERRY_DESC_ARRAY(MTLVertexAttributeDescriptorArray, MTLVertexAttributeDescriptor, 31)

@implementation MTLVertexBufferLayoutDescriptor
@synthesize stride = _stride, stepFunction = _stepFunction, stepRate = _stepRate;
- (instancetype)init
{
    if ((self = [super init])) {
        _stepFunction = MTLVertexStepFunctionPerVertex;
        _stepRate = 1;
    }
    return self;
}
- (id)copyWithZone:(NSZone *)zone { return FerryMTLCopyDescriptor(self, zone); }
@end
FERRY_DESC_ARRAY(MTLVertexBufferLayoutDescriptorArray, MTLVertexBufferLayoutDescriptor, 31)

@interface MTLVertexDescriptor () {
@public
    MTLVertexBufferLayoutDescriptorArray *_layouts;
    MTLVertexAttributeDescriptorArray *_attributes;
}
@end
@implementation MTLVertexDescriptor
+ (MTLVertexDescriptor *)vertexDescriptor { return [[[self alloc] init] autorelease]; }
- (instancetype)init
{
    if ((self = [super init])) {
        _layouts = [[MTLVertexBufferLayoutDescriptorArray alloc] init];
        _attributes = [[MTLVertexAttributeDescriptorArray alloc] init];
    }
    return self;
}
- (void)dealloc { FerryMTLReleaseIvars(self); [super dealloc]; }
- (id)copyWithZone:(NSZone *)zone { return FerryMTLCopyDescriptor(self, zone); }
- (MTLVertexBufferLayoutDescriptorArray *)layouts { return _layouts; }
- (MTLVertexAttributeDescriptorArray *)attributes { return _attributes; }
- (void)reset
{
    [_layouts ferryReset];
    [_attributes ferryReset];
}
@end

@implementation MTLRenderPipelineColorAttachmentDescriptor
@synthesize pixelFormat = _pixelFormat, blendingEnabled = _blendingEnabled,
            sourceRGBBlendFactor = _sourceRGBBlendFactor, destinationRGBBlendFactor = _destinationRGBBlendFactor,
            rgbBlendOperation = _rgbBlendOperation, sourceAlphaBlendFactor = _sourceAlphaBlendFactor,
            destinationAlphaBlendFactor = _destinationAlphaBlendFactor, alphaBlendOperation = _alphaBlendOperation,
            writeMask = _writeMask;
- (instancetype)init
{
    if ((self = [super init])) {
        _sourceRGBBlendFactor = _sourceAlphaBlendFactor = MTLBlendFactorOne;
        _destinationRGBBlendFactor = _destinationAlphaBlendFactor = MTLBlendFactorZero;
        _writeMask = MTLColorWriteMaskAll;
    }
    return self;
}
- (id)copyWithZone:(NSZone *)zone { return FerryMTLCopyDescriptor(self, zone); }
@end
FERRY_DESC_ARRAY(MTLRenderPipelineColorAttachmentDescriptorArray, MTLRenderPipelineColorAttachmentDescriptor, 8)

@implementation MTLPipelineBufferDescriptor
@synthesize mutability = _mutability;
- (id)copyWithZone:(NSZone *)zone { return FerryMTLCopyDescriptor(self, zone); }
@end
FERRY_DESC_ARRAY(MTLPipelineBufferDescriptorArray, MTLPipelineBufferDescriptor, 31)

@implementation MTLRenderPipelineDescriptor
@synthesize label = _label, vertexFunction = _vertexFunction, fragmentFunction = _fragmentFunction,
            vertexDescriptor = _vertexDescriptor, sampleCount = _sampleCount, rasterSampleCount = _rasterSampleCount,
            alphaToCoverageEnabled = _alphaToCoverageEnabled, alphaToOneEnabled = _alphaToOneEnabled,
            rasterizationEnabled = _rasterizationEnabled, maxVertexAmplificationCount = _maxVertexAmplificationCount,
            colorAttachments = _colorAttachments, depthAttachmentPixelFormat = _depthAttachmentPixelFormat,
            stencilAttachmentPixelFormat = _stencilAttachmentPixelFormat,
            inputPrimitiveTopology = _inputPrimitiveTopology, maxTessellationFactor = _maxTessellationFactor,
            tessellationFactorScaleEnabled = _tessellationFactorScaleEnabled,
            supportIndirectCommandBuffers = _supportIndirectCommandBuffers, vertexBuffers = _vertexBuffers,
            fragmentBuffers = _fragmentBuffers, supportAddingVertexBinaryFunctions = _supportAddingVertexBinaryFunctions,
            supportAddingFragmentBinaryFunctions = _supportAddingFragmentBinaryFunctions,
            maxVertexCallStackDepth = _maxVertexCallStackDepth, maxFragmentCallStackDepth = _maxFragmentCallStackDepth,
            shaderValidation = _shaderValidation;
- (void)ferryDefaults
{
    _sampleCount = _rasterSampleCount = 1;
    _rasterizationEnabled = YES;
    _maxVertexAmplificationCount = 1;
    _maxTessellationFactor = 16;
    _maxVertexCallStackDepth = _maxFragmentCallStackDepth = 1;
}
- (instancetype)init
{
    if ((self = [super init])) {
        [self ferryDefaults];
        _colorAttachments = [[MTLRenderPipelineColorAttachmentDescriptorArray alloc] init];
        _vertexBuffers = [[MTLPipelineBufferDescriptorArray alloc] init];
        _fragmentBuffers = [[MTLPipelineBufferDescriptorArray alloc] init];
    }
    return self;
}
/* Like Metal's, an empty vertex descriptor is there to fill in from the start
 * (programs such as Blender set desc.vertexDescriptor.attributes[i] directly). */
- (MTLVertexDescriptor *)vertexDescriptor
{
    if (!_vertexDescriptor) _vertexDescriptor = [[MTLVertexDescriptor alloc] init];
    return _vertexDescriptor;
}
- (void)dealloc { FerryMTLReleaseIvars(self); [super dealloc]; }
- (id)copyWithZone:(NSZone *)zone { return FerryMTLCopyDescriptor(self, zone); }
- (void)reset
{
    [_label release]; _label = nil;
    [_vertexFunction release]; _vertexFunction = nil;
    [_fragmentFunction release]; _fragmentFunction = nil;
    [_vertexDescriptor release]; _vertexDescriptor = nil;
    [_colorAttachments ferryReset];
    [_vertexBuffers ferryReset];
    [_fragmentBuffers ferryReset];
    _alphaToCoverageEnabled = _alphaToOneEnabled = NO;
    _depthAttachmentPixelFormat = _stencilAttachmentPixelFormat = MTLPixelFormatInvalid;
    _inputPrimitiveTopology = MTLPrimitiveTopologyClassUnspecified;
    [self ferryDefaults];
}
@end

@implementation MTLStageInputOutputDescriptor
+ (MTLStageInputOutputDescriptor *)stageInputOutputDescriptor { return [[[self alloc] init] autorelease]; }
- (id)copyWithZone:(NSZone *)zone { return [[[self class] allocWithZone:zone] init]; }
@end

@implementation MTLComputePipelineDescriptor
@synthesize label = _label, computeFunction = _computeFunction,
            threadGroupSizeIsMultipleOfThreadExecutionWidth = _threadGroupSizeIsMultipleOfThreadExecutionWidth,
            maxTotalThreadsPerThreadgroup = _maxTotalThreadsPerThreadgroup,
            stageInputDescriptor = _stageInputDescriptor, buffers = _buffers,
            supportIndirectCommandBuffers = _supportIndirectCommandBuffers, maxCallStackDepth = _maxCallStackDepth,
            shaderValidation = _shaderValidation;
- (instancetype)init
{
    if ((self = [super init])) {
        _buffers = [[MTLPipelineBufferDescriptorArray alloc] init];
        _maxCallStackDepth = 1;
    }
    return self;
}
- (void)dealloc { FerryMTLReleaseIvars(self); [super dealloc]; }
- (id)copyWithZone:(NSZone *)zone { return FerryMTLCopyDescriptor(self, zone); }
- (void)reset
{
    [_label release]; _label = nil;
    [_computeFunction release]; _computeFunction = nil;
    [_stageInputDescriptor release]; _stageInputDescriptor = nil;
    [_buffers ferryReset];
    _maxTotalThreadsPerThreadgroup = 0;
    _threadGroupSizeIsMultipleOfThreadExecutionWidth = NO;
}
@end

/* ---- pipelines --------------------------------------------------------------------------- */
@implementation FerryMTLRenderPipelineState
- (void)dealloc { [_vs release]; [_fs release]; [super dealloc]; }
- (NSUInteger)maxTotalThreadsPerThreadgroup { return 1024; }
- (BOOL)threadgroupSizeMatchesTileSize { return NO; }
- (NSUInteger)imageblockSampleLength { return 0; }
- (BOOL)supportIndirectCommandBuffers { return NO; }
- (MTLResourceID)gpuResourceID { MTLResourceID r = {(uint64_t)(uintptr_t)&_p}; return r; }
@end

@implementation FerryMTLComputePipelineState
- (void)dealloc { [_cs release]; [super dealloc]; }
- (NSUInteger)maxTotalThreadsPerThreadgroup { return _maxThreads; }
- (NSUInteger)threadExecutionWidth { return 32; }
- (NSUInteger)staticThreadgroupMemoryLength { return 0; }
- (BOOL)supportIndirectCommandBuffers { return NO; }
- (MTLResourceID)gpuResourceID { MTLResourceID r = {(uint64_t)(uintptr_t)self}; return r; }
- (NSUInteger)imageblockMemoryLengthForDimensions:(MTLSize)d { return 0; }
@end

static id fail(NSError **error, NSString *domain, NSInteger code, NSString *msg)
{
    mtl_log("%s", [msg UTF8String]);
    if (error) *error = FerryMTLError(domain, code, @"%@", msg);
    return nil;
}

id<MTLRenderPipelineState> FerryMTLNewRenderPipeline(MTLRenderPipelineDescriptor *d, MTLPipelineOption options,
                                                     MTLRenderPipelineReflection **refl, NSError **error)
{
    if (error) *error = nil;
    if (refl) *refl = nil;
    FerryMTLFunction *vs = (FerryMTLFunction *)d.vertexFunction, *fs = (FerryMTLFunction *)d.fragmentFunction;
    if (![vs isKindOfClass:[FerryMTLFunction class]] || vs->_fn.stage != 1 || !vs->_fn.vs)
        return fail(error, MTLRenderPipelineErrorDomain, MTLRenderPipelineErrorInvalidInput,
                    @"the render pipeline has no vertex function");
    if (fs && (![fs isKindOfClass:[FerryMTLFunction class]] || fs->_fn.stage != 2 || !fs->_fn.fs))
        return fail(error, MTLRenderPipelineErrorDomain, MTLRenderPipelineErrorInvalidInput,
                    @"the render pipeline's fragment function isn't one");
    if ([vs->_info[@"stage_in"] count]) {
        MTLVertexDescriptor *vd = d.vertexDescriptor;
        int any = 0;
        for (unsigned i = 0; i < 31 && !any; i++) {
            MTLVertexAttributeDescriptor *a = [vd->_attributes ferryPeek:i];
            any = a && a.format != MTLVertexFormatInvalid;
        }
        if (!any)
            return fail(error, MTLRenderPipelineErrorDomain, MTLRenderPipelineErrorInvalidInput,
                        [NSString stringWithFormat:@"%@ reads [[stage_in]] but the pipeline's vertex descriptor has no attributes",
                                                   vs->_name]);
    }
    FerryMTLRenderPipelineState *ps = [[FerryMTLRenderPipelineState alloc] init];
    struct mtl_rpipe *p = &ps->_p;
    ps->_label = [d.label copy];
    ps->_vs = [vs retain];
    ps->_fs = [fs retain];
    p->vs = &vs->_fn;
    p->fs = fs ? &fs->_fn : NULL;

    /* vertex attributes */
    MTLVertexDescriptor *vd = d.vertexDescriptor;
    for (unsigned i = 0; i < 31; i++) {
        MTLVertexAttributeDescriptor *a = vd ? [vd->_attributes ferryPeek:i] : nil;
        if (a && a.format != MTLVertexFormatInvalid) {
            p->vd.attr[i].format = (unsigned)a.format;
            p->vd.attr[i].offset = (unsigned)a.offset;
            p->vd.attr[i].buffer = (unsigned)a.bufferIndex;
            p->vd.nattr_used |= 1u << i;
        }
        MTLVertexBufferLayoutDescriptor *l = vd ? [vd->_layouts ferryPeek:i] : nil;
        p->vd.layout[i].stride = l ? (unsigned)l.stride : 0;
        p->vd.layout[i].step = l ? (unsigned)l.stepFunction : MTLVertexStepFunctionPerVertex;
        p->vd.layout[i].rate = l ? (unsigned)l.stepRate : 1;
    }

    /* what the vertex function writes */
    int vsize = FERRY_VS_VARYINGS;
    memset(p->interp, FERRY_I_PERSPECTIVE, sizeof p->interp);
    const struct mtl_slots *vsl = &vs->_fn.slots;
    for (int i = 0; i < vsl->n; i++) {
        const struct ferry_slot *s = &vsl->s[i];
        int end = s->offset + (s->ncomp > 0 ? s->ncomp : 1);
        switch (s->what) {
        case FERRY_W_VARYING:
            if (end > vsize) vsize = end;
            if (s->kind == FERRY_K_INT || s->kind == FERRY_K_UINT)
                for (int k = s->offset; k < end && k - FERRY_VS_VARYINGS < 256; k++)
                    if (k >= FERRY_VS_VARYINGS) p->interp[k - FERRY_VS_VARYINGS] = FERRY_I_FLAT;
            break;
        case FERRY_W_POINT_SIZE: p->has_point_size = 1; break;
        case FERRY_W_CLIP_DISTANCE:
            if (end - FERRY_VS_CLIP > p->nclip) p->nclip = end - FERRY_VS_CLIP;
            break;
        default: break;
        }
    }
    if (p->nclip > 8) p->nclip = 8;
    /* fragment inputs no vertex result matches read four zeros put after the varyings */
    int zeros = vsize;
    int need_zeros = 0;
    for (int i = 0; i < 64; i++) p->stage_in_map[i] = 0;
    for (int i = 0; i < 8; i++) p->color_kind[i] = -1;
    if (fs) {
        const struct mtl_slots *fsl = &fs->_fn.slots;
        for (int i = 0; i < fsl->n; i++) {
            const struct ferry_slot *s = &fsl->s[i];
            switch (s->what) {
            case FERRY_W_COLOR:
                if (s->index >= 0 && s->index < 8) p->color_kind[s->index] = s->kind;
                break;
            case FERRY_W_DEPTH: p->writes_depth = 1; break;
            case FERRY_W_SAMPLE_MASK: p->writes_mask = 1; break;
            case FERRY_W_STENCIL: p->writes_stencil = 1; break;
            case FERRY_W_INPUT: {
                if (s->index < 0 || s->index >= 64) break;
                int found = -1, vkind = 0;
                for (int k = 0; k < vsl->n; k++)
                    if (vsl->s[k].what == FERRY_W_VARYING && vsl->s[k].tag && s->tag &&
                        !strcmp(vsl->s[k].tag, s->tag)) {
                        found = vsl->s[k].offset;
                        vkind = vsl->s[k].kind;
                        break;
                    }
                if (found < 0) {
                    if (mtl_verbose)
                        mtl_log("%s reads %s, which %s doesn't write; it reads zeros", [fs->_name UTF8String], s->tag,
                                [vs->_name UTF8String]);
                    p->stage_in_map[s->index] = zeros;
                    need_zeros = 1;
                    break;
                }
                p->stage_in_map[s->index] = found;
                int interp = s->interp;
                if (s->kind == FERRY_K_INT || s->kind == FERRY_K_UINT || vkind == FERRY_K_INT || vkind == FERRY_K_UINT)
                    interp = FERRY_I_FLAT;
                for (int k = 0; k < (s->ncomp > 0 ? s->ncomp : 1); k++) {
                    int v = found + k - FERRY_VS_VARYINGS;
                    if (v >= 0 && v < 256) p->interp[v] = (unsigned char)interp;
                }
                break;
            }
            default: break;
            }
        }
    }
    if (need_zeros) {
        for (int k = 0; k < 4 && zeros + k - FERRY_VS_VARYINGS < 256; k++)
            p->interp[zeros + k - FERRY_VS_VARYINGS] = FERRY_I_FLAT;
        vsize = zeros + 4;
    }
    p->vsize = vsize;
    p->nvary = vsize - FERRY_VS_VARYINGS;

    /* attachments */
    for (unsigned i = 0; i < 8; i++) {
        MTLRenderPipelineColorAttachmentDescriptor *c = [d.colorAttachments ferryPeek:i];
        struct mtl_blend *b = &p->blend[i];
        if (!c) {
            p->color_formats[i] = 0;
            b->write_mask = 15;
            b->src_rgb = b->src_a = MTLBlendFactorOne;
            continue;
        }
        p->color_formats[i] = (unsigned)c.pixelFormat;
        b->enabled = c.isBlendingEnabled;
        b->write_mask = (unsigned char)c.writeMask;
        b->src_rgb = (unsigned char)c.sourceRGBBlendFactor;
        b->dst_rgb = (unsigned char)c.destinationRGBBlendFactor;
        b->op_rgb = (unsigned char)c.rgbBlendOperation;
        b->src_a = (unsigned char)c.sourceAlphaBlendFactor;
        b->dst_a = (unsigned char)c.destinationAlphaBlendFactor;
        b->op_a = (unsigned char)c.alphaBlendOperation;
    }
    p->depth_format = (unsigned)d.depthAttachmentPixelFormat;
    p->stencil_format = (unsigned)d.stencilAttachmentPixelFormat;
    p->alpha_to_coverage = d.isAlphaToCoverageEnabled;
    p->raster_enabled = d.isRasterizationEnabled;
    if (d.sampleCount > 1 && mtl_verbose) mtl_log("multisampling isn't done yet; drawing with one sample");

    if (refl && (options & (MTLPipelineOptionArgumentInfo | MTLPipelineOptionBufferTypeInfo))) {
        MTLRenderPipelineReflection *r = [[[MTLRenderPipelineReflection alloc] init] autorelease];
        r->_vertexArguments = [arguments_of(vs->_info) retain];
        r->_fragmentArguments = [(fs ? arguments_of(fs->_info) : @[]) retain];
        *refl = r;
    }
    return ps;
}

id<MTLComputePipelineState> FerryMTLNewComputePipeline(id<MTLFunction> fn, MTLComputePipelineDescriptor *d,
                                                       MTLPipelineOption options, MTLComputePipelineReflection **refl,
                                                       NSError **error)
{
    if (error) *error = nil;
    if (refl) *refl = nil;
    FerryMTLFunction *f = (FerryMTLFunction *)fn;
    if (![f isKindOfClass:[FerryMTLFunction class]] || f->_fn.stage != 3 || !f->_fn.cs)
        return fail(error, MTLLibraryErrorDomain, MTLLibraryErrorInternal,
                    @"the compute pipeline's function isn't a kernel");
    FerryMTLComputePipelineState *ps = [[FerryMTLComputePipelineState alloc] init];
    ps->_label = [d.label copy];
    ps->_cs = [f retain];
    ps->_maxThreads = f->_fn.max_threads;
    if (d.maxTotalThreadsPerThreadgroup && d.maxTotalThreadsPerThreadgroup < ps->_maxThreads)
        ps->_maxThreads = d.maxTotalThreadsPerThreadgroup;
    if (refl && (options & (MTLPipelineOptionArgumentInfo | MTLPipelineOptionBufferTypeInfo))) {
        MTLComputePipelineReflection *r = [[[MTLComputePipelineReflection alloc] init] autorelease];
        r->_arguments = [arguments_of(f->_info) retain];
        *refl = r;
    }
    return ps;
}

/* ---- argument encoders --------------------------------------------------------------------- */
/* An argument buffer here is a plain struct: a buffer is its address, a
 * texture the address of Ferry's texture record, a sampler the sampler
 * record itself, a constant its bytes, laid out in the order of the
 * arguments' indices with each one aligned as C aligns it. */
struct argslot { NSUInteger index, count, offset, size; MTLDataType type; };
@interface FerryMTLArgumentEncoder : FerryMTLObject <MTLArgumentEncoder> {
@public
    struct argslot *_slots;
    NSUInteger _n, _length, _align;
    char *_base;
    id _buffer;
}
@end
@implementation FerryMTLArgumentEncoder
- (void)dealloc { free(_slots); [_buffer release]; [super dealloc]; }
- (NSUInteger)encodedLength { return _length; }
- (NSUInteger)alignment { return _align; }
- (void)setArgumentBuffer:(id<MTLBuffer>)b offset:(NSUInteger)offset
{
    [_buffer release];
    _buffer = [b retain];
    _base = b ? (char *)[b contents] + offset : NULL;
}
- (void)setArgumentBuffer:(id<MTLBuffer>)b startOffset:(NSUInteger)start arrayElement:(NSUInteger)element
{
    [self setArgumentBuffer:b offset:start + element * ((_length + _align - 1) / _align * _align)];
}
- (char *)ferrySlot:(NSUInteger)index size:(NSUInteger *)size
{
    for (NSUInteger i = 0; i < _n; i++)
        if (index >= _slots[i].index && index < _slots[i].index + _slots[i].count) {
            if (size) *size = _slots[i].size;
            return _base ? _base + _slots[i].offset + (index - _slots[i].index) * _slots[i].size : NULL;
        }
    return NULL;
}
- (void)setBuffer:(id<MTLBuffer>)b offset:(NSUInteger)offset atIndex:(NSUInteger)index
{
    char *p = [self ferrySlot:index size:NULL];
    if (!p) return;
    void *v = b ? (char *)[b contents] + offset : NULL;
    memcpy(p, &v, sizeof v);
}
- (void)setBuffers:(const id<MTLBuffer> __unsafe_unretained[])b offsets:(const NSUInteger[])o withRange:(NSRange)r
{
    for (NSUInteger i = 0; i < r.length; i++) [self setBuffer:b[i] offset:o[i] atIndex:r.location + i];
}
- (void)setTexture:(id<MTLTexture>)t atIndex:(NSUInteger)index
{
    char *p = [self ferrySlot:index size:NULL];
    if (!p) return;
    const void *v = t ? (const void *)[(FerryMTLTexture *)t ferryTex] : NULL;
    memcpy(p, &v, sizeof v);
}
- (void)setTextures:(const id<MTLTexture> __unsafe_unretained[])t withRange:(NSRange)r
{
    for (NSUInteger i = 0; i < r.length; i++) [self setTexture:t[i] atIndex:r.location + i];
}
- (void)setSamplerState:(id<MTLSamplerState>)s atIndex:(NSUInteger)index
{
    char *p = [self ferrySlot:index size:NULL];
    if (!p) return;
    if (s) memcpy(p, &((FerryMTLSampler *)s)->_s, sizeof(struct ferry_sampler));
    else memset(p, 0, sizeof(struct ferry_sampler));
}
- (void)setSamplerStates:(const id<MTLSamplerState> __unsafe_unretained[])s withRange:(NSRange)r
{
    for (NSUInteger i = 0; i < r.length; i++) [self setSamplerState:s[i] atIndex:r.location + i];
}
- (void *)constantDataAtIndex:(NSUInteger)index { return [self ferrySlot:index size:NULL]; }
- (id<MTLArgumentEncoder>)newArgumentEncoderForBufferAtIndex:(NSUInteger)index
{
    mtl_log("nested argument encoders aren't done yet");
    return nil;
}
@end

id<MTLArgumentEncoder> FerryMTLNewArgumentEncoder(NSArray *arguments)
{
    FerryMTLArgumentEncoder *e = [[FerryMTLArgumentEncoder alloc] init];
    NSArray *sorted = [arguments sortedArrayUsingComparator:^NSComparisonResult(MTLArgumentDescriptor *a,
                                                                                MTLArgumentDescriptor *b) {
      return a.index < b.index ? NSOrderedAscending : a.index > b.index ? NSOrderedDescending : NSOrderedSame;
    }];
    e->_n = [sorted count];
    e->_slots = calloc(e->_n ? e->_n : 1, sizeof(struct argslot));
    NSUInteger off = 0, maxalign = 8;
    for (NSUInteger i = 0; i < e->_n; i++) {
        MTLArgumentDescriptor *a = sorted[i];
        NSUInteger size, align;
        switch (a.dataType) {
        case MTLDataTypePointer: case MTLDataTypeTexture: size = align = 8; break;
        case MTLDataTypeSampler: size = sizeof(struct ferry_sampler); align = 4; break;
        default:
            size = data_type_size(a.dataType);
            align = size == 12 ? 16 : size == 6 ? 8 : size;   /* (3-vectors take four places) */
            if (size == 12) size = 16;
            if (size == 6) size = 8;
            if (a.constantBlockAlignment > align) align = a.constantBlockAlignment;
            if (!align) align = 4;
            break;
        }
        off = (off + align - 1) / align * align;
        e->_slots[i] = (struct argslot){a.index, a.arrayLength ? a.arrayLength : 1, off, size, a.dataType};
        off += size * e->_slots[i].count;
        if (align > maxalign) maxalign = align;
    }
    e->_length = off;
    e->_align = maxalign;
    return e;
}

id<MTLArgumentEncoder> FerryMTLNewArgumentEncoderLaidOut(const struct ferry_arg *a, int n, int size)
{
    FerryMTLArgumentEncoder *e = [[FerryMTLArgumentEncoder alloc] init];
    e->_n = (NSUInteger)n;
    e->_slots = calloc(n ? (size_t)n : 1, sizeof(struct argslot));
    for (int i = 0; i < n; i++) {
        MTLDataType t = a[i].type == FERRY_A_SAMPLER ? MTLDataTypeSampler
                        : a[i].type == FERRY_A_TEXTURE ? MTLDataTypeTexture
                        : a[i].type == FERRY_A_BUFFER  ? MTLDataTypePointer
                                                        : MTLDataTypeStruct;
        e->_slots[i] = (struct argslot){(NSUInteger)a[i].id, a[i].count > 0 ? (NSUInteger)a[i].count : 1,
                                        (NSUInteger)a[i].offset, (NSUInteger)a[i].stride, t};
    }
    e->_length = (NSUInteger)size;
    e->_align = 16;
    return e;
}
