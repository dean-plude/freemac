/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry test (freemac 1.219, Ferry 0.43.0): string encodings, as Hex Fiend,
 * Sequel Pro and Flycut use them. The list of available encodings and their
 * names; converting to and from Latin-1, Mac Roman, Windows-1252, the
 * UTF-16 and UTF-32 forms, Shift JIS and the non-lossy ASCII escapes; what
 * fails strictly and what a lossy conversion gives; the byte counts; reading
 * a file whose encoding is found from its bytes; and the Core Foundation
 * names, IANA names and Windows code pages. */
#import <Foundation/Foundation.h>
#include <unistd.h>

static const char *yn(BOOL b) { return b ? "yes" : "no"; }

static void hex(const char *label, NSData *d)
{
    printf("%s:", label);
    if (!d) {
        printf(" (nil)\n");
        return;
    }
    const unsigned char *b = [d bytes];
    for (NSUInteger i = 0; i < [d length]; i++)
        printf(" %02x", b[i]);
    printf("\n");
}

static void show(const char *label, NSString *s)
{
    printf("%s: ", label);
    if (!s) {
        printf("(nil)\n");
        return;
    }
    for (NSUInteger i = 0; i < [s length]; i++) {
        unichar c = [s characterAtIndex:i];
        if (c >= 0x20 && c < 0x7f)
            printf("%c", c);
        else
            printf("<U+%04X>", c);
    }
    printf("\n");
}

