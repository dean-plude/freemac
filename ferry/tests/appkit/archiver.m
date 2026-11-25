/* SPDX-License-Identifier: GPL-3.0-or-later
 * NSArchiver and NSUnarchiver (freemac 1.221, Ferry 0.45.0): a class of
 * the program's own coding its values in order, as HexFiend's, KeyCastr's
 * and Sequel Pro's do, objects shared and pointing back at each other,
 * Foundation's collections, and the colours and fonts Sequel Pro keeps in
 * its preferences; class names changed on the way; a keyed archiver given
 * values without keys; and an archive a Mac's NSArchiver wrote, which
 * Ferry doesn't read. */
#import <Cocoa/Cocoa.h>

typedef struct {
    short s;
    double d;
    char c;
} Mixed;

@interface Shape : NSObject <NSCoding>
@property int sides;
@property float scale;
@property double angle;
@property BOOL filled;
@property NSRect frame;
@property (copy) NSString *name;
@property (strong) id friend;
@property (weak) id owner;
@property SEL action;
@property Class kind;
@property Mixed mixed;
@property NSInteger extra;
@end

static BOOL saw_keyed_coding;

@implementation Shape {
    int _corners[3];
    char *_label;
}
+ (void)initialize
{
    if (self == [Shape class])
        [self setVersion:3];
}
- (void)dealloc { free(_label); }
- (void)setLabel:(const char *)label { free(_label); _label = strdup(label); }
- (const char *)label { return _label; }
- (int *)corners { return _corners; }
- (void)encodeWithCoder:(NSCoder *)coder
{
    if ([coder allowsKeyedCoding])
        saw_keyed_coding = YES;
    [coder encodeValueOfObjCType:@encode(int) at:&_sides];
    [coder encodeValuesOfObjCTypes:"fdc", &_scale, &_angle, &_filled];
    [coder encodeRect:_frame];
    [coder encodeObject:_name];
    [coder encodeObject:_friend];
    [coder encodeConditionalObject:_owner];
    [coder encodeValueOfObjCType:@encode(SEL) at:&_action];
    [coder encodeValueOfObjCType:@encode(Class) at:&_kind];
    [coder encodeValueOfObjCType:@encode(Mixed) at:&_mixed];
    [coder encodeArrayOfObjCType:@encode(int) count:3 at:_corners];
    [coder encodeValueOfObjCType:@encode(char *) at:&_label];
    [coder encodeBytes:"\x01\x02\x03" length:3];
    if (_extra)
        [coder encodeValueOfObjCType:@encode(NSInteger) at:&_extra];
}
- (instancetype)initWithCoder:(NSCoder *)coder
{
    if (!(self = [super init]))
        return nil;
    [coder decodeValueOfObjCType:@encode(int) at:&_sides size:sizeof _sides];
    [coder decodeValuesOfObjCTypes:"fdc", &_scale, &_angle, &_filled];
    _frame = [coder decodeRect];
    _name = [coder decodeObject];
    _friend = [coder decodeObject];
    _owner = [coder decodeObject];
    [coder decodeValueOfObjCType:@encode(SEL) at:&_action size:sizeof _action];
    [coder decodeValueOfObjCType:@encode(Class) at:&_kind size:sizeof _kind];
    [coder decodeValueOfObjCType:@encode(Mixed) at:&_mixed size:sizeof _mixed];
    [coder decodeArrayOfObjCType:@encode(int) count:3 at:_corners];
    char *label = NULL;
    [coder decodeValueOfObjCType:@encode(char *) at:&label size:sizeof label];
    if (label)
        _label = strdup(label);
    NSUInteger len = 0;
    const unsigned char *bytes = [coder decodeBytesWithReturnedLength:&len];
    if (len != 3 || bytes[2] != 3)
        printf("bytes came back wrong\n");
    if ([coder isKindOfClass:[NSUnarchiver class]] && ![(NSUnarchiver *)coder isAtEnd])
        [coder decodeValueOfObjCType:@encode(NSInteger) at:&_extra size:sizeof _extra];
    return self;
}
@end

