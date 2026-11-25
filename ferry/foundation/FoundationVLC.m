/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry)
 * What VLC's Mac interface calls besides the rest of Foundation (freemac
 * 1.NEXT, Ferry 0.NEXT): see FoundationVLC.h. */
#import <Foundation/Foundation.h>

@implementation NSString (FerryVLC)
+ (instancetype)localizedStringWithFormat:(NSString *)format, ...
{
    va_list ap;
    va_start(ap, format);
    NSString *s = [[[self alloc] initWithFormat:format arguments:ap] autorelease];
    va_end(ap);
    return s;
}
- (NSComparisonResult)compare:(NSString *)other options:(NSStringCompareOptions)mask range:(NSRange)range
{
    return [[self substringWithRange:range] compare:other options:mask];
}
- (NSComparisonResult)compare:(NSString *)other options:(NSStringCompareOptions)mask range:(NSRange)range
                       locale:(id)locale
{
    return [self compare:other options:mask range:range];
}
- (NSString *)stringByReplacingCharactersInRange:(NSRange)range withString:(NSString *)replacement
{
    NSMutableString *m = [[self mutableCopy] autorelease];
    [m replaceCharactersInRange:range withString:replacement ?: @""];
    return [[m copy] autorelease];
}
@end

@implementation NSLocale (FerryDirection)
/* the languages written right to left, by their ISO 639 codes */
+ (NSLocaleLanguageDirection)characterDirectionForLanguage:(NSString *)code
{
    if (![code length])
        return NSLocaleLanguageDirectionUnknown;
    NSString *lang = [[[code componentsSeparatedByCharactersInSet:
                                 [NSCharacterSet characterSetWithCharactersInString:@"-_"]] firstObject] lowercaseString];
    static NSSet *rtl;
    if (!rtl)
        rtl = [[NSSet alloc] initWithObjects:@"ar", @"arc", @"ckb", @"dv", @"fa", @"ha", @"he", @"iw", @"khw",
                                             @"ks", @"ku", @"ps", @"sd", @"syr", @"ug", @"ur", @"yi", nil];
    return [rtl containsObject:lang] ? NSLocaleLanguageDirectionRightToLeft : NSLocaleLanguageDirectionLeftToRight;
}
+ (NSLocaleLanguageDirection)lineDirectionForLanguage:(NSString *)code
{
    return [code length] ? NSLocaleLanguageDirectionTopToBottom : NSLocaleLanguageDirectionUnknown;
}
@end

@implementation NSScriptCommandDescription {
    NSString *_suite, *_name;
    NSDictionary *_declaration;
}
- (instancetype)initWithSuiteName:(NSString *)suiteName commandName:(NSString *)commandName
                       dictionary:(NSDictionary *)commandDeclaration
{
    if ((self = [super init])) {
        _suite = [suiteName copy];
        _name = [commandName copy];
        _declaration = [commandDeclaration copy];
    }
    return self;
}
- (instancetype)initWithCoder:(NSCoder *)coder { return [self init]; }
- (void)encodeWithCoder:(NSCoder *)coder
{
}
- (void)dealloc
{
    [_suite release];
    [_name release];
    [_declaration release];
    [super dealloc];
}
- (NSString *)suiteName { return _suite; }
- (NSString *)commandName { return _name; }
- (NSString *)commandClassName { return _declaration[@"CommandClass"] ?: @"NSScriptCommand"; }
- (NSString *)returnType { return _declaration[@"ResultAppleEventCode"]; }
- (NSArray<NSString *> *)argumentNames { return [_declaration[@"Arguments"] allKeys] ?: @[]; }
- (NSScriptCommand *)createCommandInstance
{
    Class c = NSClassFromString([self commandClassName]) ?: [NSScriptCommand class];
    return [[[c alloc] initWithCommandDescription:self] autorelease];
}
@end
