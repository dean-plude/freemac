/* SPDX-License-Identifier: GPL-3.0-or-later
 * IOSurface.framework for Ferry, written from Apple's public IOSurface
 * documentation. A surface is memory of this program's own, with the
 * properties it was made with: one plane, or several planes one after the
 * other, each row aligned to 16 bytes as on a Mac. Locking only counts
 * (there is no GPU copy to sync), the seed goes up after a write lock, and
 * a surface's ID finds it with IOSurfaceLookup while it lives. Surfaces
 * aren't shared with other programs: IOSurfaceCreateMachPort gives no port. */
#import <Foundation/Foundation.h>
#include <IOSurface/IOSurface.h>
#include <pthread.h>
#include <stdlib.h>
#include <string.h>

#define KEY(name, text) const CFStringRef name = (CFStringRef)@text;
KEY(kIOSurfaceAllocSize, "IOSurfaceAllocSize")
KEY(kIOSurfaceWidth, "IOSurfaceWidth")
KEY(kIOSurfaceHeight, "IOSurfaceHeight")
KEY(kIOSurfaceBytesPerRow, "IOSurfaceBytesPerRow")
KEY(kIOSurfaceBytesPerElement, "IOSurfaceBytesPerElement")
KEY(kIOSurfaceElementWidth, "IOSurfaceElementWidth")
KEY(kIOSurfaceElementHeight, "IOSurfaceElementHeight")
KEY(kIOSurfaceOffset, "IOSurfaceOffset")
KEY(kIOSurfacePlaneInfo, "IOSurfacePlaneInfo")
KEY(kIOSurfacePlaneWidth, "IOSurfacePlaneWidth")
KEY(kIOSurfacePlaneHeight, "IOSurfacePlaneHeight")
KEY(kIOSurfacePlaneBytesPerRow, "IOSurfacePlaneBytesPerRow")
KEY(kIOSurfacePlaneOffset, "IOSurfacePlaneOffset")
KEY(kIOSurfacePlaneSize, "IOSurfacePlaneSize")
KEY(kIOSurfacePlaneBase, "IOSurfacePlaneBase")
KEY(kIOSurfacePlaneBytesPerElement, "IOSurfacePlaneBytesPerElement")
KEY(kIOSurfacePlaneElementWidth, "IOSurfacePlaneElementWidth")
KEY(kIOSurfacePlaneElementHeight, "IOSurfacePlaneElementHeight")
KEY(kIOSurfaceCacheMode, "IOSurfaceCacheMode")
KEY(kIOSurfaceIsGlobal, "IOSurfaceIsGlobal")
KEY(kIOSurfacePixelFormat, "IOSurfacePixelFormat")
KEY(kIOSurfaceName, "IOSurfaceName")
KEY(kIOSurfaceColorSpace, "IOSurfaceColorSpace")
KEY(kIOSurfaceICCProfile, "IOSurfaceICCProfile")
NSString *const IOSurfacePropertyKeyAllocSize = @"IOSurfaceAllocSize";
NSString *const IOSurfacePropertyKeyWidth = @"IOSurfaceWidth";
NSString *const IOSurfacePropertyKeyHeight = @"IOSurfaceHeight";
NSString *const IOSurfacePropertyKeyBytesPerRow = @"IOSurfaceBytesPerRow";
NSString *const IOSurfacePropertyKeyBytesPerElement = @"IOSurfaceBytesPerElement";
NSString *const IOSurfacePropertyKeyPixelFormat = @"IOSurfacePixelFormat";
NSString *const IOSurfacePropertyKeyName = @"IOSurfaceName";

#define MAX_PLANES 4
#define ROW_ALIGN 16

typedef struct {
    size_t width, height, bpe, ew, eh, bpr, offset, size;
} FPlane;

static pthread_mutex_t registry_lock = PTHREAD_MUTEX_INITIALIZER;
static NSMutableDictionary *registry; /* ID -> the surface, not retained */
static IOSurfaceID next_id = 1;

