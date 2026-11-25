/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry test (freemac 1.219, Ferry 0.43.0): the rest of Core Foundation's
 * arrays and dictionaries, which Sequel Pro, Hex Fiend and RegexKitLite use
 * from C. Arrays with the CFType callbacks and with none (plain pointers and
 * numbers), searching, sorting and binary search, replacing a range; a
 * dictionary of C strings with callbacks of its own, then the CFType one,
 * copied, applied over and emptied; the type IDs; UUIDs made, parsed and
 * compared; file URLs in POSIX, HFS and Windows styles; the bundle keys; and
 * the byte-order calls. */
#include <CoreFoundation/CoreFoundation.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

static void print_cf(const char *label, CFStringRef s)
{
    char buf[256];
    if (!s || !CFStringGetCString(s, buf, sizeof buf, kCFStringEncodingUTF8))
        strcpy(buf, "(null)");
    printf("%s: %s\n", label, buf);
}

static CFComparisonResult by_value(const void *a, const void *b, void *ctx)
{
    intptr_t x = (intptr_t)a, y = (intptr_t)b;
    return x < y ? kCFCompareLessThan : x > y ? kCFCompareGreaterThan : kCFCompareEqualTo;
}
static void add_up(const void *value, void *ctx) { *(intptr_t *)ctx += (intptr_t)value; }

/* A dictionary of malloc'd C strings: keys copied in, freed when they go. */
static int frees;
static const void *cstr_retain(CFAllocatorRef a, const void *v) { return strdup(v); }
static void cstr_release(CFAllocatorRef a, const void *v)
{
    frees++;
    free((void *)v);
}
static Boolean cstr_equal(const void *a, const void *b) { return strcmp(a, b) == 0; }
static CFHashCode cstr_hash(const void *v)
{
    CFHashCode h = 5381;
    for (const char *p = v; *p; p++)
        h = h * 33 + (unsigned char)*p;
    return h;
}
static void count_pair(const void *k, const void *v, void *ctx) { *(int *)ctx += (int)(intptr_t)v; }

