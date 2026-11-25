/* Ferry test: CFLocale, CFDate, CFDateFormatter and CFError from C, as
 * Flycut's date display and other apps' error handling use them; each is
 * the Foundation object (NSLocale, NSDate, NSDateFormatter, NSError). Run
 * with TZ=Europe/Paris and LANG=en_US.UTF-8. */
#include <CoreFoundation/CoreFoundation.h>
#include <stdio.h>

static void show(const char *what, CFTypeRef v)
{
    char buf[256] = "(null)";
    if (v && CFGetTypeID(v) == CFStringGetTypeID())
        CFStringGetCString((CFStringRef)v, buf, sizeof buf, kCFStringEncodingUTF8);
    else if (v) {
        CFStringRef d = CFCopyDescription(v);
        CFStringGetCString(d, buf, sizeof buf, kCFStringEncodingUTF8);
        CFRelease(d);
    }
    printf("%s: %s\n", what, buf);
}

static void locales(void)
{
    CFLocaleRef fr = CFLocaleCreate(NULL, CFSTR("fr_FR"));
    printf("locale type: %d\n", CFGetTypeID(fr) == CFLocaleGetTypeID());
    show("identifier", CFLocaleGetIdentifier(fr));
    show("language", CFLocaleGetValue(fr, kCFLocaleLanguageCode));
    show("country", CFLocaleGetValue(fr, kCFLocaleCountryCode));
    show("currency", CFLocaleGetValue(fr, kCFLocaleCurrencyCode));
    CFTypeRef metric = CFLocaleGetValue(fr, kCFLocaleUsesMetricSystem);
    printf("metric: %d\n", metric == kCFBooleanTrue);
    CFLocaleRef copy = CFLocaleCreateCopy(NULL, fr);
    show("copy", CFLocaleGetIdentifier(copy));
    CFLocaleRef current = CFLocaleCopyCurrent();
    show("current", CFLocaleGetIdentifier(current));
    printf("system: %d\n", CFLocaleGetSystem() != NULL);
    CFStringRef canonical = CFLocaleCreateCanonicalLocaleIdentifierFromString(NULL, CFSTR("en-GB"));
    show("canonical en-GB", canonical);
    CFDictionaryRef parts = CFLocaleCreateComponentsFromLocaleIdentifier(NULL, CFSTR("de_CH"));
    show("de_CH language", CFDictionaryGetValue(parts, kCFLocaleLanguageCode));
    show("de_CH country", CFDictionaryGetValue(parts, kCFLocaleCountryCode));
    CFArrayRef codes = CFLocaleCopyISOLanguageCodes();
    printf("ISO languages: some %d\n", CFArrayGetCount(codes) > 0);
    CFArrayRef available = CFLocaleCopyAvailableLocaleIdentifiers();
    printf("available locales: some %d\n", CFArrayGetCount(available) > 0);
    CFArrayRef preferred = CFLocaleCopyPreferredLanguages();
    printf("preferred languages: some %d\n", CFArrayGetCount(preferred) > 0);
    CFRelease(fr);
    CFRelease(copy);
    CFRelease(current);
    CFRelease(canonical);
    CFRelease(parts);
    CFRelease(codes);
    CFRelease(available);
    CFRelease(preferred);
}

static void dates(void)
{
    CFDateRef a = CFDateCreate(NULL, 0);           /* 2001-01-01 00:00:00 UTC */
    CFDateRef b = CFDateCreate(NULL, 86400 * 365); /* a year later */
    printf("date type: %d\n", CFGetTypeID(a) == CFDateGetTypeID());
    printf("absolute time: %.0f\n", CFDateGetAbsoluteTime(b));
    printf("interval: %.0f\n", CFDateGetTimeIntervalSinceDate(b, a));
    printf("compare: %ld %ld %ld\n", (long)CFDateCompare(a, b, NULL), (long)CFDateCompare(b, a, NULL),
           (long)CFDateCompare(a, a, NULL));
    printf("since 1904: %.0f\n", kCFAbsoluteTimeIntervalSince1904);

    CFLocaleRef us = CFLocaleCreate(NULL, CFSTR("en_US"));
    CFDateFormatterRef f = CFDateFormatterCreate(NULL, us, kCFDateFormatterMediumStyle, kCFDateFormatterShortStyle);
    printf("formatter type: %d, styles %ld %ld\n", CFGetTypeID(f) == CFDateFormatterGetTypeID(),
           (long)CFDateFormatterGetDateStyle(f), (long)CFDateFormatterGetTimeStyle(f));
    show("its locale", CFLocaleGetIdentifier(CFDateFormatterGetLocale(f)));
    CFStringRef s = CFDateFormatterCreateStringWithDate(NULL, f, b);
    show("medium, short (Paris)", s);
    CFRelease(s);
    CFDateFormatterSetFormat(f, CFSTR("yyyy-MM-dd HH:mm"));
    show("format", CFDateFormatterGetFormat(f));
    s = CFDateFormatterCreateStringWithAbsoluteTime(NULL, f, 3600);
    show("formatted", s);
    CFRelease(s);
    CFDateRef parsed = CFDateFormatterCreateDateFromString(NULL, f, CFSTR("2001-01-02 01:00"), NULL);
    printf("parsed: %.0f\n", parsed ? CFDateGetAbsoluteTime(parsed) : -1.0);
    if (parsed)
        CFRelease(parsed);
    s = CFDateFormatterCreateDateFormatFromTemplate(NULL, CFSTR("yMMMd"), 0, us);
    show("template yMMMd", s);
    if (s)
        CFRelease(s);
    CFRelease(f);
    CFRelease(us);
    CFRelease(a);
    CFRelease(b);
}

static void errors(void)
{
    CFStringRef keys[] = {kCFErrorLocalizedDescriptionKey, kCFErrorFilePathKey};
    CFStringRef values[] = {CFSTR("The clipping store can't be read."), CFSTR("/tmp/clips")};
    CFErrorRef e = CFErrorCreateWithUserInfoKeysAndValues(NULL, kCFErrorDomainPOSIX, 2, (const void *const *)keys,
                                                          (const void *const *)values, 2);
    printf("error type: %d\n", CFGetTypeID(e) == CFErrorGetTypeID());
    show("domain", CFErrorGetDomain(e));
    printf("code: %ld\n", (long)CFErrorGetCode(e));
    CFStringRef d = CFErrorCopyDescription(e);
    show("description", d);
    CFRelease(d);
    CFDictionaryRef info = CFErrorCopyUserInfo(e);
    show("its file", CFDictionaryGetValue(info, kCFErrorFilePathKey));
    CFRelease(info);
    printf("failure reason: %s\n", CFErrorCopyFailureReason(e) ? "some" : "none");
    CFRelease(e);
    e = CFErrorCreate(NULL, kCFErrorDomainOSStatus, -43, NULL);
    show("plain domain", CFErrorGetDomain(e));
    info = CFErrorCopyUserInfo(e);
    printf("plain user info: %ld entries\n", (long)CFDictionaryGetCount(info));
    CFRelease(info);
    CFRelease(e);
    printf("no domain: %d\n", CFErrorCreate(NULL, NULL, 1, NULL) == NULL);
}

int main(void)
{
    locales();
    dates();
    errors();
    return 0;
}
