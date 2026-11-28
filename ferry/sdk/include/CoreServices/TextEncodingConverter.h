/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: text encodings (TextCommon.h) and the Text Encoding Converter
 * (TextEncodingConverter.h), and a locale's name in parts, written from
 * Apple's public documentation for freemac 1.NEXT (Vim turns file names
 * and UTF-16 into UTF-8 with them). Not Apple's headers. Served from
 * Foundation's file (foundation/TextEncodingConverter.m). */
#ifndef _FERRY_TEXTENCODINGCONVERTER_H_
#define _FERRY_TEXTENCODINGCONVERTER_H_
#include <MacTypes.h>
#include <CoreServices/UnicodeUtilities.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef UInt32 TextEncoding;
typedef UInt32 TextEncodingBase;
typedef UInt32 TextEncodingVariant;
typedef UInt32 TextEncodingFormat;
typedef UInt8 *TextPtr;
typedef const UInt8 *ConstTextPtr;
typedef struct OpaqueTECObjectRef *TECObjectRef;

/* Bases: the Mac encodings below 0x100 are CFString's numbers. */
enum {
    kTextEncodingMacRoman = 0,
    kTextEncodingUnicodeDefault = 0x0100,
    kTextEncodingUnicodeV2_0 = 0x0103,
    kTextEncodingUnicodeV3_0 = 0x0104,
    kTextEncodingISOLatin1 = 0x0201,
    kTextEncodingWindowsLatin1 = 0x0500,
    kTextEncodingUS_ASCII = 0x0600,
};
enum { kTextEncodingDefaultVariant = 0, kTextEncodingDefaultFormat = 0 };
/* Unicode's variants (normalization) and formats */
enum {
    kUnicodeNoSubset = 0,
    kUnicodeCanonicalDecompVariant = 2,
    kUnicodeCanonicalCompVariant = 3,
    kUnicodeHFSPlusDecompVariant = 8,
    kUnicodeHFSPlusCompVariant = 9,
};
enum { kUnicode16BitFormat = 0, kUnicodeUTF7Format = 1, kUnicodeUTF8Format = 2, kUnicode32BitFormat = 3 };
enum {
    kTextUnsupportedEncodingErr = -8738,
    kTECOutputBufferFullStatus = -8785,
    kTECNoConversionPathErr = -8749,
};

TextEncoding CreateTextEncoding(TextEncodingBase base, TextEncodingVariant variant, TextEncodingFormat format);
TextEncodingBase GetTextEncodingBase(TextEncoding encoding);
TextEncodingVariant GetTextEncodingVariant(TextEncoding encoding);
TextEncodingFormat GetTextEncodingFormat(TextEncoding encoding);
OSStatus TECCreateConverter(TECObjectRef *newEncodingConverter, TextEncoding inputEncoding,
                            TextEncoding outputEncoding);
OSStatus TECDisposeConverter(TECObjectRef encodingConverter);
OSStatus TECClearConverterContextInfo(TECObjectRef encodingConverter);
OSStatus TECConvertText(TECObjectRef encodingConverter, ConstTextPtr inputBuffer, ByteCount inputBufferLength,
                        ByteCount *actualInputLength, TextPtr outputBuffer, ByteCount outputBufferLength,
                        ByteCount *actualOutputLength);
OSStatus TECFlushText(TECObjectRef encodingConverter, TextPtr outputBuffer, ByteCount outputBufferLength,
                      ByteCount *actualOutputLength);

/* A locale's name in parts, as "en_US"; NULL is the user's own locale. */
typedef UInt32 LocalePartMask;
enum {
    kLocaleLanguageMask = 1 << 0,
    kLocaleLanguageVariantMask = 1 << 1,
    kLocaleScriptMask = 1 << 2,
    kLocaleScriptVariantMask = 1 << 3,
    kLocaleRegionMask = 1 << 4,
    kLocaleRegionVariantMask = 1 << 5,
    kLocaleAllPartsMask = 0x3f,
};
OSStatus LocaleRefGetPartString(LocaleRef refLocale, LocalePartMask partMask, ByteCount maxStringLen,
                                char *partString);

#ifdef __cplusplus
}
#endif
#endif