@interface IOSurface () {
@public
    void *_memory;
    size_t _alloc, _width, _height, _bpe, _ew, _eh, _bpr;
    OSType _format;
    FPlane _planes[MAX_PLANES];
    size_t _nplanes;
    uint32_t _seed;
    int32_t _use, _locks;
    IOSurfaceID _id;
    NSMutableDictionary *_values;
    pthread_mutex_t _lock;
}
@end

static size_t num(NSDictionary *d, CFStringRef key, size_t fallback)
{
    id v = d[(__bridge NSString *)key];
    return [v respondsToSelector:@selector(unsignedLongLongValue)] ? (size_t)[v unsignedLongLongValue] : fallback;
}

static size_t align_up(size_t v, size_t a) { return (v + a - 1) / a * a; }

@implementation IOSurface

+ (BOOL)supportsSecureCoding { return NO; }
- (void)encodeWithCoder:(NSCoder *)coder { }
- (instancetype)initWithCoder:(NSCoder *)coder { return nil; }

- (instancetype)initWithProperties:(NSDictionary *)p
{
    if (!(self = [super init]))
        return nil;
    pthread_mutex_init(&_lock, NULL);
    _width = num(p, kIOSurfaceWidth, 0);
    _height = num(p, kIOSurfaceHeight, 0);
    _bpe = num(p, kIOSurfaceBytesPerElement, 1);
    _ew = num(p, kIOSurfaceElementWidth, 1);
    _eh = num(p, kIOSurfaceElementHeight, 1);
    _format = (OSType)num(p, kIOSurfacePixelFormat, 0);
    if (!_bpe) _bpe = 1;
    if (!_ew) _ew = 1;
    if (!_eh) _eh = 1;
    size_t minrow = (_width + _ew - 1) / _ew * _bpe;
    _bpr = num(p, kIOSurfaceBytesPerRow, 0);
    if (_bpr < minrow)
        _bpr = align_up(minrow, ROW_ALIGN);
    size_t total = _bpr * ((_height + _eh - 1) / _eh);
    NSArray *planes = p[(__bridge NSString *)kIOSurfacePlaneInfo];
    if ([planes isKindOfClass:[NSArray class]] && [planes count]) {
        size_t off = 0;
        for (NSDictionary *pl in planes) {
            if (_nplanes == MAX_PLANES || ![pl isKindOfClass:[NSDictionary class]])
                break;
            FPlane *f = &_planes[_nplanes++];
            f->width = num(pl, kIOSurfacePlaneWidth, _width);
            f->height = num(pl, kIOSurfacePlaneHeight, _height);
            f->bpe = num(pl, kIOSurfacePlaneBytesPerElement, 1);
            f->ew = num(pl, kIOSurfacePlaneElementWidth, 1);
            f->eh = num(pl, kIOSurfacePlaneElementHeight, 1);
            if (!f->bpe) f->bpe = 1;
            if (!f->ew) f->ew = 1;
            if (!f->eh) f->eh = 1;
            size_t pmin = (f->width + f->ew - 1) / f->ew * f->bpe;
            f->bpr = num(pl, kIOSurfacePlaneBytesPerRow, 0);
            if (f->bpr < pmin)
                f->bpr = align_up(pmin, ROW_ALIGN);
            f->offset = num(pl, kIOSurfacePlaneOffset, align_up(off, 64));
            f->size = num(pl, kIOSurfacePlaneSize, f->bpr * ((f->height + f->eh - 1) / f->eh));
            off = f->offset + f->size;
        }
        if (off > total)
            total = off;
    }
    _alloc = num(p, kIOSurfaceAllocSize, 0);
    if (_alloc < total)
        _alloc = total;
    if (!_alloc)
        _alloc = 1;
    _alloc = align_up(_alloc, 4096);
    if (posix_memalign(&_memory, 4096, _alloc)) {
        [self release];
        return nil;
    }
    memset(_memory, 0, _alloc);
    _values = [[NSMutableDictionary alloc] init];
    for (NSString *k in p) {
        if (![k isKindOfClass:[NSString class]] || [k hasPrefix:@"IOSurface"])
            continue;
        _values[k] = p[k];
    }
    id name = p[(__bridge NSString *)kIOSurfaceName];
    if (name)
        _values[(__bridge NSString *)kIOSurfaceName] = name;
    pthread_mutex_lock(&registry_lock);
    if (!registry)
        registry = [[NSMutableDictionary alloc] init];
    _id = next_id++;
    registry[@(_id)] = [NSValue valueWithNonretainedObject:self];
    pthread_mutex_unlock(&registry_lock);
    return self;
}

