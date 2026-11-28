/* SPDX-License-Identifier: GPL-3.0-or-later
 * What the Stats system monitor's official download calls in Foundation
 * besides (freemac 1.271, Ferry 0.94.0): a disk's size and free space,
 * and a locale's names for languages, regions and calendars. Written from
 * Apple's public documentation of NSFileManager and NSLocale; no Apple
 * code was read. Built without ARC. */
#import "FInternal.h"
#include <sys/mount.h>

NSString *const NSFileSystemSize = @"NSFileSystemSize";
NSString *const NSFileSystemFreeSize = @"NSFileSystemFreeSize";
NSString *const NSFileSystemNodes = @"NSFileSystemNodes";
NSString *const NSFileSystemFreeNodes = @"NSFileSystemFreeNodes";

/* ---- a disk's size --------------------------------------------------------------- *
 * The free size is what this user may write, as on a Mac (blocks set aside
 * for the system don't count). */

@implementation NSFileManager (FerryFileSystemAttributes)
- (NSDictionary *)attributesOfFileSystemForPath:(NSString *)path error:(NSError **)error
{
    struct statfs s;
    const char *p = [path fileSystemRepresentation];
    if (!p || statfs(p, &s) != 0) {
        FSetError(error, FPosixError(p ? errno : ENOENT, path));
        return nil;
    }
    unsigned long long block = s.f_bsize ? s.f_bsize : 512;
    struct stat st;
    unsigned long long number = stat(p, &st) == 0 ? (unsigned long long)st.st_dev : 0;
    return [NSDictionary dictionaryWithObjectsAndKeys:
                             [NSNumber numberWithUnsignedLongLong:s.f_blocks * block], NSFileSystemSize,
                             [NSNumber numberWithUnsignedLongLong:s.f_bavail * block], NSFileSystemFreeSize,
                             [NSNumber numberWithUnsignedLongLong:s.f_files], NSFileSystemNodes,
                             [NSNumber numberWithUnsignedLongLong:s.f_ffree], NSFileSystemFreeNodes,
                             [NSNumber numberWithUnsignedLongLong:number], NSFileSystemNumber, nil];
}
@end

/* ---- a locale's names ------------------------------------------------------------ *
 * English names only: this system's own translations aren't reachable from
 * here, and an English name reads better than none. A code Ferry has no
 * name for gives nil, as a Mac does for a code it doesn't know. */

static NSString *name_in(const char *const table[][2], NSString *code)
{
    if (![code isKindOfClass:[NSString class]])
        return nil;
    const char *c = [code UTF8String];
    for (int i = 0; table[i][0]; i++)
        if (strcasecmp(table[i][0], c) == 0)
            return [NSString stringWithUTF8String:table[i][1]];
    return nil;
}

static const char *const languages[][2] = {
    {"en", "English"}, {"de", "German"}, {"fr", "French"}, {"es", "Spanish"}, {"it", "Italian"},
    {"pt", "Portuguese"}, {"nl", "Dutch"}, {"sv", "Swedish"}, {"da", "Danish"}, {"nb", "Norwegian Bokmål"},
    {"fi", "Finnish"}, {"pl", "Polish"}, {"cs", "Czech"}, {"sk", "Slovak"}, {"hu", "Hungarian"},
    {"ro", "Romanian"}, {"bg", "Bulgarian"}, {"el", "Greek"}, {"tr", "Turkish"}, {"ru", "Russian"},
    {"uk", "Ukrainian"}, {"be", "Belarusian"}, {"hr", "Croatian"}, {"sr", "Serbian"}, {"sl", "Slovenian"},
    {"et", "Estonian"}, {"lv", "Latvian"}, {"lt", "Lithuanian"}, {"he", "Hebrew"}, {"ar", "Arabic"},
    {"fa", "Persian"}, {"hi", "Hindi"}, {"bn", "Bangla"}, {"th", "Thai"}, {"vi", "Vietnamese"},
    {"id", "Indonesian"}, {"ms", "Malay"}, {"zh", "Chinese"}, {"ja", "Japanese"}, {"ko", "Korean"},
    {"ca", "Catalan"}, {"eu", "Basque"}, {"gl", "Galician"}, {"is", "Icelandic"}, {"ga", "Irish"},
    {"cy", "Welsh"}, {"ka", "Georgian"}, {"hy", "Armenian"}, {"kk", "Kazakh"}, {"az", "Azerbaijani"},
    {NULL, NULL}};

