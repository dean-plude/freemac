/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry SDK)
 * What VLC's Mac interface calls besides the rest of Foundation (freemac
 * 1.NEXT, Ferry 0.NEXT), written from Apple's public documentation. */
#ifndef _FERRY_FOUNDATION_VLC_H_
#define _FERRY_FOUNDATION_VLC_H_
/* a Mac's Foundation brings the printf formats in */
#include <inttypes.h>

@interface NSString (FerryVLC)
+ (instancetype)localizedStringWithFormat:(NSString *)format, ... NS_FORMAT_FUNCTION(1, 2);
- (NSComparisonResult)compare:(NSString *)other options:(NSStringCompareOptions)mask range:(NSRange)range;
- (NSComparisonResult)compare:(NSString *)other options:(NSStringCompareOptions)mask range:(NSRange)range
                       locale:(id)locale;
- (NSString *)stringByReplacingCharactersInRange:(NSRange)range withString:(NSString *)replacement;
@end

typedef NS_ENUM(NSUInteger, NSLocaleLanguageDirection) {
    NSLocaleLanguageDirectionUnknown = 0,
    NSLocaleLanguageDirectionLeftToRight = 1,
    NSLocaleLanguageDirectionRightToLeft = 2,
    NSLocaleLanguageDirectionTopToBottom = 3,
    NSLocaleLanguageDirectionBottomToTop = 4,
};
@interface NSLocale (FerryDirection)
+ (NSLocaleLanguageDirection)characterDirectionForLanguage:(NSString *)isoLangCode;
+ (NSLocaleLanguageDirection)lineDirectionForLanguage:(NSString *)isoLangCode;
@end

/* a scripting command's description: Ferry reads no scripting
 * dictionaries, so one is made only in the program */
@interface NSScriptCommandDescription : NSObject <NSCoding>
- (instancetype)initWithSuiteName:(NSString *)suiteName commandName:(NSString *)commandName
                       dictionary:(NSDictionary *)commandDeclaration;
@property (readonly, copy) NSString *suiteName;
@property (readonly, copy) NSString *commandName;
@property (readonly, copy) NSString *commandClassName;
@property (readonly, copy) NSString *returnType;
@property (readonly, copy) NSArray<NSString *> *argumentNames;
- (NSScriptCommand *)createCommandInstance;
@end

#endif
