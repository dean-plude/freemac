/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry)
 * NSAppleEventDescriptor and NSAppleEventManager (freemac 1.225, Ferry
 * 0.49.0), over the Apple Event Manager of AppleEvents.m: see
 * NSAppleEventDescriptor.h. Written from Apple's public documentation; no
 * Apple code was read. */
#import <Foundation/Foundation.h>
#import <objc/message.h>

@implementation NSAppleEventDescriptor {
    AEDesc _desc;
}
+ (BOOL)supportsSecureCoding { return YES; }

- (instancetype)initWithAEDescNoCopy:(const AEDesc *)desc
{
    if ((self = [super init])) {
        if (desc)
            _desc = *desc;
        else
            AEInitializeDesc(&_desc);
    }
    return self;
}
- (instancetype)init { return [self initWithDescriptorType:typeNull bytes:NULL length:0]; }
- (instancetype)initWithDescriptorType:(DescType)type bytes:(const void *)bytes length:(NSUInteger)length
{
    AEDesc d;
    if (AECreateDesc(type, bytes, (Size)length, &d) != noErr) {
        [self release];
        return nil;
    }
    return [self initWithAEDescNoCopy:&d];
}
- (instancetype)initWithDescriptorType:(DescType)type data:(NSData *)data
{
    return [self initWithDescriptorType:type bytes:[data bytes] length:[data length]];
}
- (instancetype)initListDescriptor
{
    AEDesc d;
    AECreateList(NULL, 0, false, &d);
    return [self initWithAEDescNoCopy:&d];
}
- (instancetype)initRecordDescriptor
{
    AEDesc d;
    AECreateList(NULL, 0, true, &d);
    return [self initWithAEDescNoCopy:&d];
}
- (instancetype)initWithEventClass:(AEEventClass)eventClass eventID:(AEEventID)eventID
                  targetDescriptor:(NSAppleEventDescriptor *)target
                          returnID:(AEReturnID)returnID
                     transactionID:(AETransactionID)transactionID
{
    AppleEvent e;
    if (AECreateAppleEvent(eventClass, eventID, target ? [target aeDesc] : NULL, returnID, transactionID, &e) != noErr) {
        [self release];
        return nil;
    }
    return [self initWithAEDescNoCopy:&e];
}
- (void)dealloc
{
    AEDisposeDesc(&_desc);
    [super dealloc];
}
- (id)copyWithZone:(NSZone *)zone
{
    AEDesc d;
    AEDuplicateDesc(&_desc, &d);
    return [[NSAppleEventDescriptor alloc] initWithAEDescNoCopy:&d];
}

/* kept as its type and its bytes (a list, record or event as its type
 * alone: they hold descriptors of their own) */
- (void)encodeWithCoder:(NSCoder *)coder
{
    [coder encodeInt32:(int32_t)_desc.descriptorType forKey:@"NSType"];
    [coder encodeObject:[self data] forKey:@"NSData"];
}
- (instancetype)initWithCoder:(NSCoder *)coder
{
    return [self initWithDescriptorType:(DescType)[coder decodeInt32ForKey:@"NSType"]
                                   data:[coder decodeObjectOfClass:[NSData class] forKey:@"NSData"]];
}