static const char *const regions[][2] = {
    {"US", "United States"}, {"GB", "United Kingdom"}, {"CA", "Canada"}, {"AU", "Australia"},
    {"NZ", "New Zealand"}, {"IE", "Ireland"}, {"DE", "Germany"}, {"AT", "Austria"}, {"CH", "Switzerland"},
    {"FR", "France"}, {"BE", "Belgium"}, {"NL", "Netherlands"}, {"LU", "Luxembourg"}, {"ES", "Spain"},
    {"PT", "Portugal"}, {"IT", "Italy"}, {"SE", "Sweden"}, {"NO", "Norway"}, {"DK", "Denmark"},
    {"FI", "Finland"}, {"IS", "Iceland"}, {"PL", "Poland"}, {"CZ", "Czechia"}, {"SK", "Slovakia"},
    {"HU", "Hungary"}, {"RO", "Romania"}, {"BG", "Bulgaria"}, {"GR", "Greece"}, {"TR", "Türkiye"},
    {"RU", "Russia"}, {"UA", "Ukraine"}, {"BY", "Belarus"}, {"HR", "Croatia"}, {"RS", "Serbia"},
    {"SI", "Slovenia"}, {"EE", "Estonia"}, {"LV", "Latvia"}, {"LT", "Lithuania"}, {"IL", "Israel"},
    {"SA", "Saudi Arabia"}, {"AE", "United Arab Emirates"}, {"EG", "Egypt"}, {"IN", "India"},
    {"CN", "China mainland"}, {"TW", "Taiwan"}, {"HK", "Hong Kong"}, {"JP", "Japan"}, {"KR", "South Korea"},
    {"TH", "Thailand"}, {"VN", "Vietnam"}, {"ID", "Indonesia"}, {"MY", "Malaysia"}, {"SG", "Singapore"},
    {"PH", "Philippines"}, {"MX", "Mexico"}, {"BR", "Brazil"}, {"AR", "Argentina"}, {"CL", "Chile"},
    {"CO", "Colombia"}, {"PE", "Peru"}, {"ZA", "South Africa"}, {"NG", "Nigeria"}, {"KE", "Kenya"},
    {NULL, NULL}};

static const char *const calendars[][2] = {
    {"gregorian", "Gregorian Calendar"}, {"buddhist", "Buddhist Calendar"}, {"chinese", "Chinese Calendar"},
    {"coptic", "Coptic Calendar"}, {"ethiopic", "Ethiopic Calendar"}, {"ethiopic-amete-alem", "Ethiopic Amete Alem Calendar"},
    {"hebrew", "Hebrew Calendar"}, {"iso8601", "ISO-8601 Calendar"}, {"indian", "Indian National Calendar"},
    {"islamic", "Hijri Calendar"}, {"islamic-civil", "Hijri Calendar (tabular, civil epoch)"},
    {"islamic-tbla", "Hijri Calendar (tabular, astronomical epoch)"}, {"islamic-umalqura", "Hijri Calendar (Umm al-Qura)"},
    {"japanese", "Japanese Calendar"}, {"persian", "Persian Calendar"}, {"roc", "Minguo Calendar"},
    {NULL, NULL}};

@implementation NSLocale (FerryLocalizedNames)
- (NSString *)localizedStringForLanguageCode:(NSString *)code
{
    if (![code isKindOfClass:[NSString class]])
        return nil;
    NSString *lang = [[NSLocale componentsFromLocaleIdentifier:code] objectForKey:NSLocaleLanguageCode] ?: code;
    return name_in(languages, lang);
}
- (NSString *)localizedStringForCountryCode:(NSString *)code { return name_in(regions, code); }
- (NSString *)localizedStringForCalendarIdentifier:(NSString *)identifier { return name_in(calendars, identifier); }
- (NSString *)localizedStringForLocaleIdentifier:(NSString *)identifier
{
    if (![identifier isKindOfClass:[NSString class]])
        return nil;
    NSDictionary *parts = [NSLocale componentsFromLocaleIdentifier:identifier];
    NSString *lang = name_in(languages, [parts objectForKey:NSLocaleLanguageCode] ?: identifier);
    NSString *region = name_in(regions, [parts objectForKey:NSLocaleCountryCode]);
    if (lang && region)
        return [NSString stringWithFormat:@"%@ (%@)", lang, region];
    return lang;
}
@end
