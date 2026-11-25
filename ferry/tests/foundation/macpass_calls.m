/* SPDX-License-Identifier: GPL-3.0-or-later
 * What MacPass, MacDown and their frameworks (KissXML, KeePassKit,
 * TransformerKit, HNHUi, Sparkle) call in Foundation, CoreFoundation,
 * CommonCrypto, Security and libSystem (freemac 1.225, Ferry 0.49.0). */
@import Darwin;
@import ObjectiveC;
#import <Foundation/Foundation.h>
#import <CommonCrypto/CommonDigest.h>
#import <Security/Security.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#include <xlocale.h>

static void hex(const char *what, const unsigned char *md, int n)
{
    printf("%s ", what);
    for (int i = 0; i < n; i++)
        printf("%02x", md[i]);
    printf("\n");
}

/* a group that gives its entries only by count and index, as KeePassKit's does */
@interface Shelf : NSObject {
    NSMutableArray *_books;
}
@end
@implementation Shelf
- (instancetype)init
{
    if ((self = [super init]))
        _books = [@[ @"Emma", @"Persuasion" ] mutableCopy];
    return self;
}
- (NSUInteger)countOfTitles { return _books.count; }
- (id)objectInTitlesAtIndex:(NSUInteger)i { return _books[i]; }
- (void)insertObject:(id)o inTitlesAtIndex:(NSUInteger)i { [_books insertObject:o atIndex:i]; }
- (void)removeObjectFromTitlesAtIndex:(NSUInteger)i { [_books removeObjectAtIndex:i]; }
- (NSUInteger)countOfAuthors { return 1; }
- (NSEnumerator *)enumeratorOfAuthors { return @[ @"Austen" ].objectEnumerator; }
- (id)memberOfAuthors:(id)o { return [o isEqual:@"Austen"] ? @"Austen" : nil; }
- (NSUInteger)countOfPages { return 3; }
- (NSArray *)pagesAtIndexes:(NSIndexSet *)ix
{
    NSMutableArray *a = [NSMutableArray array];
    [ix enumerateIndexesUsingBlock:^(NSUInteger i, BOOL *stop) { [a addObject:@(i + 1)]; }];
    return a;
}
@end