- (void)dealloc
{
    pthread_mutex_lock(&registry_lock);
    [registry removeObjectForKey:@(_id)];
    pthread_mutex_unlock(&registry_lock);
    free(_memory);
    [_values release];
    pthread_mutex_destroy(&_lock);
    [super dealloc];
}

- (kern_return_t)lockWithOptions:(IOSurfaceLockOptions)options seed:(uint32_t *)seed
{
    pthread_mutex_lock(&_lock);
    _locks++;
    if (seed) *seed = _seed;
    pthread_mutex_unlock(&_lock);
    return KERN_SUCCESS;
}

- (kern_return_t)unlockWithOptions:(IOSurfaceLockOptions)options seed:(uint32_t *)seed
{
    pthread_mutex_lock(&_lock);
    if (_locks <= 0) {
        pthread_mutex_unlock(&_lock);
        return KERN_INVALID_ARGUMENT;
    }
    _locks--;
    if (!(options & kIOSurfaceLockReadOnly))
        _seed++;
    if (seed) *seed = _seed;
    pthread_mutex_unlock(&_lock);
    return KERN_SUCCESS;
}

- (NSInteger)allocationSize { return (NSInteger)_alloc; }
- (NSInteger)width { return (NSInteger)_width; }
- (NSInteger)height { return (NSInteger)_height; }
- (void *)baseAddress { return _memory; }
- (OSType)pixelFormat { return _format; }
- (NSInteger)bytesPerRow { return (NSInteger)_bpr; }
- (NSInteger)bytesPerElement { return (NSInteger)_bpe; }
- (NSInteger)elementWidth { return (NSInteger)_ew; }
- (NSInteger)elementHeight { return (NSInteger)_eh; }
- (uint32_t)seed { return _seed; }
- (NSUInteger)planeCount { return _nplanes; }
- (BOOL)isInUse { return _use > 0; }
- (int32_t)localUseCount { return _use; }
- (void)incrementUseCount { __sync_fetch_and_add(&_use, 1); }
- (void)decrementUseCount { if (__sync_fetch_and_sub(&_use, 1) <= 0) __sync_fetch_and_add(&_use, 1); }

- (id)attachmentForKey:(NSString *)key
{
    pthread_mutex_lock(&_lock);
    id v = [[_values[key] retain] autorelease];
    pthread_mutex_unlock(&_lock);
    return v;
}

- (void)setAttachment:(id)value forKey:(NSString *)key
{
    if (!key) return;
    pthread_mutex_lock(&_lock);
    if (value) _values[key] = value; else [_values removeObjectForKey:key];
    pthread_mutex_unlock(&_lock);
}

- (void)removeAttachmentForKey:(NSString *)key { [self setAttachment:nil forKey:key]; }

- (NSString *)description
{
    return [NSString stringWithFormat:@"<IOSurface %p id=%u %zux%zu fmt=%08x>", self, _id, _width, _height, _format];
}
@end

#define S(ref) ((__bridge IOSurface *)(ref))

static Class surface_class(void) { return [IOSurface class]; }

CFTypeID IOSurfaceGetTypeID(void) { return (CFTypeID)(uintptr_t)surface_class(); }

IOSurfaceRef IOSurfaceCreate(CFDictionaryRef properties)
{
    IOSurface *s = [[IOSurface alloc] initWithProperties:(__bridge NSDictionary *)properties ?: @{}];
    return (__bridge IOSurfaceRef)s;
}

IOSurfaceRef IOSurfaceLookup(IOSurfaceID csid)
{
    pthread_mutex_lock(&registry_lock);
    IOSurface *s = [registry[@(csid)] nonretainedObjectValue];
    [s retain];
    pthread_mutex_unlock(&registry_lock);
    return (__bridge IOSurfaceRef)s;
}