@interface Renamed : NSObject <NSCoding>
@property int value;
@end
@implementation Renamed
- (void)encodeWithCoder:(NSCoder *)coder { [coder encodeValueOfObjCType:"i" at:&_value]; }
- (instancetype)initWithCoder:(NSCoder *)coder
{
    if ((self = [super init]))
        [coder decodeValueOfObjCType:"i" at:&_value size:sizeof _value];
    return self;
}
@end
@interface Replacement : Renamed
@end
@implementation Replacement
@end

static void show(Shape *s)
{
    printf("  %s: sides %d, scale %.2f, angle %.3f, filled %d, frame %s\n", [s.name UTF8String], s.sides, s.scale,
           s.angle, s.filled, [NSStringFromRect(s.frame) UTF8String]);
    printf("  action %s, kind %s, mixed %d %.1f %c, corners %d %d %d, label %s, extra %ld\n",
           s.action ? sel_getName(s.action) : "NULL", s.kind ? class_getName(s.kind) : "Nil", s.mixed.s, s.mixed.d,
           s.mixed.c, [s corners][0], [s corners][1], [s corners][2], [s label] ?: "NULL", (long)s.extra);
}

int main(void)
{
    @autoreleasepool {
        Shape *a = [Shape new], *b = [Shape new];
        a.sides = 3;
        a.scale = 1.5f;
        a.angle = 0.125;
        a.filled = YES;
        a.frame = NSMakeRect(1, 2, 30, 40);
        a.name = @"triangle";
        a.action = @selector(copy:);
        a.kind = [NSString class];
        a.mixed = (Mixed){-7, 2.5, 'x'};
        [a corners][0] = 10, [a corners][1] = -20, [a corners][2] = 30;
        [a setLabel:"three sides"];
        a.extra = 99;
        b.sides = 4;
        b.name = @"square";
        b.mixed = (Mixed){1, 0.5, 'y'};
        b.friend = a;
        b.owner = a;
        a.friend = b; /* round and back */
        [b setLabel:"four"];

        NSData *data = [NSArchiver archivedDataWithRootObject:b];
        printf("archived %s, not a Mac's typedstream %d\n", data.length ? "yes" : "no",
               data.length < 6 || memcmp(data.bytes, "\x04\x0bstre", 6) != 0);
        Shape *back = [NSUnarchiver unarchiveObjectWithData:data];
        printf("back: %s, keyed coding offered %d\n", [NSStringFromClass([back class]) UTF8String],
               saw_keyed_coding);
        show(back);
        show(back.friend);
        printf("  the friend's friend is the same object %d, the owner is the friend %d\n",
               [back.friend friend] == back, back.owner == back.friend);

        /* Foundation's classes, and AppKit's colours and fonts */
        NSDictionary *prefs = @{
            @"colour" : [NSColor colorWithSRGBRed:1 green:0.5 blue:0.25 alpha:1],
            @"font" : [NSFont userFixedPitchFontOfSize:13],
            @"list" : @[ @1, @"two", @3.5, [NSData dataWithBytes:"abc" length:3] ],
            @"when" : [NSDate dateWithTimeIntervalSince1970:86400],
            @"set" : [NSSet setWithObjects:@"x", @"y", nil],
        };
        NSDictionary *got = [NSUnarchiver unarchiveObjectWithData:[NSArchiver archivedDataWithRootObject:prefs]];
        NSColor *colour = got[@"colour"];
        printf("dictionary %lu entries, equal list %d, date %d, set %d\n", (unsigned long)got.count,
               [got[@"list"] isEqual:prefs[@"list"]], [got[@"when"] isEqual:prefs[@"when"]],
               [got[@"set"] isEqual:prefs[@"set"]]);
        printf("colour %.2f %.2f %.2f, font %s %.0f pt\n", colour.redComponent, colour.greenComponent,
               colour.blueComponent, [[got[@"font"] fontName] isEqual:[prefs[@"font"] fontName]] ? "same" : "other",
               [got[@"font"] pointSize]);
        NSColor *one = [NSUnarchiver unarchiveObjectWithData:[NSArchiver archivedDataWithRootObject:[NSColor redColor]]];
        printf("a colour alone: %s\n", [one isKindOfClass:[NSColor class]] ? "a colour" : "not one");

        /* written in steps, several values at the top */
        NSMutableData *steps = [NSMutableData data];
        NSArchiver *w = [[NSArchiver alloc] initForWritingWithMutableData:steps];
        int n = 42;
        [w encodeValueOfObjCType:"i" at:&n];
        [w encodeRootObject:@"root string"];
        [w encodePoint:NSMakePoint(5, 6)];
        printf("archiver data is the given data %d\n", [w archiverData] == steps);
        w = nil;
        NSUnarchiver *r = [[NSUnarchiver alloc] initForReadingWithData:steps];
        int m = 0;
        [r decodeValueOfObjCType:"i" at:&m size:sizeof m];
        NSString *str = [r decodeObject];
        NSPoint pt = [r decodePoint];
        printf("steps: %d, %s, %s, at end %d, keyed %d, version of Shape %ld, of a missing class NSNotFound %d\n", m,
               [str UTF8String], [NSStringFromPoint(pt) UTF8String], [r isAtEnd], [r allowsKeyedCoding],
               (long)[r versionForClassName:@"Shape"], (long)[r versionForClassName:@"NoSuchClass"] == NSNotFound);

        /* class names changed while writing and while reading */
        Renamed *x = [Renamed new];
        x.value = 7;
        [NSArchiver encodeClassName:@"Renamed" intoClassName:@"OldName"];
        NSData *renamed = [NSArchiver archivedDataWithRootObject:x];
        [NSArchiver encodeClassName:@"Renamed" intoClassName:nil];
        [NSUnarchiver decodeClassName:@"OldName" asClassName:@"Replacement"];
        id y = [NSUnarchiver unarchiveObjectWithData:renamed];
        printf("renamed: %s %d, decoded as %s\n", [NSStringFromClass([y class]) UTF8String], [(Renamed *)y value],
               [[NSUnarchiver classNameDecodedForArchiveClassName:@"OldName"] UTF8String]);

        /* a keyed archiver given values without keys */
        a.extra = 0;
        NSData *keyed = [NSKeyedArchiver archivedDataWithRootObject:a requiringSecureCoding:NO error:NULL];
        saw_keyed_coding = NO;
        Shape *k = [NSKeyedUnarchiver unarchivedObjectOfClasses:[NSSet setWithObjects:[Shape class], nil]
                                                        fromData:keyed error:NULL];
        k = k ?: [NSKeyedUnarchiver unarchiveTopLevelObjectWithData:keyed error:NULL];
        printf("keyed archive with unkeyed values: %s, friend %s\n", [k.name UTF8String], [[k.friend name] UTF8String]);

        /* files, a Mac's archive, and things that aren't archives */
        NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"shape.archive"];
        printf("to a file %d, back %s\n", [NSArchiver archiveRootObject:@[ @"in", @"a", @"file" ] toFile:path],
               [[[NSUnarchiver unarchiveObjectWithFile:path] componentsJoinedByString:@" "] UTF8String]);
        static const char mac[] = "\x04\x0bstreamtyped\x81\xe8\x03\x84\x01\x40\x84\x84\x84\x08NSString";
        printf("a Mac's archive gives %s, junk gives %s, nil gives %s\n",
               [NSUnarchiver unarchiveObjectWithData:[NSData dataWithBytes:mac length:sizeof mac]] ? "an object" : "nil",
               [NSUnarchiver unarchiveObjectWithData:[@"junk" dataUsingEncoding:NSUTF8StringEncoding]] ? "an object"
                                                                                                         : "nil",
               [NSUnarchiver unarchiveObjectWithData:nil] ? "an object" : "nil");
    }
    return 0;
}
