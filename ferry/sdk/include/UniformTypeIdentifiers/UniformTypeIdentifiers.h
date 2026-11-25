/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry SDK)
 * UniformTypeIdentifiers (freemac 1.225, Ferry 0.49.0): the UTType class
 * over the uniform type identifier calls of CoreServices/UTType.h, so it
 * knows the same types: the common system ones, as constants here, and the
 * ones the program's Info.plist declares; an extension or MIME type it
 * doesn't know gets a dynamic type. Written from Apple's public
 * documentation; not Apple's header. Implemented in foundation/UTTypes.m
 * (Foundation's file, as UniformTypeIdentifiers' link stub says). */
#ifndef _FERRY_UNIFORMTYPEIDENTIFIERS_H_
#define _FERRY_UNIFORMTYPEIDENTIFIERS_H_
#import <Foundation/Foundation.h>

#define UTI_EXTERN extern

@interface UTType : NSObject <NSCopying, NSSecureCoding>
+ (instancetype)typeWithIdentifier:(NSString *)identifier;
+ (instancetype)typeWithFilenameExtension:(NSString *)filenameExtension;
+ (instancetype)typeWithFilenameExtension:(NSString *)filenameExtension conformingToType:(UTType *)supertype;
+ (instancetype)typeWithMIMEType:(NSString *)mimeType;
+ (instancetype)typeWithMIMEType:(NSString *)mimeType conformingToType:(UTType *)supertype;
+ (instancetype)typeWithTag:(NSString *)tag tagClass:(NSString *)tagClass conformingToType:(UTType *)supertype;
+ (NSArray<UTType *> *)typesWithTag:(NSString *)tag tagClass:(NSString *)tagClass conformingToType:(UTType *)supertype;
+ (instancetype)exportedTypeWithIdentifier:(NSString *)identifier;
+ (instancetype)exportedTypeWithIdentifier:(NSString *)identifier conformingToType:(UTType *)parentType;
+ (instancetype)importedTypeWithIdentifier:(NSString *)identifier;
+ (instancetype)importedTypeWithIdentifier:(NSString *)identifier conformingToType:(UTType *)parentType;
- (instancetype)init NS_UNAVAILABLE;
@property (readonly, copy) NSString *identifier;
@property (readonly, copy) NSString *preferredFilenameExtension;
@property (readonly, copy) NSString *preferredMIMEType;
@property (readonly, copy) NSString *localizedDescription;
@property (readonly, copy) NSDictionary<NSString *, NSArray<NSString *> *> *tags;
@property (readonly) NSNumber *version;
@property (readonly) NSURL *referenceURL;
@property (readonly, getter=isDynamic) BOOL dynamic;
@property (readonly, getter=isDeclared) BOOL declared;
@property (readonly, getter=isPublicType) BOOL publicType;
- (BOOL)conformsToType:(UTType *)type;
- (BOOL)isSupertypeOfType:(UTType *)type;
- (BOOL)isSubtypeOfType:(UTType *)type;
@property (readonly, copy) NSSet<UTType *> *supertypes;
@end

UTI_EXTERN NSString *const UTTagClassFilenameExtension;
UTI_EXTERN NSString *const UTTagClassMIMEType;