IOSurfaceID IOSurfaceGetID(IOSurfaceRef b) { return b ? S(b)->_id : 0; }
kern_return_t IOSurfaceLock(IOSurfaceRef b, IOSurfaceLockOptions o, uint32_t *seed)
{ return b ? [S(b) lockWithOptions:o seed:seed] : KERN_INVALID_ARGUMENT; }
kern_return_t IOSurfaceUnlock(IOSurfaceRef b, IOSurfaceLockOptions o, uint32_t *seed)
{ return b ? [S(b) unlockWithOptions:o seed:seed] : KERN_INVALID_ARGUMENT; }
size_t IOSurfaceGetAllocSize(IOSurfaceRef b) { return b ? S(b)->_alloc : 0; }
size_t IOSurfaceGetWidth(IOSurfaceRef b) { return b ? S(b)->_width : 0; }
size_t IOSurfaceGetHeight(IOSurfaceRef b) { return b ? S(b)->_height : 0; }
size_t IOSurfaceGetBytesPerElement(IOSurfaceRef b) { return b ? S(b)->_bpe : 0; }
size_t IOSurfaceGetBytesPerRow(IOSurfaceRef b) { return b ? S(b)->_bpr : 0; }
void *IOSurfaceGetBaseAddress(IOSurfaceRef b) { return b ? S(b)->_memory : NULL; }
size_t IOSurfaceGetElementWidth(IOSurfaceRef b) { return b ? S(b)->_ew : 0; }
size_t IOSurfaceGetElementHeight(IOSurfaceRef b) { return b ? S(b)->_eh : 0; }
OSType IOSurfaceGetPixelFormat(IOSurfaceRef b) { return b ? S(b)->_format : 0; }
uint32_t IOSurfaceGetSeed(IOSurfaceRef b) { return b ? S(b)->_seed : 0; }
size_t IOSurfaceGetPlaneCount(IOSurfaceRef b) { return b ? S(b)->_nplanes : 0; }

static FPlane *plane(IOSurfaceRef b, size_t i)
{
    return (b && i < S(b)->_nplanes) ? &S(b)->_planes[i] : NULL;
}

/* With no planes, plane 0 is the surface itself, as on a Mac. */
size_t IOSurfaceGetWidthOfPlane(IOSurfaceRef b, size_t i)
{ FPlane *p = plane(b, i); return p ? p->width : (i == 0 ? IOSurfaceGetWidth(b) : 0); }
size_t IOSurfaceGetHeightOfPlane(IOSurfaceRef b, size_t i)
{ FPlane *p = plane(b, i); return p ? p->height : (i == 0 ? IOSurfaceGetHeight(b) : 0); }
size_t IOSurfaceGetBytesPerElementOfPlane(IOSurfaceRef b, size_t i)
{ FPlane *p = plane(b, i); return p ? p->bpe : (i == 0 ? IOSurfaceGetBytesPerElement(b) : 0); }
size_t IOSurfaceGetBytesPerRowOfPlane(IOSurfaceRef b, size_t i)
{ FPlane *p = plane(b, i); return p ? p->bpr : (i == 0 ? IOSurfaceGetBytesPerRow(b) : 0); }
void *IOSurfaceGetBaseAddressOfPlane(IOSurfaceRef b, size_t i)
{ FPlane *p = plane(b, i); return p ? (char *)S(b)->_memory + p->offset : (i == 0 ? IOSurfaceGetBaseAddress(b) : NULL); }
size_t IOSurfaceGetElementWidthOfPlane(IOSurfaceRef b, size_t i)
{ FPlane *p = plane(b, i); return p ? p->ew : (i == 0 ? IOSurfaceGetElementWidth(b) : 0); }
size_t IOSurfaceGetElementHeightOfPlane(IOSurfaceRef b, size_t i)
{ FPlane *p = plane(b, i); return p ? p->eh : (i == 0 ? IOSurfaceGetElementHeight(b) : 0); }

