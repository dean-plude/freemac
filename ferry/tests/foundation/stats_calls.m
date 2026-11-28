/* SPDX-License-Identifier: GPL-3.0-or-later
 * What Stats, the menu bar system monitor, asks of Foundation and the
 * system libraries before it shows its readings (freemac 1.271, Stats
 * 3.1.1): one shared empty dictionary, which Swift's runtime keeps for
 * every error it bridges without taking a reference; the file system's
 * size and free space; measurements in other units; names of languages and
 * regions; the network interfaces; IOReport with no channels; and
 * libcompression's buffer calls, which also read asset catalogues. */
#import <Foundation/Foundation.h>
#import <Foundation/NSMeasurement.h>
#import <SystemConfiguration/SystemConfiguration.h>
#import <SystemConfiguration/SCNetworkConfiguration.h>
#include <compression.h>
#include <stdio.h>
#include <string.h>

extern CFMutableDictionaryRef IOReportCopyChannelsInGroup(CFStringRef group, CFStringRef subgroup, uint64_t a,
                                                          uint64_t b, uint64_t c);

static void roundtrip(const char *name, compression_algorithm algorithm, const uint8_t *src, size_t n)
{
    uint8_t packed[4096], back[4096];
    size_t p = compression_encode_buffer(packed, sizeof packed, src, n, NULL, algorithm);
    size_t b = p ? compression_decode_buffer(back, sizeof back, packed, p, NULL, algorithm) : 0;
    printf("%s round trip: %s\n", name, p && b == n && !memcmp(back, src, n) ? "same" : "different");
}

int main(void)
{
    @autoreleasepool {
        /* one empty dictionary, never freed */
        NSDictionary *empty = [NSDictionary dictionary];
        [empty release]; [empty release];
        printf("empty dictionary shared: %s, count %lu\n",
               empty == [NSDictionary dictionary] ? "yes" : "no", (unsigned long)[[NSDictionary dictionary] count]);
        printf("mutable one new each time: %s\n",
               [NSMutableDictionary dictionary] != [NSMutableDictionary dictionary] ? "yes" : "no");
        NSError *error = [NSError errorWithDomain:@"Stats" code:3 userInfo:nil];
        for (int i = 0; i < 3; i++) [error localizedDescription];
        printf("error description: %s\n", [[error localizedDescription] UTF8String]);

        /* the disk Stats shows */
        NSDictionary *fs = [[NSFileManager defaultManager] attributesOfFileSystemForPath:@"/" error:NULL];
        long long size = [fs[NSFileSystemSize] longLongValue], free = [fs[NSFileSystemFreeSize] longLongValue];
        printf("file system: size %s, free %s\n", size > 0 ? "yes" : "no", free >= 0 && free <= size ? "fits" : "wrong");

        /* measurements */
        NSMeasurement *c = [[NSMeasurement alloc] initWithDoubleValue:100 unit:[NSUnitTemperature celsius]];
        NSMeasurement *f = [c measurementByConvertingToUnit:[NSUnitTemperature fahrenheit]];
        printf("100 C = %.1f F\n", f.doubleValue);
        NSMeasurement *g = [[NSMeasurement alloc] initWithDoubleValue:2 unit:[NSUnitInformationStorage gigabytes]];
        printf("2 GB = %.0f MB\n", [g measurementByConvertingToUnit:[NSUnitInformationStorage megabytes]].doubleValue);
        printf("Hz to C: %s\n", [c canBeConvertedToUnit:[NSUnitFrequency hertz]] ? "yes" : "no");
        [c release]; [g release];

        /* names of languages and regions, for its language menu */
        NSLocale *en = [NSLocale localeWithLocaleIdentifier:@"en_US"];
        printf("de: %s, FR: %s\n", [[en localizedStringForLanguageCode:@"de"] UTF8String],
               [[en localizedStringForCountryCode:@"FR"] UTF8String]);

        /* network interfaces: none is the loopback one */
        NSArray *ifs = [(NSArray *)SCNetworkInterfaceCopyAll() autorelease];
        BOOL ok = YES;
        for (id i in ifs) {
            NSString *n = (NSString *)SCNetworkInterfaceGetBSDName((SCNetworkInterfaceRef)i);
            NSString *t = (NSString *)SCNetworkInterfaceGetInterfaceType((SCNetworkInterfaceRef)i);
            if (!n.length || [n isEqualToString:@"lo"] ||
                !([t isEqualToString:(NSString *)kSCNetworkInterfaceTypeEthernet] ||
                  [t isEqualToString:(NSString *)kSCNetworkInterfaceTypeIEEE80211]))
                ok = NO;
        }
        printf("interfaces named and typed: %s\n", ok ? "yes" : "no");

        /* IOReport: groups with no channels */
        CFMutableDictionaryRef channels = IOReportCopyChannelsInGroup(CFSTR("Energy Model"), NULL, 0, 0, 0);
        printf("IOReport channels: %lu\n",
               (unsigned long)[((NSDictionary *)channels)[@"IOReportChannels"] count]);
        CFRelease(channels);

        /* libcompression */
        uint8_t text[1000];
        for (int i = 0; i < (int)sizeof text; i++) text[i] = "menu bar "[i % 9];
        roundtrip("zlib", COMPRESSION_ZLIB, text, sizeof text);
        roundtrip("LZ4", COMPRESSION_LZ4, text, sizeof text);
        roundtrip("LZFSE", COMPRESSION_LZFSE, text, sizeof text);
        roundtrip("LZMA", COMPRESSION_LZMA, text, sizeof text);
        /* an LZ4 block by hand: 4 literals "abcd", then 8 bytes from 4 back */
        static const uint8_t lz4[] = {'b', 'v', '4', '1', 12, 0, 0, 0, 7, 0, 0, 0,
                                      0x44, 'a', 'b', 'c', 'd', 4, 0, 'b', 'v', '4', '$'};
        uint8_t out[64] = {0};
        size_t n = compression_decode_buffer(out, sizeof out, lz4, sizeof lz4, NULL, COMPRESSION_LZ4);
        printf("LZ4 block: %zu \"%.*s\"\n", n, (int)n, out);
        /* an LZVN block by hand: three literals, then the end of the stream */
        static const uint8_t lzvn[] = {'b', 'v', 'x', 'n', 3, 0, 0, 0, 12, 0, 0, 0,
                                       0xE3, 'P', 'C', '!', 0x06, 0, 0, 0, 0, 0, 0, 0, 'b', 'v', 'x', '$'};
        memset(out, 0, sizeof out);
        n = compression_decode_buffer(out, sizeof out, lzvn, sizeof lzvn, NULL, COMPRESSION_LZFSE);
        printf("LZVN block: %zu \"%.*s\"\n", n, (int)n, out);
        printf("too small: %zu\n", compression_decode_buffer(out, 2, lzvn, sizeof lzvn, NULL, COMPRESSION_LZFSE));
    }
    return 0;
}