int main(void)
{
    @autoreleasepool {
        /* modules */
        printf("Darwin: %zu, ObjectiveC: %s\n", strlen("seven"), class_getName([NSObject class]));

        /* KVC through indexed and set accessors */
        Shelf *shelf = [Shelf new];
        NSArray *titles = [shelf valueForKey:@"titles"];
        printf("titles: %lu, %s, %s\n", (unsigned long)titles.count, [titles[0] UTF8String],
               [[titles componentsJoinedByString:@"+"] UTF8String]);
        [[shelf mutableArrayValueForKey:@"titles"] addObject:@"Sanditon"];
        printf("after adding: %s\n", [[[shelf valueForKey:@"titles"] componentsJoinedByString:@"+"] UTF8String]);
        NSSet *authors = [shelf valueForKey:@"authors"];
        printf("authors: %lu, member %s, isSet %d\n", (unsigned long)authors.count,
               [[authors member:@"Austen"] UTF8String], [authors isKindOfClass:[NSSet class]]);
        printf("pages: %s\n", [[[shelf valueForKey:@"pages"] componentsJoinedByString:@","] UTF8String]);
        printf("titles copy: %s\n", [[[[shelf valueForKey:@"titles"] copy] description] isEqual:@"(\n    Emma,\n    Persuasion,\n    Sanditon\n)"] ? "same" : "different");
        @try {
            [shelf valueForKey:@"nothing"];
        } @catch (NSException *e) {
            printf("nothing: %s\n", e.name.UTF8String);
        }

        /* values */
        NSRect r = NSMakeRect(1, 2, 3, 4);
        NSValue *v = [NSValue valueWithBytes:&r objCType:@encode(NSRect)];
        NSRect back;
        [v getValue:&back size:sizeof back];
        printf("value: %s %g %g %g %g, equal %d, boxed equal %d\n", v.objCType, back.origin.x, back.origin.y,
               back.size.width, back.size.height, [v isEqualToValue:[NSValue valueWithRect:r]],
               [@(r) isEqualToValue:v]);
        int pair[2] = {7, 9};
        NSValue *pv = [NSValue value:pair withObjCType:@encode(int[2])];
        int pback[2] = {0, 0};
        [pv getValue:pback];
        printf("array value: %s %d %d\n", pv.objCType, pback[0], pback[1]);

        /* URL components */
        NSURLComponents *c = [NSURLComponents componentsWithString:@"https://user:pw@example.com:8080/a%20b/c?x=1&y=two%20words#frag"];
        printf("components: %s %s %s %s %ld %s %s %s %s\n", c.scheme.UTF8String, c.user.UTF8String, c.password.UTF8String,
               c.host.UTF8String, (long)c.port.integerValue, c.path.UTF8String, c.percentEncodedPath.UTF8String,
               c.query.UTF8String, c.fragment.UTF8String);
        for (NSURLQueryItem *q in c.queryItems)
            printf("  item %s = %s\n", q.name.UTF8String, q.value.UTF8String);
        printf("  host at %lu+%lu, port at %lu+%lu\n", (unsigned long)c.rangeOfHost.location,
               (unsigned long)c.rangeOfHost.length, (unsigned long)c.rangeOfPort.location,
               (unsigned long)c.rangeOfPort.length);
        NSURLComponents *made = [NSURLComponents new];
        made.scheme = @"http";
        made.host = @"localhost";
        made.path = @"/a b";
        made.queryItems = @[ [NSURLQueryItem queryItemWithName:@"q" value:@"x&y"] ];
        printf("made: %s\n", made.URL.absoluteString.UTF8String);

        /* binary search and other collection calls */
        NSArray *sorted = @[ @1, @3, @3, @5 ];
        NSComparator cmp = ^NSComparisonResult(id a, id b) { return [a compare:b]; };
        NSRange all = NSMakeRange(0, sorted.count);
        printf("search: first %lu, last %lu, insert 4 at %lu, insert 3 after at %lu, 2 %s\n",
               (unsigned long)[sorted indexOfObject:@3 inSortedRange:all options:NSBinarySearchingFirstEqual usingComparator:cmp],
               (unsigned long)[sorted indexOfObject:@3 inSortedRange:all options:NSBinarySearchingLastEqual usingComparator:cmp],
               (unsigned long)[sorted indexOfObject:@4 inSortedRange:all options:NSBinarySearchingInsertionIndex usingComparator:cmp],
               (unsigned long)[sorted indexOfObject:@3 inSortedRange:all
                                            options:NSBinarySearchingInsertionIndex | NSBinarySearchingLastEqual
                                    usingComparator:cmp],
               [sorted indexOfObject:@2 inSortedRange:all options:0 usingComparator:cmp] == NSNotFound ? "not found" : "found");
        NSIndexSet *odd = [@[ @1, @2, @3, @4, @5 ] indexesOfObjectsWithOptions:NSEnumerationReverse
                                                                  passingTest:^BOOL(id o, NSUInteger i, BOOL *s) { return [o intValue] % 2; }];
        printf("common: %s, %lu odd from %lu to %lu\n", [[sorted firstObjectCommonWithArray:@[ @9, @5 ]] description].UTF8String,
               (unsigned long)odd.count, (unsigned long)odd.firstIndex, (unsigned long)odd.lastIndex);
        NSDictionary *d = [[NSDictionary alloc] initWithObjects:@[ @"one", @"two" ] forKeys:@[ @1, @2 ]];
        printf("objects for keys: %s\n",
               [[[d objectsForKeys:@[ @2, @3, @1 ] notFoundMarker:@"-"] componentsJoinedByString:@" "] UTF8String]);

        /* attributed strings' mutable string */
        NSMutableAttributedString *as = [[NSMutableAttributedString alloc] initWithString:@"ab" attributes:@{ @"k": @"v" }];
        [as.mutableString appendString:@"c"];
        [as.mutableString replaceCharactersInRange:NSMakeRange(0, 1) withString:@"A"];
        NSRange er;
        printf("mutableString: %s, attribute at 2 %s over %lu\n", as.string.UTF8String,
               [[as attribute:@"k" atIndex:2 effectiveRange:&er] UTF8String], (unsigned long)er.length);

        /* transforms */
        printf("transforms: %s | %s | %s | %s | to latin %s\n",
               [@"Ångström café" stringByApplyingTransform:NSStringTransformStripDiacritics reverse:NO].UTF8String,
               [@"ＡＢＣ１２３" stringByApplyingTransform:NSStringTransformFullwidthToHalfwidth reverse:NO].UTF8String,
               [@"<é>" stringByApplyingTransform:NSStringTransformToXMLHex reverse:NO].UTF8String,
               [@"&#x3C;&#xE9;&#x3E;" stringByApplyingTransform:NSStringTransformToXMLHex reverse:YES].UTF8String,
               [@"Москва" stringByApplyingTransform:NSStringTransformToLatin reverse:NO] ? "made" : "not made");
        /* full case mapping: one character can become two */
        printf("case: %s %s %s %s | %s\n", [@"Straße" uppercaseString].UTF8String, [@"ﬁx" uppercaseString].UTF8String,
               [@"ǅ" lowercaseString].UTF8String, [@"ΣΟΦΊΑ ÿ" lowercaseString].UTF8String,
               [@"hello wORLD\tñandú-bird" capitalizedString].UTF8String);
        CFMutableStringRef up = CFStringCreateMutableCopy(NULL, 0, CFSTR("Maß"));
        CFStringUppercase(up, NULL);
        printf("CFStringUppercase: %s\n", [(__bridge NSString *)up UTF8String]);
        CFRelease(up);
        CFMutableStringRef ms = CFStringCreateMutableCopy(NULL, 0, CFSTR("naïve"));
        Boolean ok = CFStringTransform(ms, NULL, kCFStringTransformStripCombiningMarks, false);
        printf("CFStringTransform: %d %s\n", ok, [(__bridge NSString *)ms UTF8String]);
        CFRelease(ms);

        /* CF mutable data */
        CFMutableDataRef md = CFDataCreateMutable(NULL, 0);
        CFDataAppendBytes(md, (const UInt8 *)"hello world", 11);
        CFDataReplaceBytes(md, CFRangeMake(0, 5), (const UInt8 *)"HELLO!", 6);
        CFDataDeleteBytes(md, CFRangeMake(6, 1));
        CFDataIncreaseLength(md, 1);
        printf("CFMutableData: %ld \"%.*s\" last %d\n", (long)CFDataGetLength(md), (int)CFDataGetLength(md) - 1,
               (const char *)CFDataGetBytePtr(md), CFDataGetBytePtr(md)[CFDataGetLength(md) - 1]);
        CFRelease(md);

        /* Apple event descriptors */
        NSAppleEventDescriptor *list = [NSAppleEventDescriptor listDescriptor];
        [list insertDescriptor:[NSAppleEventDescriptor descriptorWithString:@"first"] atIndex:0];
        [list insertDescriptor:[NSAppleEventDescriptor descriptorWithInt32:42] atIndex:0];
        printf("list: %ld items, 1 %s, 2 %d\n", (long)list.numberOfItems,
               [[list descriptorAtIndex:1] stringValue].UTF8String, [[list descriptorAtIndex:2] int32Value]);
        NSAppleEventDescriptor *rec = [NSAppleEventDescriptor recordDescriptor];
        [rec setDescriptor:[NSAppleEventDescriptor descriptorWithBoolean:YES] forKeyword:'abcd'];
        printf("record: %d, %d, %s\n", rec.isRecordDescriptor, [rec descriptorForKeyword:'abcd'].booleanValue,
               [rec descriptorForKeyword:'none'] ? "has none" : "no none");

        /* uniform types */
        UTType *txtType = [UTType typeWithFilenameExtension:@"txt"];
        printf("types: %s, %s, conforms to text %d, plain text %s, png %s\n", txtType.identifier.UTF8String,
               txtType.preferredFilenameExtension.UTF8String, [txtType conformsToType:UTTypeText],
               UTTypePlainText.identifier.UTF8String, [UTType typeWithMIMEType:@"image/png"].identifier.UTF8String);

        /* CommonCrypto's MD2 and MD4, with RFC 1319 and RFC 1320's examples */
        unsigned char out[16];
        hex("MD2(\"\")", CC_MD2("", 0, out), 16);
        hex("MD2(\"abc\")", CC_MD2("abc", 3, out), 16);
        hex("MD4(\"\")", CC_MD4("", 0, out), 16);
        hex("MD4(\"abc\")", CC_MD4("abc", 3, out), 16);
        CC_MD4_CTX m4;
        CC_MD4_Init(&m4);
        CC_MD4_Update(&m4, "message ", 8);
        CC_MD4_Update(&m4, "digest", 6);
        CC_MD4_Final(out, &m4);
        hex("MD4(\"message digest\")", out, 16);

        /* strptime_l */
        struct tm tm = {0};
        locale_t loc = newlocale(LC_ALL_MASK, "C", NULL);
        const char *end = strptime_l("2026-11-25 13:45 rest", "%Y-%m-%d %H:%M", &tm, loc);
        printf("strptime_l: %d-%d-%d %d:%d, rest \"%s\"\n", tm.tm_year + 1900, tm.tm_mon + 1, tm.tm_mday, tm.tm_hour,
               tm.tm_min, end ? end : "(null)");
        freelocale(loc);

        /* Security's encode and decode transforms, with RFC 4648's examples */
        const char *words[] = {"", "f", "fo", "foo", "foob", "fooba", "foobar"};
        CFStringRef kinds[] = {kSecBase64Encoding, kSecBase32Encoding, kSecBase32HexEncoding};
        const char *kindNames[] = {"base64", "base32", "base32hex"};
        for (int k = 0; k < 3; k++) {
            printf("%s:", kindNames[k]);
            for (int w = 0; w < 7; w++) {
                NSData *in = [NSData dataWithBytes:words[w] length:strlen(words[w])];
                CFErrorRef err = NULL;
                SecTransformRef enc = SecEncodeTransformCreate(kinds[k], &err);
                SecTransformSetAttribute(enc, kSecTransformInputAttributeName, (__bridge CFDataRef)in, &err);
                NSData *coded = CFBridgingRelease(SecTransformExecute(enc, &err));
                CFRelease(enc);
                SecTransformRef dec = SecDecodeTransformCreate(kinds[k], &err);
                SecTransformSetAttribute(dec, kSecTransformInputAttributeName, (__bridge CFDataRef)coded, &err);
                NSData *plain = CFBridgingRelease(SecTransformExecute(dec, &err));
                CFRelease(dec);
                printf(" \"%.*s\"%s", (int)coded.length, (const char *)coded.bytes, [plain isEqual:in] ? "" : "(!)");
            }
            printf("\n");
        }
        CFErrorRef bad = NULL;
        SecTransformRef none = SecEncodeTransformCreate(CFSTR("rot13"), &bad);
        printf("unknown encoding: %s, error %s\n", none ? "made" : "refused", bad ? "set" : "unset");
        if (bad)
            CFRelease(bad);
        NSData *longIn = [NSMutableData dataWithLength:60];
        CFErrorRef lerr = NULL;
        SecTransformRef lt = SecEncodeTransformCreate(kSecBase64Encoding, &lerr);
        SecTransformSetAttribute(lt, kSecEncodeLineLengthAttribute, (__bridge CFNumberRef)@(kSecLineLength64), &lerr);
        SecTransformSetAttribute(lt, kSecTransformInputAttributeName, (__bridge CFDataRef)longIn, &lerr);
        NSData *lines = CFBridgingRelease(SecTransformExecute(lt, &lerr));
        CFRelease(lt);
        NSString *ls = [[NSString alloc] initWithData:lines encoding:NSUTF8StringEncoding];
        NSArray *pieces = [[ls componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]
            filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"length > 0"]];
        printf("64-column lines: %lu, first %lu wide, %lu characters in all\n", (unsigned long)pieces.count,
               (unsigned long)[pieces.firstObject length], (unsigned long)[[pieces componentsJoinedByString:@""] length]);

        /* access control, and keys Ferry doesn't make */
        CFErrorRef acErr = NULL;
        SecAccessControlRef ac = SecAccessControlCreateWithFlags(NULL, kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
                                                                 kSecAccessControlUserPresence, &acErr);
        printf("access control: %s, type %s\n", ac ? "made" : "refused",
               ac && CFGetTypeID(ac) == SecAccessControlGetTypeID() ? "SecAccessControl" : "other");
        if (ac)
            CFRelease(ac);
        SecAccessControlRef badAc = SecAccessControlCreateWithFlags(NULL, CFSTR("nowhere"), 0, &acErr);
        printf("bad protection: %s, error %s\n", badAc ? "made" : "refused", acErr ? "set" : "unset");
        if (acErr)
            CFRelease(acErr);
        CFErrorRef keyErr = NULL;
        SecKeyRef key = SecKeyCreateRandomKey((__bridge CFDictionaryRef)@{ (__bridge id)kSecAttrKeyType: (__bridge id)kSecAttrKeyTypeRSA,
                                                                           (__bridge id)kSecAttrKeySizeInBits: @2048 },
                                              &keyErr);
        printf("random key: %s, error %ld\n", key ? "made" : "none", keyErr ? (long)CFErrorGetCode(keyErr) : 0L);
        if (keyErr)
            CFRelease(keyErr);
    }
    return 0;
}
