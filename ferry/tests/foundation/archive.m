/* NSKeyedArchiver and NSKeyedUnarchiver (added for M5's nib files): an
 * archive written by another program (archive.bplist, made with Python's
 * plistlib by make_archive.py) and archives that Ferry writes and reads
 * back. Built without ARC. */
#import <Foundation/Foundation.h>
#include <stdio.h>
#include <stdlib.h>

@interface Point3 : NSObject <NSSecureCoding>
@property int x, y;
@property double z;
@property (retain) NSString *name;
@property (assign) Point3 *next;
@end

@implementation Point3
+ (BOOL)supportsSecureCoding { return YES; }
- (instancetype)initWithCoder:(NSCoder *)c
{
    if ((self = [super init])) {
        _x = [c decodeIntForKey:@"x"];
        _y = [c decodeIntForKey:@"y"];
        _z = [c decodeDoubleForKey:@"z"];
        _name = [[c decodeObjectOfClass:[NSString class] forKey:@"name"] retain];
        _next = [c decodeObjectForKey:@"next"];
    }
    return self;
}
- (void)encodeWithCoder:(NSCoder *)c
{
    [c encodeInt:_x forKey:@"x"];
    [c encodeInt:_y forKey:@"y"];
    [c encodeDouble:_z forKey:@"z"];
    [c encodeObject:_name forKey:@"name"];
    [c encodeConditionalObject:_next forKey:@"next"];
}
- (NSString *)description
{
    return [NSString stringWithFormat:@"Point3(%d, %d, %g%s%s)", _x, _y, _z, _name ? " " : "",
                                      _name ? _name.UTF8String : ""];
}
- (void)dealloc
{
    [_name release];
    [super dealloc];
}
@end

/* An object that archives as a different class, and one that replaces itself. */
@interface Legacy : Point3
@end
@implementation Legacy
- (Class)classForKeyedArchiver { return [Point3 class]; }
@end

static void show(NSString *label, id v)
{
    printf("%s: %s = %s\n", label.UTF8String, v ? [NSStringFromClass([v classForCoder]) UTF8String] : "nil",
           [[v description] UTF8String]);
}

static const char *kind(id o)
{
    if ([o isKindOfClass:[NSMutableArray class]]) return "mutable array";
    if ([o isKindOfClass:[NSArray class]]) return "array";
    if ([o isKindOfClass:[NSMutableDictionary class]]) return "mutable dictionary";
    if ([o isKindOfClass:[NSDictionary class]]) return "dictionary";
    if ([o isKindOfClass:[NSMutableString class]]) return "mutable string";
    if ([o isKindOfClass:[NSString class]]) return "string";
    return "other";
}

