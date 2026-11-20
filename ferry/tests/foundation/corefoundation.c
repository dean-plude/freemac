/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry M2 test: CoreFoundation from plain C. */
#include <CoreFoundation/CoreFoundation.h>
#include <stdio.h>

int main(void)
{
    CFStringRef s = CFStringCreateWithCString(kCFAllocatorDefault, "plain C", kCFStringEncodingUTF8);
    char buf[64];
    CFStringGetCString(s, buf, sizeof buf, kCFStringEncodingUTF8);
    printf("string \"%s\" length %ld, equal to literal %d\n", buf, (long)CFStringGetLength(s),
           CFEqual(s, CFSTR("plain C")));
    CFMutableArrayRef a = CFArrayCreateMutable(NULL, 0, kCFTypeArrayCallBacks);
    CFArrayAppendValue(a, s);
    CFArrayAppendValue(a, CFSTR("second"));
    CFRelease(s);
    printf("array count %ld, retain count of the array %ld\n", (long)CFArrayGetCount(a), (long)CFGetRetainCount(a));
    CFStringRef desc = CFCopyDescription(CFArrayGetValueAtIndex(a, 1));
    CFStringGetCString(desc, buf, sizeof buf, kCFStringEncodingUTF8);
    printf("second item %s\n", buf);
    CFRelease(desc);
    CFRelease(a);
    double pi = 3.25, out = 0;
    CFNumberRef n = CFNumberCreate(NULL, kCFNumberDoubleType, &pi);
    CFNumberGetValue(n, kCFNumberDoubleType, &out);
    printf("number %.2f, true is %d\n", out, CFBooleanGetValue(kCFBooleanTrue));
    CFRelease(n);
    printf("run loop with nothing to do finishes: %d\n",
           CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.1, false) == kCFRunLoopRunFinished);
    return 0;
}