void IOSurfaceSetValue(IOSurfaceRef b, CFStringRef key, CFTypeRef value)
{ if (b) [S(b) setAttachment:(__bridge id)value forKey:(__bridge NSString *)key]; }
CFTypeRef IOSurfaceCopyValue(IOSurfaceRef b, CFStringRef key)
{ return b ? (__bridge CFTypeRef)[[S(b) attachmentForKey:(__bridge NSString *)key] retain] : NULL; }
void IOSurfaceRemoveValue(IOSurfaceRef b, CFStringRef key)
{ if (b) [S(b) removeAttachmentForKey:(__bridge NSString *)key]; }
void IOSurfaceSetValues(IOSurfaceRef b, CFDictionaryRef d)
{
    NSDictionary *dict = (__bridge NSDictionary *)d;
    for (NSString *k in dict)
        IOSurfaceSetValue(b, (__bridge CFStringRef)k, (__bridge CFTypeRef)dict[k]);
}
CFDictionaryRef IOSurfaceCopyAllValues(IOSurfaceRef b)
{
    if (!b) return NULL;
    pthread_mutex_lock(&S(b)->_lock);
    NSDictionary *d = [S(b)->_values copy];
    pthread_mutex_unlock(&S(b)->_lock);
    return (__bridge CFDictionaryRef)d;
}
void IOSurfaceRemoveAllValues(IOSurfaceRef b)
{
    if (!b) return;
    pthread_mutex_lock(&S(b)->_lock);
    [S(b)->_values removeAllObjects];
    pthread_mutex_unlock(&S(b)->_lock);
}

/* What a Mac's documentation gives as the limits: 16384 pixels a side, rows
 * aligned to 16 bytes. */
size_t IOSurfaceGetPropertyMaximum(CFStringRef property)
{
    NSString *p = (__bridge NSString *)property;
    if ([p isEqualToString:(__bridge NSString *)kIOSurfaceWidth] || [p isEqualToString:(__bridge NSString *)kIOSurfaceHeight] ||
        [p isEqualToString:(__bridge NSString *)kIOSurfacePlaneWidth] || [p isEqualToString:(__bridge NSString *)kIOSurfacePlaneHeight])
        return 16384;
    if ([p isEqualToString:(__bridge NSString *)kIOSurfaceBytesPerRow] || [p isEqualToString:(__bridge NSString *)kIOSurfacePlaneBytesPerRow])
        return 16384 * 16;
    if ([p isEqualToString:(__bridge NSString *)kIOSurfaceAllocSize])
        return (size_t)1 << 32;
    return SIZE_MAX;
}

size_t IOSurfaceGetPropertyAlignment(CFStringRef property)
{
    NSString *p = (__bridge NSString *)property;
    if ([p isEqualToString:(__bridge NSString *)kIOSurfaceBytesPerRow] || [p isEqualToString:(__bridge NSString *)kIOSurfacePlaneBytesPerRow])
        return ROW_ALIGN;
    if ([p isEqualToString:(__bridge NSString *)kIOSurfaceAllocSize])
        return 4096;
    return 1;
}

size_t IOSurfaceAlignProperty(CFStringRef property, size_t value)
{
    return align_up(value, IOSurfaceGetPropertyAlignment(property));
}

void IOSurfaceIncrementUseCount(IOSurfaceRef b) { if (b) [S(b) incrementUseCount]; }
void IOSurfaceDecrementUseCount(IOSurfaceRef b) { if (b) [S(b) decrementUseCount]; }
int32_t IOSurfaceGetUseCount(IOSurfaceRef b) { return b ? S(b)->_use : 0; }
Boolean IOSurfaceIsInUse(IOSurfaceRef b) { return b && S(b)->_use > 0; }
Boolean IOSurfaceAllowsPixelSizeCasting(IOSurfaceRef b) { return b != NULL; }
kern_return_t IOSurfaceSetPurgeable(IOSurfaceRef b, uint32_t newState, uint32_t *oldState)
{
    if (oldState) *oldState = kIOSurfacePurgeableNonVolatile;
    return b ? KERN_SUCCESS : KERN_INVALID_ARGUMENT;
}
mach_port_t IOSurfaceCreateMachPort(IOSurfaceRef b) { return MACH_PORT_NULL; }
IOSurfaceRef IOSurfaceLookupFromMachPort(mach_port_t port) { return NULL; }
