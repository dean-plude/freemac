/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: CFLocale, written for freemac from Apple's public CFLocale
 * documentation; not Apple's header. A CFLocaleRef is an NSLocale, as on a
 * Mac, and its keys are NSLocale's own. Included by
 * <CoreFoundation/CoreFoundation.h>; foundation/CFLocale.m. */
#ifndef _FERRY_CFLOCALE_H_
#define _FERRY_CFLOCALE_H_

__FERRY_BEGIN
CF_IMPLICIT_BRIDGING_ENABLED
typedef const struct CF_BRIDGED_TYPE(NSLocale) __CFLocale *CFLocaleRef;
typedef CFStringRef CFLocaleIdentifier;
typedef CFStringRef CFLocaleKey;

extern const CFLocaleKey kCFLocaleIdentifier;
extern const CFLocaleKey kCFLocaleLanguageCode;
extern const CFLocaleKey kCFLocaleCountryCode;
extern const CFLocaleKey kCFLocaleScriptCode;
extern const CFLocaleKey kCFLocaleVariantCode;
extern const CFLocaleKey kCFLocaleDecimalSeparator;
extern const CFLocaleKey kCFLocaleGroupingSeparator;
extern const CFLocaleKey kCFLocaleUsesMetricSystem;
extern const CFLocaleKey kCFLocaleCalendar;
extern const CFLocaleKey kCFLocaleCurrencyCode;
extern const CFLocaleKey kCFLocaleCurrencySymbol;
extern const CFStringRef kCFLocaleCurrentLocaleDidChangeNotification;

CFTypeID CFLocaleGetTypeID(void);
CFLocaleRef CFLocaleCopyCurrent(void);
CFLocaleRef CFLocaleGetSystem(void);
CFLocaleRef CFLocaleCreate(CFAllocatorRef allocator, CFLocaleIdentifier localeIdentifier);
CFLocaleRef CFLocaleCreateCopy(CFAllocatorRef allocator, CFLocaleRef locale);
CFLocaleIdentifier CFLocaleGetIdentifier(CFLocaleRef locale);
CFTypeRef CFLocaleGetValue(CFLocaleRef locale, CFLocaleKey key);
CFStringRef CFLocaleCopyDisplayNameForPropertyValue(CFLocaleRef displayLocale, CFLocaleKey key, CFStringRef value);
CFArrayRef CFLocaleCopyAvailableLocaleIdentifiers(void);
CFArrayRef CFLocaleCopyISOLanguageCodes(void);
CFArrayRef CFLocaleCopyPreferredLanguages(void);
CFLocaleIdentifier CFLocaleCreateCanonicalLocaleIdentifierFromString(CFAllocatorRef allocator,
                                                                    CFStringRef localeIdentifier);
CFDictionaryRef CFLocaleCreateComponentsFromLocaleIdentifier(CFAllocatorRef allocator,
                                                             CFLocaleIdentifier localeID);
CF_IMPLICIT_BRIDGING_DISABLED
__FERRY_END
#endif
