/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry test (freemac 1.219, Ferry 0.43.0): working through text, as
 * MacDown, Sequel Pro and Flycut do. Lines and paragraphs around a range
 * (with \n, \r\n, \r and U+2028), substrings enumerated by line, paragraph,
 * word, sentence and composed character (forwards, backwards and stopped
 * early), composed character sequences with combining marks and surrogate
 * pairs, the four Unicode normalization forms, searching for characters
 * from a set (backwards, anchored, in a range), and the older percent
 * escapes. */
#import <Foundation/Foundation.h>

static void show(const char *label, NSString *s)
{
    printf("%s: ", label);
    for (NSUInteger i = 0; i < [s length]; i++) {
        unichar c = [s characterAtIndex:i];
        if (c >= 0x20 && c < 0x7f)
            printf("%c", c);
        else if (c == '\n')
            printf("\\n");
        else if (c == '\r')
            printf("\\r");
        else
            printf("<U+%04X>", c);
    }
    printf("\n");
}
static void range(const char *label, NSRange r)
{
    printf("%s: {%lu, %lu}\n", label, (unsigned long)r.location, (unsigned long)r.length);
}

static void enumerate(const char *label, NSString *s, NSStringEnumerationOptions opts)
{
    printf("%s:", label);
    [s enumerateSubstringsInRange:NSMakeRange(0, [s length])
                          options:opts
                       usingBlock:^(NSString *sub, NSRange r, NSRange enclosing, BOOL *stop) {
                           printf(" [");
                           for (NSUInteger i = 0; i < [sub length]; i++) {
                               unichar c = [sub characterAtIndex:i];
                               if (c >= 0x20 && c < 0x7f)
                                   printf("%c", c);
                               else
                                   printf("<%04X>", c);
                           }
                           printf("]%lu+%lu/%lu+%lu", (unsigned long)r.location, (unsigned long)r.length,
                                  (unsigned long)enclosing.location, (unsigned long)enclosing.length);
                       }];
    printf("\n");
}

int main(void)
{
    @autoreleasepool {
        NSString *t = @"one\ntwo\r\nthree\rfour five";
        NSUInteger start, end, contentsEnd;
        [t getLineStart:&start end:&end contentsEnd:&contentsEnd forRange:NSMakeRange(5, 0)];
        printf("line around 5: start %lu end %lu contents end %lu\n", (unsigned long)start, (unsigned long)end,
               (unsigned long)contentsEnd);
        range("line range of {2, 4}", [t lineRangeForRange:NSMakeRange(2, 4)]);
        range("line range at the end", [t lineRangeForRange:NSMakeRange([t length], 0)]);
        range("line range of four", [t lineRangeForRange:NSMakeRange(16, 1)]);
        range("paragraph range of four", [t paragraphRangeForRange:NSMakeRange(16, 1)]);
        [t getParagraphStart:&start end:&end contentsEnd:&contentsEnd forRange:NSMakeRange(0, 1)];
        printf("paragraph of one: start %lu end %lu contents end %lu\n", (unsigned long)start, (unsigned long)end,
               (unsigned long)contentsEnd);

        enumerate("lines", t, NSStringEnumerationByLines);
        enumerate("paragraphs", t, NSStringEnumerationByParagraphs);
        enumerate("lines backwards", @"a\nb\nc", NSStringEnumerationByLines | NSStringEnumerationReverse);
        enumerate("words", @"Hello, wide world! It's 3.5 o'clock.", NSStringEnumerationByWords);
        enumerate("sentences", @"First one. Second? Third!", NSStringEnumerationBySentences);
        enumerate("composed", @"éa\U0001F600", NSStringEnumerationByComposedCharacterSequences);
        __block int seen = 0;
        [@"a b c d" enumerateSubstringsInRange:NSMakeRange(0, 7)
                                       options:NSStringEnumerationByWords
                                    usingBlock:^(NSString *sub, NSRange r, NSRange e, BOOL *stop) {
                                        if (++seen == 2)
                                            *stop = YES;
                                    }];
        printf("stopped after %d words\n", seen);
        __block BOOL nilSub = NO;
        [@"x y" enumerateSubstringsInRange:NSMakeRange(0, 3)
                                   options:NSStringEnumerationByWords | NSStringEnumerationSubstringNotRequired
                                usingBlock:^(NSString *sub, NSRange r, NSRange e, BOOL *stop) {
                                    nilSub = sub == nil;
                                }];
        printf("substring not required gives nil: %s\n", nilSub ? "yes" : "no");

        NSString *c = @"aé\U0001F600z";
        range("composed at 1", [c rangeOfComposedCharacterSequenceAtIndex:1]);
        range("composed at 2", [c rangeOfComposedCharacterSequenceAtIndex:2]);
        range("composed at 4 (inside the pair)", [c rangeOfComposedCharacterSequenceAtIndex:4]);
        range("composed for {2, 2}", [c rangeOfComposedCharacterSequencesForRange:NSMakeRange(2, 2)]);

        NSString *e = @"é é ﬁ ①";
        show("NFC", [e precomposedStringWithCanonicalMapping]);
        show("NFD", [e decomposedStringWithCanonicalMapping]);
        show("NFKC", [e precomposedStringWithCompatibilityMapping]);
        show("NFKD", [e decomposedStringWithCompatibilityMapping]);
        CFMutableStringRef m = CFStringCreateMutableCopy(NULL, 0, CFSTR("Å"));
        CFStringNormalize(m, kCFStringNormalizationFormD);
        show("CFStringNormalize D", (NSString *)m);
        CFRelease(m);

        NSCharacterSet *digits = [NSCharacterSet decimalDigitCharacterSet];
        NSString *s = @"ab12cd34";
        range("first digit", [s rangeOfCharacterFromSet:digits]);
        range("last digit", [s rangeOfCharacterFromSet:digits options:NSBackwardsSearch]);
        range("anchored digit", [s rangeOfCharacterFromSet:digits options:NSAnchoredSearch]);
        range("anchored backwards", [s rangeOfCharacterFromSet:digits options:NSAnchoredSearch | NSBackwardsSearch]);
        range("digit in {4, 4}", [s rangeOfCharacterFromSet:digits options:0 range:NSMakeRange(4, 4)]);

        show("percent escapes added", [@"a b/c?d=é#x%" stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]);
        show("percent escapes replaced", [@"a%20b%C3%A9" stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding]);
        printf("a bad escape gives nil: %s\n",
               [@"a%ZZ%FF" stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding] ? "no" : "yes");
        CFStringRef esc = CFURLCreateStringByAddingPercentEscapes(NULL, CFSTR("a b&c=d"), NULL, CFSTR("&="),
                                                                  kCFStringEncodingUTF8);
        show("CF escapes with &= too", (NSString *)esc);
        CFRelease(esc);
        CFStringRef un = CFURLCreateStringByReplacingPercentEscapes(NULL, CFSTR("a%20b%26c"), CFSTR("&"));
        show("CF unescape all but &", (NSString *)un);
        CFRelease(un);
    }
    return 0;
}