+ (NSAppleEventDescriptor *)nullDescriptor { return [[[self alloc] init] autorelease]; }
+ (NSAppleEventDescriptor *)descriptorWithDescriptorType:(DescType)type bytes:(const void *)bytes length:(NSUInteger)length
{
    return [[[self alloc] initWithDescriptorType:type bytes:bytes length:length] autorelease];
}
+ (NSAppleEventDescriptor *)descriptorWithDescriptorType:(DescType)type data:(NSData *)data
{
    return [[[self alloc] initWithDescriptorType:type data:data] autorelease];
}
+ (NSAppleEventDescriptor *)descriptorWithBoolean:(Boolean)b
{
    return [self descriptorWithDescriptorType:typeBoolean bytes:&b length:sizeof b];
}
+ (NSAppleEventDescriptor *)descriptorWithEnumCode:(OSType)code
{
    return [self descriptorWithDescriptorType:typeEnumerated bytes:&code length:sizeof code];
}
+ (NSAppleEventDescriptor *)descriptorWithInt32:(SInt32)n
{
    return [self descriptorWithDescriptorType:typeSInt32 bytes:&n length:sizeof n];
}
+ (NSAppleEventDescriptor *)descriptorWithDouble:(double)d
{
    return [self descriptorWithDescriptorType:typeIEEE64BitFloatingPoint bytes:&d length:sizeof d];
}
+ (NSAppleEventDescriptor *)descriptorWithTypeCode:(OSType)code
{
    return [self descriptorWithDescriptorType:typeType bytes:&code length:sizeof code];
}
+ (NSAppleEventDescriptor *)descriptorWithString:(NSString *)s
{
    NSData *d = [s dataUsingEncoding:NSUTF16LittleEndianStringEncoding] ?: [NSData data];
    return [self descriptorWithDescriptorType:typeUnicodeText data:d];
}
+ (NSAppleEventDescriptor *)descriptorWithFileURL:(NSURL *)url
{
    NSData *d = [[url absoluteString] dataUsingEncoding:NSUTF8StringEncoding];
    return d ? [self descriptorWithDescriptorType:typeFileURL data:d] : nil;
}
+ (NSAppleEventDescriptor *)descriptorWithBundleIdentifier:(NSString *)ident
{
    NSData *d = [ident dataUsingEncoding:NSUTF8StringEncoding];
    return d ? [self descriptorWithDescriptorType:typeApplicationBundleID data:d] : nil;
}
+ (NSAppleEventDescriptor *)descriptorWithProcessIdentifier:(pid_t)pid
{
    return [self descriptorWithDescriptorType:typeKernelProcessID bytes:&pid length:sizeof pid];
}
+ (NSAppleEventDescriptor *)currentProcessDescriptor
{
    return [self descriptorWithProcessIdentifier:[[NSProcessInfo processInfo] processIdentifier]];
}
+ (NSAppleEventDescriptor *)appleEventWithEventClass:(AEEventClass)eventClass eventID:(AEEventID)eventID
                                    targetDescriptor:(NSAppleEventDescriptor *)target
                                            returnID:(AEReturnID)returnID
                                       transactionID:(AETransactionID)transactionID
{
    return [[[self alloc] initWithEventClass:eventClass eventID:eventID targetDescriptor:target returnID:returnID
                               transactionID:transactionID] autorelease];
}
+ (NSAppleEventDescriptor *)listDescriptor { return [[[self alloc] initListDescriptor] autorelease]; }
+ (NSAppleEventDescriptor *)recordDescriptor { return [[[self alloc] initRecordDescriptor] autorelease]; }

- (const AEDesc *)aeDesc { return &_desc; }
- (DescType)descriptorType { return _desc.descriptorType; }
- (NSData *)data
{
    Size n = AEGetDescDataSize(&_desc);
    NSMutableData *d = [NSMutableData dataWithLength:(NSUInteger)(n > 0 ? n : 0)];
    if (n > 0)
        AEGetDescData(&_desc, [d mutableBytes], n);
    return d;
}

/* the value coerced to type, into buf; NO when it can't be */
static BOOL value_as(NSAppleEventDescriptor *self, DescType type, void *buf, Size size)
{
    AEDesc c;
    if (AECoerceDesc([self aeDesc], type, &c) != noErr)
        return NO;
    BOOL ok = AEGetDescDataSize(&c) == size && AEGetDescData(&c, buf, size) == noErr;
    AEDisposeDesc(&c);
    return ok;
}
- (Boolean)booleanValue
{
    if (_desc.descriptorType == typeTrue)
        return true;
    if (_desc.descriptorType == typeFalse)
        return false;
    Boolean b = false;
    return value_as(self, typeBoolean, &b, sizeof b) ? b : false;
}
- (OSType)enumCodeValue
{
    OSType v = 0;
    return value_as(self, typeEnumerated, &v, sizeof v) || value_as(self, typeType, &v, sizeof v) ? v : 0;
}
- (OSType)typeCodeValue
{
    OSType v = 0;
    return value_as(self, typeType, &v, sizeof v) || value_as(self, typeEnumerated, &v, sizeof v) ? v : 0;
}
- (SInt32)int32Value
{
    SInt32 v = 0;
    return value_as(self, typeSInt32, &v, sizeof v) ? v : 0;
}
- (double)doubleValue
{
    double v = 0;
    return value_as(self, typeIEEE64BitFloatingPoint, &v, sizeof v) ? v : 0;
}
- (NSString *)stringValue
{
    DescType t = _desc.descriptorType;
    if (t == typeUnicodeText)
        return [[[NSString alloc] initWithData:[self data] encoding:NSUTF16LittleEndianStringEncoding] autorelease];
    if (t == typeUTF8Text || t == typeChar || t == typeFileURL || t == typeApplicationBundleID)
        return [[[NSString alloc] initWithData:[self data] encoding:NSUTF8StringEncoding] autorelease];
    AEDesc c;
    if (AECoerceDesc(&_desc, typeUTF8Text, &c) != noErr)
        return nil;
    NSAppleEventDescriptor *d = [[[NSAppleEventDescriptor alloc] initWithAEDescNoCopy:&c] autorelease];
    return [[[NSString alloc] initWithData:[d data] encoding:NSUTF8StringEncoding] autorelease];
}
- (NSURL *)fileURLValue
{
    NSString *s = [self stringValue];
    if (!s)
        return nil;
    return [s hasPrefix:@"/"] ? [NSURL fileURLWithPath:s] : [NSURL URLWithString:s];
}

