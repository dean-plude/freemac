/* SPDX-License-Identifier: GPL-3.0-or-later
 * What Chromium and Electron call at start besides (freemac 1.265): Core
 * Foundation's binary heaps, tokenizers and character-set bitmaps, the
 * dynamic store's keys, Security's identities and trust settings, vDSP's
 * vector maths and real FFT, and following symbolic links in a path. */
#import <Foundation/Foundation.h>
#include <Accelerate/Accelerate.h>
#include <Security/Security.h>
#include <SystemConfiguration/SystemConfiguration.h>
#include <math.h>
#include <unistd.h>

static CFComparisonResult by_number(const void *a, const void *b, void *ctx)
{
    long x = (long)a, y = (long)b;
    return x < y ? kCFCompareLessThan : x > y ? kCFCompareGreaterThan : kCFCompareEqualTo;
}

int main(void)
{
    @autoreleasepool {
        /* a binary heap: smallest first, whatever the order they went in */
        CFBinaryHeapCallBacks cb = {0, NULL, NULL, NULL, by_number};
        CFBinaryHeapRef heap = CFBinaryHeapCreate(NULL, 0, &cb, NULL);
        long in[] = {42, 7, 19, 3, 88, 7, 50};
        for (int i = 0; i < 7; i++)
            CFBinaryHeapAddValue(heap, (const void *)in[i]);
        printf("heap count %ld, same type: %s\n", (long)CFBinaryHeapGetCount(heap),
               CFGetTypeID(heap) == CFBinaryHeapGetTypeID() ? "yes" : "no");
        printf("heap order:");
        const void *v;
        while (CFBinaryHeapGetMinimumIfPresent(heap, &v)) {
            printf(" %ld", (long)v);
            CFBinaryHeapRemoveMinimumValue(heap);
        }
        printf("\n");
        CFRelease(heap);

        /* a tokenizer, by words and by sentences */
        CFStringRef text = CFSTR("Ferry runs Mac apps. It's free, and 100% ours!");
        CFStringTokenizerRef tok = CFStringTokenizerCreate(NULL, text, CFRangeMake(0, CFStringGetLength(text)),
                                                           kCFStringTokenizerUnitWord, NULL);
        printf("words:");
        while (CFStringTokenizerAdvanceToNextToken(tok) != kCFStringTokenizerTokenNone) {
            CFRange r = CFStringTokenizerGetCurrentTokenRange(tok);
            printf(" [%s]", [[(__bridge NSString *)text substringWithRange:NSMakeRange(r.location, r.length)] UTF8String]);
        }
        printf("\n");
        CFStringTokenizerGoToTokenAtIndex(tok, 13);
        CFRange at = CFStringTokenizerGetCurrentTokenRange(tok);
        printf("word at 13: %ld+%ld\n", (long)at.location, (long)at.length);
        CFRelease(tok);
        tok = CFStringTokenizerCreate(NULL, text, CFRangeMake(0, CFStringGetLength(text)),
                                      kCFStringTokenizerUnitSentence, NULL);
        int sentences = 0;
        while (CFStringTokenizerAdvanceToNextToken(tok) != kCFStringTokenizerTokenNone)
            sentences++;
        printf("sentences: %d\n", sentences);
        CFRelease(tok);

        /* a character set's bitmap */
        CFDataRef bits = CFCharacterSetCreateBitmapRepresentation(NULL, CFCharacterSetGetPredefined(kCFCharacterSetDecimalDigit));
        const uint8_t *b = CFDataGetBytePtr(bits);
        printf("bitmap %ld bytes, '5' in: %s, 'a' in: %s\n", (long)CFDataGetLength(bits), (b['5' >> 3] >> ('5' & 7)) & 1 ? "yes" : "no",
               (b['a' >> 3] >> ('a' & 7)) & 1 ? "yes" : "no");
        CFRelease(bits);
        printf("hyphenation: %s\n", CFStringIsHyphenationAvailableForLocale(NULL) ? "yes" : "no");

        /* the dynamic store */
        SCDynamicStoreRef store = SCDynamicStoreCreate(NULL, CFSTR("test"), NULL, NULL);
        CFStringRef key = SCDynamicStoreKeyCreateNetworkGlobalEntity(NULL, kSCDynamicStoreDomainState, kSCEntNetIPv4);
        printf("store key: %s\n", [(__bridge NSString *)key UTF8String]);
        CFStringRef pkey = SCDynamicStoreKeyCreateProxies(NULL);
        CFPropertyListRef proxies = SCDynamicStoreCopyValue(store, pkey);
        printf("proxies is a dictionary: %s, notification keys: %s\n",
               proxies && CFGetTypeID(proxies) == CFDictionaryGetTypeID() ? "yes" : "no",
               SCDynamicStoreSetNotificationKeys(store, (__bridge CFArrayRef)@[ (__bridge id)key ], NULL) ? "set" : "refused");
        CFRunLoopSourceRef src = SCDynamicStoreCreateRunLoopSource(NULL, store, 0);
        printf("run loop source: %s\n", src ? "yes" : "no");
        if (proxies)
            CFRelease(proxies);
        CFRelease(key);
        CFRelease(pkey);
        CFRelease(src);
        CFRelease(store);

        /* Security: no identities, no trust settings, type IDs */
        SecIdentitySearchRef search = NULL;
        SecIdentityRef ident = NULL;
        OSStatus st = SecIdentitySearchCreate(NULL, 0, &search);
        printf("identity search: %d, next: %d\n", (int)st, (int)SecIdentitySearchCopyNext(search, &ident));
        CFRelease(search);
        CFArrayRef certs = NULL;
        printf("trust settings: %d, keychain callback: %d\n",
               (int)SecTrustSettingsCopyCertificates(kSecTrustSettingsDomainUser, &certs),
               (int)SecKeychainAddCallback((SecKeychainCallback)(void *)by_number, 0, NULL));
        SecPolicyRef pol = SecPolicyCreateSSL(true, CFSTR("example.org"));
        NSDictionary *props = (__bridge_transfer NSDictionary *)SecPolicyCopyProperties(pol);
        printf("policy type: %s, name: %s, is SSL: %s\n", CFGetTypeID(pol) == SecPolicyGetTypeID() ? "yes" : "no",
               [props[(__bridge id)kSecPolicyName] UTF8String],
               [props[(__bridge id)kSecPolicyOid] isEqual:(__bridge id)kSecPolicyAppleSSL] ? "yes" : "no");
        CFRelease(pol);
        SecRequirementRef req = NULL;
        SecRequirementCreateWithString(CFSTR("anchor apple"), 0, &req);
        CFDataRef rdata = NULL;
        SecRequirementCopyData(req, 0, &rdata);
        SecRequirementRef back = NULL;
        CFStringRef rtext = NULL;
        SecRequirementCreateWithData(rdata, 0, &back);
        SecRequirementCopyString(back, 0, &rtext);
        printf("requirement round trip: %s\n", [(__bridge NSString *)rtext UTF8String]);
        CFRelease(req);
        CFRelease(rdata);
        CFRelease(back);
        CFRelease(rtext);

        /* vDSP */
        float a[4] = {1, -2, 3, -4}, c[4], d[4], s, m;
        float two = 2;
        vDSP_vsmul(a, 1, &two, c, 1, 4);
        vDSP_vsub(a, 1, c, 1, d, 1, 4); /* d = c - a = a */
        vDSP_svesq(a, 1, &s, 4);
        vDSP_maxmgv(a, 1, &m, 4);
        printf("vsmul %g %g, vsub %g %g, svesq %g, maxmgv %g\n", c[0], c[3], d[1], d[2], s, m);
        float lo = -1, hi = 1;
        vDSP_vclip(a, 1, &lo, &hi, c, 1, 4);
        printf("vclip %g %g %g %g\n", c[0], c[1], c[2], c[3]);
        float sig[16], re[8], im[8];
        for (int i = 0; i < 16; i++)
            sig[i] = (float)(sin(2 * M_PI * 2 * i / 16.0) + 0.5);
        DSPSplitComplex z = {re, im};
        vDSP_ctoz((DSPComplex *)sig, 2, &z, 1, 8);
        FFTSetup setup = vDSP_create_fftsetup(4, kFFTRadix2);
        vDSP_fft_zrip(setup, &z, 1, 4, kFFTDirection_Forward);
        printf("fft dc %.2f, bin 2 %.2f%+.2fi, bin 1 %.2f\n", re[0], re[2], im[2], fabsf(re[1]) + fabsf(im[1]));
        vDSP_fft_zrip(setup, &z, 1, 4, kFFTDirection_Inverse);
        float back_sig[16];
        vDSP_ztoc(&z, 1, (DSPComplex *)back_sig, 2, 8);
        float err = 0;
        for (int i = 0; i < 16; i++)
            err = fmaxf(err, fabsf(back_sig[i] / 32 - sig[i]));
        printf("forward then inverse is 2N times: %s\n", err < 1e-4 ? "yes" : "no");
        vDSP_destroy_fftsetup(setup);
        double x[6] = {0, 0, 1, 0, 0, 0}, y[6] = {0, 0};
        double coef[5] = {1, 0, 0, -0.5, 0};
        vDSP_deq22D(x, 1, coef, y, 1, 4);
        printf("deq22D %g %g %g %g\n", y[2], y[3], y[4], y[5]);

        /* symbolic links in a path */
        NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:@"ferry-symlinks"];
        [[NSFileManager defaultManager] removeItemAtPath:dir error:nil];
        [[NSFileManager defaultManager] createDirectoryAtPath:[dir stringByAppendingPathComponent:@"real"]
                                  withIntermediateDirectories:YES attributes:nil error:nil];
        symlink([[dir stringByAppendingPathComponent:@"real"] fileSystemRepresentation],
                [[dir stringByAppendingPathComponent:@"link"] fileSystemRepresentation]);
        NSString *resolved = [[dir stringByAppendingPathComponent:@"link/../link"] stringByResolvingSymlinksInPath];
        printf("symlink resolves to real: %s\n", [resolved hasSuffix:@"/ferry-symlinks/real"] ? "yes" : "no");
        printf("missing path standardized: %s\n", [[@"/nowhere/a/../b" stringByResolvingSymlinksInPath] UTF8String]);
        [[NSFileManager defaultManager] removeItemAtPath:dir error:nil];
    }
    return 0;
}