int main(void)
{
    @autoreleasepool {
        /* What is offered. */
        const NSStringEncoding *list = [NSString availableStringEncodings];
        int n = 0, utf8 = 0, latin1 = 0, sjis = 0;
        for (; list[n]; n++) {
            if (list[n] == NSUTF8StringEncoding)
                utf8 = 1;
            if (list[n] == NSISOLatin1StringEncoding)
                latin1 = 1;
            if (list[n] == NSShiftJISStringEncoding)
                sjis = 1;
        }
        printf("available: more than 20 %s, UTF-8 %s, Latin-1 %s, Shift JIS %s\n", yn(n > 20), yn(utf8), yn(latin1),
               yn(sjis));
        printf("names: %s / %s / %s\n", [[NSString localizedNameOfStringEncoding:NSUTF8StringEncoding] UTF8String],
               [[NSString localizedNameOfStringEncoding:NSMacOSRomanStringEncoding] UTF8String],
               [[NSString localizedNameOfStringEncoding:NSWindowsCP1252StringEncoding] UTF8String]);
        printf("default C string encoding is UTF-8: %s\n", yn([NSString defaultCStringEncoding] == NSUTF8StringEncoding));

        NSString *cafe = @"café – €5";
        hex("utf8", [cafe dataUsingEncoding:NSUTF8StringEncoding]);
        hex("latin1 strict", [cafe dataUsingEncoding:NSISOLatin1StringEncoding]);
        hex("latin1 lossy", [cafe dataUsingEncoding:NSISOLatin1StringEncoding allowLossyConversion:YES]);
        hex("cp1252", [cafe dataUsingEncoding:NSWindowsCP1252StringEncoding]);
        hex("mac roman", [@"café –" dataUsingEncoding:NSMacOSRomanStringEncoding]);
        hex("ascii strict", [cafe dataUsingEncoding:NSASCIIStringEncoding]);
        hex("ascii lossy", [cafe dataUsingEncoding:NSASCIIStringEncoding allowLossyConversion:YES]);
        hex("utf16 (with its byte-order mark)", [@"Ab" dataUsingEncoding:NSUTF16StringEncoding]);
        hex("utf16 big-endian", [@"Ab" dataUsingEncoding:NSUTF16BigEndianStringEncoding]);
        hex("utf16 little-endian", [@"Ab" dataUsingEncoding:NSUTF16LittleEndianStringEncoding]);
        hex("utf32 big-endian", [@"A\U0001F600" dataUsingEncoding:NSUTF32BigEndianStringEncoding]);
        hex("shift jis", [@"日本" dataUsingEncoding:NSShiftJISStringEncoding]);
        hex("non-lossy ascii", [@"aé€" dataUsingEncoding:NSNonLossyASCIIStringEncoding]);
        printf("can convert to latin1: %s, to cp1252: %s, to ascii: %s\n",
               yn([cafe canBeConvertedToEncoding:NSISOLatin1StringEncoding]),
               yn([cafe canBeConvertedToEncoding:NSWindowsCP1252StringEncoding]),
               yn([cafe canBeConvertedToEncoding:NSASCIIStringEncoding]));
        printf("bytes in UTF-8 %lu, in UTF-16 %lu, at most in UTF-8 %s\n",
               (unsigned long)[cafe lengthOfBytesUsingEncoding:NSUTF8StringEncoding],
               (unsigned long)[cafe lengthOfBytesUsingEncoding:NSUTF16StringEncoding],
               yn([cafe maximumLengthOfBytesUsingEncoding:NSUTF8StringEncoding] >=
                  [cafe lengthOfBytesUsingEncoding:NSUTF8StringEncoding]));

        /* And back. */
        const unsigned char latin[] = {'n', 0xe4, 'h', 'e'};
        show("from latin1", [[NSString alloc] initWithBytes:latin length:4 encoding:NSISOLatin1StringEncoding]);
        const unsigned char roman[] = {'c', 'a', 'f', 0x8e, ' ', 0xd0};
        show("from mac roman", [[NSString alloc] initWithBytes:roman length:6 encoding:NSMacOSRomanStringEncoding]);
        const unsigned char win[] = {0x80, '5', ' ', 0x93, 'q', 0x94};
        show("from cp1252", [[NSString alloc] initWithBytes:win length:6 encoding:NSWindowsCP1252StringEncoding]);
        const unsigned char bad[] = {'o', 'k', 0xff, 0xfe};
        show("bad utf8", [[NSString alloc] initWithBytes:bad length:4 encoding:NSUTF8StringEncoding]);
        const unsigned char u16[] = {0xff, 0xfe, 'H', 0, 'i', 0};
        show("utf16 with a byte-order mark", [[NSString alloc] initWithBytes:u16 length:6 encoding:NSUTF16StringEncoding]);
        const unsigned char u16be[] = {0, 'H', 0x20, 0xac};
        show("utf16 big-endian", [[NSString alloc] initWithBytes:u16be length:4 encoding:NSUTF16BigEndianStringEncoding]);
        const unsigned char sj[] = {0x93, 0xfa, 0x96, 0x7b};
        show("from shift jis", [[NSString alloc] initWithBytes:sj length:4 encoding:NSShiftJISStringEncoding]);
        show("from non-lossy ascii", [[NSString alloc] initWithBytes:"a\\351\\u20ac" length:11
                                                            encoding:NSNonLossyASCIIStringEncoding]);
        show("from euc-kr",
             [[NSString alloc] initWithData:[@"한" dataUsingEncoding:CFStringConvertEncodingToNSStringEncoding(
                                                                              kCFStringEncodingEUC_KR)]
                                   encoding:CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingEUC_KR)]);

        /* C strings. */
        char buf[8];
        printf("getCString fits: %s", yn([@"abc" getCString:buf maxLength:sizeof buf encoding:NSASCIIStringEncoding]));
        printf(" (%s), too long: %s\n", buf,
               yn([@"abcdefghij" getCString:buf maxLength:sizeof buf encoding:NSASCIIStringEncoding]));
        const char *c = [@"été" cStringUsingEncoding:NSISOLatin1StringEncoding];
        printf("latin1 C string: %02x %02x %02x %02x\n", (unsigned char)c[0], (unsigned char)c[1],
               (unsigned char)c[2], (unsigned char)c[3]);
        printf("ascii C string of a non-ascii string is NULL: %s\n",
               yn([@"é" cStringUsingEncoding:NSASCIIStringEncoding] == NULL));

        /* getBytes, a piece at a time. */
        unsigned char out[4];
        NSUInteger used = 0;
        NSRange rest;
        BOOL ok = [@"héllo" getBytes:out maxLength:sizeof out usedLength:&used encoding:NSUTF8StringEncoding
                                  options:0 range:NSMakeRange(0, 5) remainingRange:&rest];
        printf("getBytes: %s, used %lu, rest at %lu length %lu\n", yn(ok), (unsigned long)used,
               (unsigned long)rest.location, (unsigned long)rest.length);

        /* Files whose encoding is found from their bytes. */
        char dir[] = "/tmp/ferry-encodings-XXXXXX";
        if (!mkdtemp(dir))
            return 1;
        NSString *d = [NSString stringWithUTF8String:dir];
        NSStringEncoding used_enc = 0;
        NSString *p1 = [d stringByAppendingPathComponent:@"utf8.txt"];
        [[@"über" dataUsingEncoding:NSUTF8StringEncoding] writeToFile:p1 atomically:NO];
        show("read utf8", [NSString stringWithContentsOfFile:p1 usedEncoding:&used_enc error:NULL]);
        printf("  found UTF-8: %s\n", yn(used_enc == NSUTF8StringEncoding));
        NSString *p2 = [d stringByAppendingPathComponent:@"utf16.txt"];
        [[@"über" dataUsingEncoding:NSUTF16StringEncoding] writeToFile:p2 atomically:NO];
        show("read utf16", [NSString stringWithContentsOfFile:p2 usedEncoding:&used_enc error:NULL]);
        printf("  found UTF-16: %s\n", yn(used_enc == NSUTF16StringEncoding));
        NSString *p3 = [d stringByAppendingPathComponent:@"latin.txt"];
        [[NSData dataWithBytes:latin length:4] writeToFile:p3 atomically:NO];
        show("read latin", [NSString stringWithContentsOfFile:p3 usedEncoding:&used_enc error:NULL]);
        printf("  found Windows-1252: %s\n", yn(used_enc == NSWindowsCP1252StringEncoding));
        NSError *err = nil;
        NSString *strict = [NSString stringWithContentsOfFile:p3 encoding:NSUTF8StringEncoding error:&err];
        printf("latin read as utf8: %s, error %ld\n", strict ? "a string" : "nil", (long)[err code]);
        [[NSFileManager defaultManager] removeItemAtPath:d error:NULL];

        /* Core Foundation's side. */
        CFStringEncoding cf = CFStringConvertNSStringEncodingToEncoding(NSWindowsCP1252StringEncoding);
        printf("cf cp1252: 0x%x, IANA %s, code page %u\n", (unsigned)cf,
               [(NSString *)CFStringConvertEncodingToIANACharSetName(cf) UTF8String],
               (unsigned)CFStringConvertEncodingToWindowsCodepage(cf));
        printf("IANA shift_jis -> 0x%x, code page 932 -> 0x%x, UTF-8 -> 0x%x\n",
               (unsigned)CFStringConvertIANACharSetNameToEncoding(CFSTR("shift_jis")),
               (unsigned)CFStringConvertWindowsCodepageToEncoding(932),
               (unsigned)CFStringConvertIANACharSetNameToEncoding(CFSTR("UTF-8")));
        printf("unknown IANA name is invalid: %s\n",
               yn(CFStringConvertIANACharSetNameToEncoding(CFSTR("no-such-set")) == kCFStringEncodingInvalidId));
        printf("cf names: %s / %s\n", [(NSString *)CFStringGetNameOfEncoding(kCFStringEncodingMacRoman) UTF8String],
               [(NSString *)CFStringGetNameOfEncoding(kCFStringEncodingISOLatin2) UTF8String]);
        printf("NS of cf UTF-8 is NSUTF8StringEncoding: %s, of cf Latin-2: 0x%lx\n",
               yn(CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingUTF8) == NSUTF8StringEncoding),
               (unsigned long)CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingISOLatin2));
        printf("system encoding is Mac Roman: %s, available: big5 %s, bogus %s\n",
               yn(CFStringGetSystemEncoding() == kCFStringEncodingMacRoman),
               yn(CFStringIsEncodingAvailable(kCFStringEncodingBig5)), yn(CFStringIsEncodingAvailable(0x7777)));
        CFStringRef s = CFStringCreateWithBytes(NULL, (const UInt8 *)"\xe9t\xe9", 3, kCFStringEncodingISOLatin1, false);
        show("CFStringCreateWithBytes latin1", (NSString *)s);
        UInt8 b[16];
        CFIndex usedBytes = 0;
        CFIndex conv = CFStringGetBytes(s, CFRangeMake(0, 3), kCFStringEncodingUTF8, 0, false, b, sizeof b, &usedBytes);
        printf("CFStringGetBytes to UTF-8: %ld characters, %ld bytes\n", (long)conv, (long)usedBytes);
        conv = CFStringGetBytes(s, CFRangeMake(0, 3), kCFStringEncodingUTF8, 0, false, b, 3, &usedBytes);
        printf("  into 3 bytes: %ld characters, %ld bytes\n", (long)conv, (long)usedBytes);
        conv = CFStringGetBytes(CFSTR("a€b"), CFRangeMake(0, 3), kCFStringEncodingISOLatin1, '?', false, b,
                                sizeof b, &usedBytes);
        printf("  a euro sign to Latin-1 with '?': %ld characters, %.*s\n", (long)conv, (int)usedBytes, b);
        CFRelease(s);
        CFDataRef ext = CFStringCreateExternalRepresentation(NULL, CFSTR("hi"), kCFStringEncodingUTF16, 0);
        hex("external representation in UTF-16", (NSData *)ext);
        CFStringRef back = CFStringCreateFromExternalRepresentation(NULL, ext, kCFStringEncodingUTF16);
        show("and back", (NSString *)back);
        CFRelease(ext);
        CFRelease(back);
    }
    return 0;
}