static OSType attribute(NSAppleEventDescriptor *self, AEKeyword key, DescType type, Size size)
{
    uint32_t v = 0;
    DescType actual;
    Size got;
    if (AEGetAttributePtr([self aeDesc], key, type, &actual, &v, size, &got) != noErr)
        return 0;
    return v;
}
- (AEEventClass)eventClass { return attribute(self, keyEventClassAttr, typeType, sizeof(AEEventClass)); }
- (AEEventID)eventID { return attribute(self, keyEventIDAttr, typeType, sizeof(AEEventID)); }
- (AEReturnID)returnID
{
    AEReturnID v = 0;
    DescType actual;
    Size got;
    AEGetAttributePtr(&_desc, keyReturnIDAttr, typeSInt16, &actual, &v, sizeof v, &got);
    return v;
}
- (AETransactionID)transactionID
{
    AETransactionID v = 0;
    DescType actual;
    Size got;
    AEGetAttributePtr(&_desc, keyTransactionIDAttr, typeSInt32, &actual, &v, sizeof v, &got);
    return v;
}
- (BOOL)isRecordDescriptor { return AECheckIsRecord(&_desc); }
- (NSInteger)numberOfItems
{
    long n = 0;
    return AECountItems(&_desc, &n) == noErr ? n : 0;
}

static NSAppleEventDescriptor *wrap(AEDesc *d) { return [[[NSAppleEventDescriptor alloc] initWithAEDescNoCopy:d] autorelease]; }

- (void)setParamDescriptor:(NSAppleEventDescriptor *)d forKeyword:(AEKeyword)key
{
    if (d)
        AEPutParamDesc(&_desc, key, [d aeDesc]);
}
- (NSAppleEventDescriptor *)paramDescriptorForKeyword:(AEKeyword)key
{
    AEDesc d;
    return AEGetParamDesc(&_desc, key, typeWildCard, &d) == noErr ? wrap(&d) : nil;
}
- (void)removeParamDescriptorWithKeyword:(AEKeyword)key { AEDeleteParam(&_desc, key); }
- (void)setAttributeDescriptor:(NSAppleEventDescriptor *)d forKeyword:(AEKeyword)key
{
    if (d)
        AEPutAttributeDesc(&_desc, key, [d aeDesc]);
}
- (NSAppleEventDescriptor *)attributeDescriptorForKeyword:(AEKeyword)key
{
    AEDesc d;
    return AEGetAttributeDesc(&_desc, key, typeWildCard, &d) == noErr ? wrap(&d) : nil;
}
- (void)insertDescriptor:(NSAppleEventDescriptor *)d atIndex:(NSInteger)index
{
    if (!d)
        return;
    NSInteger n = [self numberOfItems];
    if (index <= 0 || index > n) {
        AEPutDesc(&_desc, 0, [d aeDesc]);   /* 0 appends */
        return;
    }
    /* the items from index on move up one */
    NSMutableArray *rest = [NSMutableArray array];
    for (NSInteger i = index; i <= n; i++)
        [rest addObject:[self descriptorAtIndex:i]];
    for (NSInteger i = n; i >= index; i--)
        AEDeleteItem(&_desc, i);
    AEPutDesc(&_desc, 0, [d aeDesc]);
    for (NSAppleEventDescriptor *r in rest)
        AEPutDesc(&_desc, 0, [r aeDesc]);
}
- (NSAppleEventDescriptor *)descriptorAtIndex:(NSInteger)index
{
    AEDesc d;
    AEKeyword key;
    return AEGetNthDesc(&_desc, index, typeWildCard, &key, &d) == noErr ? wrap(&d) : nil;
}
- (void)removeDescriptorAtIndex:(NSInteger)index { AEDeleteItem(&_desc, index); }
- (void)setDescriptor:(NSAppleEventDescriptor *)d forKeyword:(AEKeyword)key
{
    if (d)
        AEPutKeyDesc(&_desc, key, [d aeDesc]);
}
- (NSAppleEventDescriptor *)descriptorForKeyword:(AEKeyword)key
{
    AEDesc d;
    return AEGetKeyDesc(&_desc, key, typeWildCard, &d) == noErr ? wrap(&d) : nil;
}
- (void)removeDescriptorWithKeyword:(AEKeyword)key { AEDeleteKeyDesc(&_desc, key); }
- (AEKeyword)keywordForDescriptorAtIndex:(NSInteger)index
{
    AEDesc d;
    AEKeyword key = 0;
    if (AEGetNthDesc(&_desc, index, typeWildCard, &key, &d) != noErr)
        return 0;
    AEDisposeDesc(&d);
    return key;
}
- (NSAppleEventDescriptor *)coerceToDescriptorType:(DescType)type
{
    AEDesc d;
    return AECoerceDesc(&_desc, type, &d) == noErr ? wrap(&d) : nil;
}
- (BOOL)isEqual:(id)other
{
    return other == self || ([other isKindOfClass:[NSAppleEventDescriptor class]] &&
                             [other descriptorType] == _desc.descriptorType && [[other data] isEqual:[self data]]);
}
- (NSUInteger)hash { return _desc.descriptorType ^ [[self data] hash]; }
- (NSString *)description
{
    DescType t = _desc.descriptorType;
    char c[5] = {(char)(t >> 24), (char)(t >> 16), (char)(t >> 8), (char)t, 0};
    return [NSString stringWithFormat:@"<NSAppleEventDescriptor: '%s' %@>", c,
                                      t == typeUnicodeText || t == typeUTF8Text ? [self stringValue] : [self data]];
}
@end

