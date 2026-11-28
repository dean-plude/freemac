/* SPDX-License-Identifier: GPL-3.0-or-later
 * libIOReport (freemac 1.271, Ferry 0.94.0): the report of power, clock
 * and residency counters that system monitors such as Stats read, served
 * from Foundation. IOReport has no public documentation; the calls and
 * their arguments are as Stats' own open-source code declares them. A PC
 * here has no such report, as an Intel Mac mostly hasn't, so every group
 * has no channels and a sample holds none; Stats then falls back to the
 * readings it takes other ways. No Apple code was read. */
#import "FInternal.h"
#include <CoreFoundation/CoreFoundation.h>
#include <stdint.h>

/* A channel list with no channels, in the shape the report uses: a
 * dictionary whose "IOReportChannels" is an array. */
static CFMutableDictionaryRef empty_channels(void)
{
    CFMutableDictionaryRef d = CFDictionaryCreateMutable(NULL, 0, &kCFTypeDictionaryKeyCallBacks,
                                                         &kCFTypeDictionaryValueCallBacks);
    CFArrayRef none = CFArrayCreate(NULL, NULL, 0, &kCFTypeArrayCallBacks);
    CFDictionarySetValue(d, CFSTR("IOReportChannels"), none);
    CFRelease(none);
    return d;
}

CFMutableDictionaryRef IOReportCopyChannelsInGroup(CFStringRef group, CFStringRef subgroup, uint64_t a, uint64_t b,
                                                   uint64_t c)
{
    return empty_channels();
}
CFMutableDictionaryRef IOReportCopyAllChannels(uint64_t a, uint64_t b) { return empty_channels(); }

void IOReportMergeChannels(CFDictionaryRef into, CFDictionaryRef from, CFTypeRef unused) {}

/* A subscription needs a channel the system reports; there is none. */
void *IOReportCreateSubscription(void *a, CFMutableDictionaryRef channels, CFMutableDictionaryRef *subscribed,
                                 uint64_t b, CFTypeRef c)
{
    if (subscribed)
        *subscribed = NULL;
    return NULL;
}

CFDictionaryRef IOReportCreateSamples(void *subscription, CFMutableDictionaryRef channels, CFTypeRef unused)
{
    return subscription ? empty_channels() : NULL;
}
CFDictionaryRef IOReportCreateSamplesDelta(CFDictionaryRef before, CFDictionaryRef after, CFTypeRef unused)
{
    return before && after ? empty_channels() : NULL;
}

/* A channel's details: there are no channels to ask about. */
CFStringRef IOReportChannelGetGroup(CFDictionaryRef channel) { return NULL; }
CFStringRef IOReportChannelGetSubGroup(CFDictionaryRef channel) { return NULL; }
CFStringRef IOReportChannelGetChannelName(CFDictionaryRef channel) { return NULL; }
CFStringRef IOReportChannelGetUnitLabel(CFDictionaryRef channel) { return NULL; }
int32_t IOReportStateGetCount(CFDictionaryRef channel) { return 0; }
CFStringRef IOReportStateGetNameForIndex(CFDictionaryRef channel, int32_t index) { return NULL; }
int64_t IOReportStateGetResidency(CFDictionaryRef channel, int32_t index) { return 0; }
int64_t IOReportSimpleGetIntegerValue(CFDictionaryRef channel, int32_t index) { return 0; }