int main(void)
{
    @autoreleasepool {
        /* 1. Reading an archive Ferry didn't write. */
        NSString *dir = [NSString stringWithUTF8String:getenv("FERRY_TEST_DATA") ?: "."];
        NSData *data = [NSData dataWithContentsOfFile:[dir stringByAppendingPathComponent:@"archive.bplist"]];
        printf("fixture %lu bytes\n", (unsigned long)data.length);
        NSKeyedUnarchiver *u = [[NSKeyedUnarchiver alloc] initForReadingFromData:data error:NULL];
        u.requiresSecureCoding = NO;
        NSDictionary *root = [u decodeObjectForKey:NSKeyedArchiveRootObjectKey];
        printf("root is a %s with %lu entries\n", kind(root), (unsigned long)root.count);
        printf("count=%d pi=%g yes=%d\n", [root[@"count"] intValue], [root[@"pi"] doubleValue], [root[@"yes"] boolValue]);
        printf("list is a %s\n", kind(root[@"list"]));
        printf("list: %s, %d, %s\n", [root[@"list"][0] UTF8String], [root[@"list"][1] intValue],
               [[root[@"list"][2] description] UTF8String]);
        NSSet *set = root[@"set"];
        printf("set: %lu items, has a %d, has b %d\n", (unsigned long)set.count, [set containsObject:@"a"],
               [set containsObject:@"b"]);
        printf("when: %g seconds after 2001\n", [root[@"when"] timeIntervalSinceReferenceDate]);
        NSData *bytes = root[@"bytes"];
        const unsigned char *b = bytes.bytes;
        printf("bytes: %lu: %02x %02x %02x\n", (unsigned long)bytes.length, b[0], b[1], b[2]);
        NSMutableString *m = root[@"mutable"];
        printf("mutable: %s, ", kind(m));
        [m appendString:@" more"];
        printf("%s\n", m.UTF8String);
        printf("rect: %s\n", NSStringFromRect([root[@"rect"] rectValue]).UTF8String);
        NSAttributedString *styled = root[@"styled"];
        NSRange r;
        NSDictionary *a = [styled attributesAtIndex:0 effectiveRange:&r];
        printf("styled \"%s\": [%lu,%lu] weight=%s", styled.string.UTF8String, (unsigned long)r.location,
               (unsigned long)r.length, [a[@"weight"] UTF8String]);
        a = [styled attributesAtIndex:3 effectiveRange:&r];
        printf(" [%lu,%lu] %lu attributes\n", (unsigned long)r.location, (unsigned long)r.length, (unsigned long)a.count);
        printf("url: %s host %s\n", [root[@"url"] absoluteString].UTF8String, [root[@"url"] host].UTF8String);
        printf("same object twice: %s\n", root[@"same1"] == root[@"same2"] ? "yes" : "no");
        printf("same object in the list: %s\n", root[@"same1"] == root[@"list"][2] ? "yes" : "no");
        Point3 *loop = root[@"loop"];
        printf("loop: %s, next is itself: %s\n", loop.description.UTF8String, loop.next == loop ? "yes" : "no");
        show(@"missing class", root[@"missing"]);
        printf("error: %s\n", u.error ? "yes" : "no");
        [u release];

        /* 2. Secure decoding refuses an unexpected class. */
        NSError *err = nil;
        id wrong = [NSKeyedUnarchiver unarchivedObjectOfClass:[NSArray class] fromData:data error:&err];
        printf("as an array: %s, error code %ld\n", wrong ? "decoded" : "nil", (long)err.code);
        id right = [NSKeyedUnarchiver unarchivedObjectOfClasses:
                                          [NSSet setWithObjects:[NSDictionary class], [NSArray class], [NSString class],
                                                                [NSNumber class], [Point3 class], [NSSet class],
                                                                [NSDate class], [NSData class], [NSValue class],
                                                                [NSAttributedString class], [NSURL class], nil]
                                                       fromData:data
                                                          error:&err];
        printf("with its classes: %s\n", right ? "decoded" : "nil");

        /* 3. Not an archive. */
        err = nil;
        id junk = [NSKeyedUnarchiver unarchivedObjectOfClass:[NSString class]
                                                    fromData:[@"nonsense" dataUsingEncoding:NSUTF8StringEncoding]
                                                       error:&err];
        printf("junk: %s, error code %ld\n", junk ? "decoded" : "nil", (long)err.code);

        /* 4. Writing and reading back. */
        Point3 *p = [[Point3 alloc] init];
        p.x = 10; p.y = -20; p.z = 0.5; p.name = @"pé";
        p.next = p;
        Legacy *old = [[Legacy alloc] init];
        old.x = 99;
        NSMutableArray *list = [NSMutableArray arrayWithObjects:p, p, old, @"text", @12, @NO, [NSNull null], nil];
        NSDictionary *orig = @{
            @"points" : list,
            @"name" : [NSMutableString stringWithString:@"changeable"],
            @"date" : [NSDate dateWithTimeIntervalSinceReferenceDate:1000.5],
            @"size" : [NSValue valueWithSize:NSMakeSize(3, 4)],
            @"range" : [NSValue valueWithRange:NSMakeRange(5, 6)],
            @"set" : [NSSet setWithObjects:@1, @2, @3, nil],
            @"data" : [NSMutableData dataWithLength:4],
            @"url" : [NSURL URLWithString:@"b/c" relativeToURL:[NSURL URLWithString:@"http://h/a/"]],
        };
        NSData *bin = [NSKeyedArchiver archivedDataWithRootObject:orig requiringSecureCoding:NO error:NULL];
        printf("archive starts %.8s\n", (const char *)bin.bytes);
        NSDictionary *back = [NSKeyedUnarchiver unarchiveTopLevelObjectWithData:bin error:NULL];
        NSArray *pts = back[@"points"];
        printf("points: %s of %lu\n", kind(pts), (unsigned long)pts.count);
        for (id o in pts)
            show(@"  item", o);
        Point3 *q = pts[0];
        printf("shared kept: %s, loop kept: %s\n", pts[0] == pts[1] ? "yes" : "no", q.next == q ? "yes" : "no");
        printf("name: %s \"%s\"\n", kind(back[@"name"]), [back[@"name"] UTF8String]);
        printf("date: %g\n", [back[@"date"] timeIntervalSinceReferenceDate]);
        printf("size: %s range: %s\n", NSStringFromSize([back[@"size"] sizeValue]).UTF8String,
               NSStringFromRange([back[@"range"] rangeValue]).UTF8String);
        printf("set: %lu, data: %s %lu, url: %s\n", (unsigned long)[back[@"set"] count],
               [back[@"data"] isKindOfClass:[NSMutableData class]] ? "mutable" : "plain",
               (unsigned long)[back[@"data"] length], [back[@"url"] absoluteString].UTF8String);
        printf("equal dictionaries apart from points: %s\n",
               [back[@"set"] isEqual:orig[@"set"]] && [back[@"name"] isEqual:orig[@"name"]] ? "yes" : "no");

        /* The archive is a property list in Apple's layout. */
        NSDictionary *plist = [NSPropertyListSerialization propertyListWithData:bin options:0 format:NULL error:NULL];
        printf("$archiver=%s $version=%d $top has root: %s\n", [plist[@"$archiver"] UTF8String],
               [plist[@"$version"] intValue], plist[@"$top"][@"root"] ? "yes" : "no");
        NSMutableSet *names = [NSMutableSet set];
        for (id o in plist[@"$objects"])
            if ([o isKindOfClass:[NSDictionary class]] && o[@"$classname"])
                [names addObject:o[@"$classname"]];
        printf("classes: %s\n",
               [[[names allObjects] sortedArrayUsingSelector:@selector(compare:)] componentsJoinedByString:@" "].UTF8String);

        /* XML output, and class names swapped both ways. */
        NSMutableData *xml = [NSMutableData data];
        NSKeyedArchiver *ar = [[NSKeyedArchiver alloc] initForWritingWithMutableData:xml];
        ar.outputFormat = NSPropertyListXMLFormat_v1_0;
        [ar setClassName:@"RenamedPoint" forClass:[Point3 class]];
        [ar encodeObject:p forKey:@"p"];
        [ar encodeInt:7 forKey:@"seven"];
        [ar encodeBool:YES forKey:@"flag"];
        [ar encodeRect:NSMakeRect(1, 2, 3, 4) forKey:@"r"];
        [ar finishEncoding];
        NSString *text = [[NSString alloc] initWithData:xml encoding:NSUTF8StringEncoding];
        printf("xml has CF$UID: %s, RenamedPoint: %s\n", [text containsString:@"CF$UID"] ? "yes" : "no",
               [text containsString:@"RenamedPoint"] ? "yes" : "no");
        [text release];
        NSKeyedUnarchiver *un = [[NSKeyedUnarchiver alloc] initForReadingFromData:xml error:NULL];
        un.requiresSecureCoding = NO;
        [un setClass:[Point3 class] forClassName:@"RenamedPoint"];
        show(@"renamed", [un decodeObjectForKey:@"p"]);
        printf("seven=%d flag=%d has r=%d r=%s has nothing=%d\n", [un decodeIntForKey:@"seven"],
               [un decodeBoolForKey:@"flag"], [un containsValueForKey:@"r"],
               NSStringFromRect([un decodeRectForKey:@"r"]).UTF8String, [un containsValueForKey:@"nothing"]);
        [un release];
        [ar release];
        [p release];
        [old release];
    }
    return 0;
}