int main(void)
{
    /* Arrays with no callbacks hold whatever pointers they are given. */
    CFMutableArrayRef a = CFArrayCreateMutable(NULL, 0, NULL);
    intptr_t vals[] = {5, 3, 9, 1, 7, 3};
    for (int i = 0; i < 6; i++)
        CFArrayAppendValue(a, (const void *)vals[i]);
    CFRange all = CFRangeMake(0, CFArrayGetCount(a));
    printf("count %ld, contains 9 %d, count of 3 %ld, first 3 at %ld, last 3 at %ld, 4 at %ld\n",
           (long)CFArrayGetCount(a), CFArrayContainsValue(a, all, (const void *)9),
           (long)CFArrayGetCountOfValue(a, all, (const void *)3),
           (long)CFArrayGetFirstIndexOfValue(a, all, (const void *)3),
           (long)CFArrayGetLastIndexOfValue(a, all, (const void *)3),
           (long)CFArrayGetFirstIndexOfValue(a, all, (const void *)4));
    CFArraySortValues(a, all, by_value, NULL);
    printf("sorted:");
    for (CFIndex i = 0; i < CFArrayGetCount(a); i++)
        printf(" %ld", (long)(intptr_t)CFArrayGetValueAtIndex(a, i));
    printf("\n");
    printf("binary search 7 -> %ld, 4 -> %ld, 100 -> %ld\n",
           (long)CFArrayBSearchValues(a, all, (const void *)7, by_value, NULL),
           (long)CFArrayBSearchValues(a, all, (const void *)4, by_value, NULL),
           (long)CFArrayBSearchValues(a, all, (const void *)100, by_value, NULL));
    intptr_t sum = 0;
    CFArrayApplyFunction(a, all, add_up, &sum);
    printf("sum %ld\n", (long)sum);
    const void *repl[] = {(const void *)40, (const void *)41};
    CFArrayReplaceValues(a, CFRangeMake(1, 3), repl, 2);
    CFArrayInsertValueAtIndex(a, 0, (const void *)0);
    CFArrayExchangeValuesAtIndices(a, 0, 1);
    CFArrayRemoveValueAtIndex(a, CFArrayGetCount(a) - 1);
    printf("replaced:");
    for (CFIndex i = 0; i < CFArrayGetCount(a); i++)
        printf(" %ld", (long)(intptr_t)CFArrayGetValueAtIndex(a, i));
    printf("\n");
    CFArrayRemoveAllValues(a);
    printf("emptied: %ld\n", (long)CFArrayGetCount(a));
    CFRelease(a);

    /* With the CFType callbacks, values are retained and compared with CFEqual. */
    CFStringRef words[] = {CFSTR("pear"), CFSTR("apple"), CFSTR("fig")};
    CFArrayRef fixed = CFArrayCreate(NULL, (const void **)words, 3, &kCFTypeArrayCallBacks);
    CFMutableArrayRef copy = CFArrayCreateMutableCopy(NULL, 0, fixed);
    CFStringRef made = CFStringCreateWithCString(NULL, "apple", kCFStringEncodingUTF8);
    printf("equal string found at %ld\n", (long)CFArrayGetFirstIndexOfValue(copy, CFRangeMake(0, 3), made));
    CFArraySortValues(copy, CFRangeMake(0, 3), (CFComparatorFunction)CFStringCompare, NULL);
    CFStringRef joined = CFStringCreateByCombiningStrings(NULL, copy, CFSTR(","));
    print_cf("sorted words", joined);
    CFArrayAppendArray(copy, fixed, CFRangeMake(1, 2));
    printf("after append %ld, arrays equal %d, type is array %d\n", (long)CFArrayGetCount(copy), CFEqual(copy, fixed),
           CFGetTypeID(copy) == CFArrayGetTypeID());
    const void *got[3];
    CFArrayGetValues(fixed, CFRangeMake(0, 3), got);
    printf("values are the same objects: %d\n", got[2] == words[2]);
    CFRelease(made);
    CFRelease(joined);
    CFRelease(copy);
    CFRelease(fixed);

    /* A dictionary of C strings. */
    CFDictionaryKeyCallBacks kc = {0, cstr_retain, cstr_release, NULL, cstr_equal, cstr_hash};
    CFMutableDictionaryRef d = CFDictionaryCreateMutable(NULL, 0, &kc, NULL);
    char key[16];
    for (int i = 0; i < 40; i++) {
        snprintf(key, sizeof key, "key%d", i);
        CFDictionarySetValue(d, key, (const void *)(intptr_t)i);
    }
    const void *v = NULL;
    printf("dictionary count %ld, key17 present %d -> %ld, key99 present %d\n", (long)CFDictionaryGetCount(d),
           CFDictionaryGetValueIfPresent(d, "key17", &v), (long)(intptr_t)v,
           CFDictionaryGetValueIfPresent(d, "key99", NULL));
    CFDictionaryAddValue(d, "key3", (const void *)1000); /* already there: unchanged */
    CFDictionaryReplaceValue(d, "key4", (const void *)400);
    CFDictionaryReplaceValue(d, "key400", (const void *)1); /* not there: nothing */
    printf("key3 %ld, key4 %ld, key400 there %d, count of value 400: %ld\n",
           (long)(intptr_t)CFDictionaryGetValue(d, "key3"), (long)(intptr_t)CFDictionaryGetValue(d, "key4"),
           CFDictionaryContainsKey(d, "key400"), (long)CFDictionaryGetCountOfValue(d, (const void *)400));
    int total = 0;
    CFDictionaryApplyFunction(d, count_pair, &total);
    printf("values add up to %d\n", total);
    frees = 0;
    CFDictionaryRemoveValue(d, "key0");
    printf("removing one freed %d key\n", frees);
    CFDictionaryRemoveAllValues(d);
    printf("emptying freed %d keys, count %ld\n", frees, (long)CFDictionaryGetCount(d));
    CFRelease(d);

    /* The CFType dictionary, copied and listed. */
    CFStringRef keys[] = {CFSTR("b"), CFSTR("a")};
    CFNumberRef nums[2];
    int one = 1, two = 2;
    nums[0] = CFNumberCreate(NULL, kCFNumberIntType, &one);
    nums[1] = CFNumberCreate(NULL, kCFNumberIntType, &two);
    CFDictionaryRef fd = CFDictionaryCreate(NULL, (const void **)keys, (const void **)nums, 2,
                                            &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    CFMutableDictionaryRef md = CFDictionaryCreateMutableCopy(NULL, 0, fd);
    CFDictionarySetValue(md, CFSTR("c"), nums[0]);
    const void *ks[3], *vs[3];
    CFDictionaryGetKeysAndValues(md, ks, vs);
    int sumv = 0;
    for (int i = 0; i < 3; i++) {
        int x;
        CFNumberGetValue(vs[i], kCFNumberIntType, &x);
        sumv += x;
    }
    printf("copy has %ld, value sum %d, contains value 2 %d, is a dictionary %d, original unchanged %ld\n",
           (long)CFDictionaryGetCount(md), sumv, CFDictionaryContainsValue(md, nums[1]),
           CFGetTypeID(md) == CFDictionaryGetTypeID(), (long)CFDictionaryGetCount(fd));
    CFDictionaryRef dcopy = CFDictionaryCreateCopy(NULL, md);
    printf("copies equal %d\n", CFEqual(dcopy, md));
    CFRelease(dcopy);
    CFRelease(md);
    CFRelease(fd);
    CFRelease(nums[0]);
    CFRelease(nums[1]);

    /* UUIDs. */
    CFUUIDRef u1 = CFUUIDCreateFromString(NULL, CFSTR("68753A44-4D6F-1226-9C60-0050E4C00067"));
    CFStringRef us = CFUUIDCreateString(NULL, u1);
    print_cf("uuid", us);
    CFUUIDBytes ub = CFUUIDGetUUIDBytes(u1);
    printf("uuid bytes start %02x %02x, end %02x\n", ub.byte0, ub.byte1, ub.byte15);
    CFUUIDRef u2 = CFUUIDCreateFromUUIDBytes(NULL, ub);
    CFUUIDRef c1 = CFUUIDGetConstantUUIDWithBytes(NULL, 0x68, 0x75, 0x3a, 0x44, 0x4d, 0x6f, 0x12, 0x26, 0x9c, 0x60,
                                                  0x00, 0x50, 0xe4, 0xc0, 0x00, 0x67);
    CFUUIDRef c2 = CFUUIDGetConstantUUIDWithBytes(NULL, 0x68, 0x75, 0x3a, 0x44, 0x4d, 0x6f, 0x12, 0x26, 0x9c, 0x60,
                                                  0x00, 0x50, 0xe4, 0xc0, 0x00, 0x67);
    CFUUIDRef fresh = CFUUIDCreate(NULL);
    CFStringRef fs = CFUUIDCreateString(NULL, fresh);
    printf("same uuid equal %d, constant uuid kept %d, fresh is 36 long %d and differs %d, type %d\n",
           CFEqual(u1, u2), c1 == c2, CFStringGetLength(fs) == 36, !CFEqual(fresh, u1),
           CFGetTypeID(u1) == CFUUIDGetTypeID());
    CFRelease(us);
    CFRelease(fs);
    CFRelease(fresh);
    CFRelease(u1);
    CFRelease(u2);

    /* URLs. */
    CFURLRef fu = CFURLCreateWithFileSystemPath(NULL, CFSTR("/tmp/some dir/file.txt"), kCFURLPOSIXPathStyle, false);
    print_cf("file url", CFURLGetString(fu));
    CFStringRef hfs = CFURLCopyFileSystemPath(fu, kCFURLHFSPathStyle);
    print_cf("as HFS", hfs);
    CFStringRef win = CFURLCopyFileSystemPath(fu, kCFURLWindowsPathStyle);
    print_cf("as Windows", win);
    CFStringRef ext = CFURLCopyPathExtension(fu);
    CFStringRef last = CFURLCopyLastPathComponent(fu);
    print_cf("extension", ext);
    print_cf("last component", last);
    CFURLRef up = CFURLCreateCopyDeletingLastPathComponent(NULL, fu);
    print_cf("parent", CFURLGetString(up));
    printf("parent is a directory %d\n", CFURLHasDirectoryPath(up));
    CFURLRef web = CFURLCreateWithString(NULL, CFSTR("https://example.org:8443/a/b?q=1#top"), NULL);
    CFStringRef host = CFURLCopyHostName(web), q = CFURLCopyQueryString(web, NULL), frag = CFURLCopyFragment(web, NULL);
    print_cf("host", host);
    print_cf("query", q);
    print_cf("fragment", frag);
    printf("port %d\n", (int)CFURLGetPortNumber(web));
    UInt8 rep[256];
    printf("file system representation: %d %s\n", CFURLGetFileSystemRepresentation(fu, true, rep, sizeof rep),
           (char *)rep);
    CFRelease(fu);
    CFRelease(hfs);
    CFRelease(win);
    CFRelease(ext);
    CFRelease(last);
    CFRelease(up);
    CFRelease(web);
    CFRelease(host);
    CFRelease(q);
    CFRelease(frag);

    print_cf("bundle version key", kCFBundleVersionKey);
    print_cf("bundle identifier key", kCFBundleIdentifierKey);
    printf("Core Foundation version past 10.10: %d\n",
           kCFCoreFoundationVersionNumber >= kCFCoreFoundationVersionNumber10_10);
    printf("byte order: 0x%x 0x%x, host is little-endian %d\n", (unsigned)CFSwapInt16(0x1234),
           (unsigned)CFSwapInt32BigToHost(0x01020304), CFByteOrderGetCurrent() == CFByteOrderLittleEndian);
    return 0;
}