/* the system types (made when Foundation is loaded) */
#ifndef _FERRY_UTI_DEFINING
UTI_EXTERN UTType *const UTTypeItem;   /* public.item */
UTI_EXTERN UTType *const UTTypeContent;   /* public.content */
UTI_EXTERN UTType *const UTTypeCompositeContent;   /* public.composite-content */
UTI_EXTERN UTType *const UTTypeData;   /* public.data */
UTI_EXTERN UTType *const UTTypeDirectory;   /* public.directory */
UTI_EXTERN UTType *const UTTypeFolder;   /* public.folder */
UTI_EXTERN UTType *const UTTypeVolume;   /* public.volume */
UTI_EXTERN UTType *const UTTypePackage;   /* com.apple.package */
UTI_EXTERN UTType *const UTTypeBundle;   /* com.apple.bundle */
UTI_EXTERN UTType *const UTTypeApplication;   /* com.apple.application */
UTI_EXTERN UTType *const UTTypeApplicationBundle;   /* com.apple.application-bundle */
UTI_EXTERN UTType *const UTTypeFramework;   /* com.apple.framework */
UTI_EXTERN UTType *const UTTypePlugIn;   /* com.apple.plugin */
UTI_EXTERN UTType *const UTTypeSymLink;   /* public.symlink */
UTI_EXTERN UTType *const UTTypeAliasFile;   /* com.apple.alias-file */
UTI_EXTERN UTType *const UTTypeURL;   /* public.url */
UTI_EXTERN UTType *const UTTypeFileURL;   /* public.file-url */
UTI_EXTERN UTType *const UTTypeText;   /* public.text */
UTI_EXTERN UTType *const UTTypePlainText;   /* public.plain-text */
UTI_EXTERN UTType *const UTTypeUTF8PlainText;   /* public.utf8-plain-text */
UTI_EXTERN UTType *const UTTypeUTF16PlainText;   /* public.utf16-plain-text */
UTI_EXTERN UTType *const UTTypeRTF;   /* public.rtf */
UTI_EXTERN UTType *const UTTypeHTML;   /* public.html */
UTI_EXTERN UTType *const UTTypeXML;   /* public.xml */
UTI_EXTERN UTType *const UTTypeJSON;   /* public.json */
UTI_EXTERN UTType *const UTTypeCommaSeparatedText;   /* public.comma-separated-values-text */
UTI_EXTERN UTType *const UTTypeTabSeparatedText;   /* public.tab-separated-values-text */
UTI_EXTERN UTType *const UTTypeSourceCode;   /* public.source-code */
UTI_EXTERN UTType *const UTTypeCSource;   /* public.c-source */
UTI_EXTERN UTType *const UTTypeObjectiveCSource;   /* public.objective-c-source */
UTI_EXTERN UTType *const UTTypeCHeader;   /* public.c-header */
UTI_EXTERN UTType *const UTTypeScript;   /* public.script */
UTI_EXTERN UTType *const UTTypeShellScript;   /* public.shell-script */
UTI_EXTERN UTType *const UTTypePythonScript;   /* public.python-script */
UTI_EXTERN UTType *const UTTypeJavaScript;   /* com.netscape.javascript-source */
UTI_EXTERN UTType *const UTTypeLog;   /* public.log */
UTI_EXTERN UTType *const UTTypeImage;   /* public.image */
UTI_EXTERN UTType *const UTTypePNG;   /* public.png */
UTI_EXTERN UTType *const UTTypeJPEG;   /* public.jpeg */
UTI_EXTERN UTType *const UTTypeTIFF;   /* public.tiff */
UTI_EXTERN UTType *const UTTypeGIF;   /* com.compuserve.gif */
UTI_EXTERN UTType *const UTTypeBMP;   /* com.microsoft.bmp */
UTI_EXTERN UTType *const UTTypeICO;   /* com.microsoft.ico */
UTI_EXTERN UTType *const UTTypeICNS;   /* com.apple.icns */
UTI_EXTERN UTType *const UTTypeSVG;   /* public.svg-image */
UTI_EXTERN UTType *const UTTypePDF;   /* com.adobe.pdf */
UTI_EXTERN UTType *const UTTypeRTFD;   /* com.apple.rtfd */
UTI_EXTERN UTType *const UTTypeFlatRTFD;   /* com.apple.flat-rtfd */
UTI_EXTERN UTType *const UTTypeWebArchive;   /* com.apple.webarchive */
UTI_EXTERN UTType *const UTTypePropertyList;   /* com.apple.property-list */
UTI_EXTERN UTType *const UTTypeXMLPropertyList;   /* com.apple.xml-property-list */
UTI_EXTERN UTType *const UTTypeArchive;   /* public.archive */
UTI_EXTERN UTType *const UTTypeZipArchive;   /* com.pkware.zip-archive */
UTI_EXTERN UTType *const UTTypeGZIP;   /* org.gnu.gnu-zip-archive */
UTI_EXTERN UTType *const UTTypeBZ2;   /* public.bzip2-archive */
UTI_EXTERN UTType *const UTTypeDiskImage;   /* public.disk-image */
UTI_EXTERN UTType *const UTTypeAudiovisual;   /* public.audiovisual-content */
UTI_EXTERN UTType *const UTTypeMovie;   /* public.movie */
UTI_EXTERN UTType *const UTTypeAudio;   /* public.audio */
UTI_EXTERN UTType *const UTTypeMP3;   /* public.mp3 */
UTI_EXTERN UTType *const UTTypeMPEG4;   /* public.mpeg-4 */
UTI_EXTERN UTType *const UTTypeQuickTimeMovie;   /* com.apple.quicktime-movie */
UTI_EXTERN UTType *const UTTypeWAV;   /* com.microsoft.waveform-audio */
UTI_EXTERN UTType *const UTTypeFont;   /* public.font */
UTI_EXTERN UTType *const UTTypeTrueTypeFont;   /* public.truetype-font */
UTI_EXTERN UTType *const UTTypeOpenTypeFont;   /* public.opentype-font */
UTI_EXTERN UTType *const UTTypeExecutable;   /* public.executable */
UTI_EXTERN UTType *const UTTypeUnixExecutable;   /* public.unix-executable */
UTI_EXTERN UTType *const UTTypeDatabase;   /* public.database */
UTI_EXTERN UTType *const UTTypeVCard;   /* public.vcard */
UTI_EXTERN UTType *const UTTypeMessage;   /* public.message */
UTI_EXTERN UTType *const UTTypeEmailMessage;   /* public.email-message */
UTI_EXTERN UTType *const UTTypeSpreadsheet;   /* public.spreadsheet */
UTI_EXTERN UTType *const UTTypePresentation;   /* public.presentation */
UTI_EXTERN UTType *const UTTypeX509Certificate;   /* public.x509-certificate */
UTI_EXTERN UTType *const UTTypeEPUB;   /* org.idpf.epub-container */
#endif

@interface NSString (UTAdditions)
- (NSString *)stringByAppendingPathComponent:(NSString *)partialName conformingToType:(UTType *)contentType;
- (NSString *)stringByAppendingPathExtensionForType:(UTType *)contentType;
@end
@interface NSURL (UTAdditions)
- (NSURL *)URLByAppendingPathComponent:(NSString *)partialName conformingToType:(UTType *)contentType;
- (NSURL *)URLByAppendingPathExtensionForType:(UTType *)contentType;
@end

#endif