/* ---- the handlers ------------------------------------------------------------------------- */

@implementation NSAppleEventManager {
    NSMutableDictionary *_handlers;   /* @[class, id] -> @[handler (not retained), selector] */
    NSAppleEventDescriptor *_current, *_currentReply;
}
+ (NSAppleEventManager *)sharedAppleEventManager
{
    static NSAppleEventManager *shared;
    @synchronized(self) {
        if (!shared)
            shared = [[NSAppleEventManager alloc] init];
    }
    return shared;
}
- (instancetype)init
{
    if ((self = [super init]))
        _handlers = [[NSMutableDictionary alloc] init];
    return self;
}
static id handler_key(AEEventClass cls, AEEventID ident) { return @[ @(cls), @(ident) ]; }
- (void)setEventHandler:(id)handler andSelector:(SEL)sel forEventClass:(AEEventClass)cls andEventID:(AEEventID)ident
{
    if (!handler || !sel)
        return;
    _handlers[handler_key(cls, ident)] =
        @[ [NSValue valueWithNonretainedObject:handler], NSStringFromSelector(sel) ];
}
- (void)removeEventHandlerForEventClass:(AEEventClass)cls andEventID:(AEEventID)ident
{
    [_handlers removeObjectForKey:handler_key(cls, ident)];
}
- (NSAppleEventDescriptor *)currentAppleEvent { return _current; }
- (NSAppleEventDescriptor *)currentReplyAppleEvent { return _currentReply; }
- (OSErr)dispatchRawAppleEvent:(const AppleEvent *)event withRawReply:(AppleEvent *)reply
                 handlerRefCon:(SRefCon)refCon
{
    if (!event)
        return errAEEventNotHandled;
    AEDesc copy;
    AEDuplicateDesc(event, &copy);
    NSAppleEventDescriptor *e = [[[NSAppleEventDescriptor alloc] initWithAEDescNoCopy:&copy] autorelease];
    NSArray *h = _handlers[handler_key([e eventClass], [e eventID])];
    if (!h)
        h = _handlers[handler_key([e eventClass], typeWildCard)] ?: _handlers[handler_key(typeWildCard, typeWildCard)];
    if (!h)
        return errAEEventNotHandled;
    NSAppleEventDescriptor *r = [NSAppleEventDescriptor nullDescriptor];
    if (reply && reply->descriptorType != typeNull) {
        AEDesc rc;
        AEDuplicateDesc(reply, &rc);
        r = [[[NSAppleEventDescriptor alloc] initWithAEDescNoCopy:&rc] autorelease];
    }
    NSAppleEventDescriptor *outer = _current, *outerReply = _currentReply;
    _current = e;
    _currentReply = r;
    ((void (*)(id, SEL, id, id))objc_msgSend)([h[0] nonretainedObjectValue], NSSelectorFromString(h[1]), e, r);
    _current = outer;
    _currentReply = outerReply;
    return noErr;
}
@end
