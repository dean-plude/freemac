/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry)
 * UniformTypeIdentifiers' UTType (freemac 1.225, Ferry 0.49.0), over the
 * uniform type identifier calls of UTType.m: see UniformTypeIdentifiers.h.
 * Written from Apple's public documentation; no Apple code was read.
 *
 * The system types' constants are made when Foundation is loaded, before
 * the program's own code runs; this file defines them as variables (a
 * program sees them as constants). */
#define _FERRY_UTI_DEFINING
#import <Foundation/Foundation.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#include <CoreServices/CoreServices.h>

NSString *const UTTagClassFilenameExtension = @"public.filename-extension";
NSString *const UTTagClassMIMEType = @"public.mime-type";

UTType *UTTypeItem;
UTType *UTTypeContent;
UTType *UTTypeCompositeContent;
UTType *UTTypeData;
UTType *UTTypeDirectory;
UTType *UTTypeFolder;
UTType *UTTypeVolume;
UTType *UTTypePackage;
UTType *UTTypeBundle;
UTType *UTTypeApplication;
UTType *UTTypeApplicationBundle;
UTType *UTTypeFramework;
UTType *UTTypePlugIn;
UTType *UTTypeSymLink;
UTType *UTTypeAliasFile;
UTType *UTTypeURL;
UTType *UTTypeFileURL;
UTType *UTTypeText;
UTType *UTTypePlainText;
UTType *UTTypeUTF8PlainText;
UTType *UTTypeUTF16PlainText;
UTType *UTTypeRTF;
UTType *UTTypeHTML;
UTType *UTTypeXML;
UTType *UTTypeJSON;
UTType *UTTypeCommaSeparatedText;
UTType *UTTypeTabSeparatedText;
UTType *UTTypeSourceCode;
UTType *UTTypeCSource;
UTType *UTTypeObjectiveCSource;
UTType *UTTypeCHeader;
UTType *UTTypeScript;
UTType *UTTypeShellScript;
UTType *UTTypePythonScript;
UTType *UTTypeJavaScript;
UTType *UTTypeLog;
UTType *UTTypeImage;
UTType *UTTypePNG;
UTType *UTTypeJPEG;
UTType *UTTypeTIFF;
UTType *UTTypeGIF;
UTType *UTTypeBMP;
UTType *UTTypeICO;
UTType *UTTypeICNS;
UTType *UTTypeSVG;
UTType *UTTypePDF;
UTType *UTTypeRTFD;
UTType *UTTypeFlatRTFD;
UTType *UTTypeWebArchive;
UTType *UTTypePropertyList;
UTType *UTTypeXMLPropertyList;
UTType *UTTypeArchive;
UTType *UTTypeZipArchive;
UTType *UTTypeGZIP;
UTType *UTTypeBZ2;
UTType *UTTypeDiskImage;
UTType *UTTypeAudiovisual;
UTType *UTTypeMovie;
UTType *UTTypeAudio;
UTType *UTTypeMP3;
UTType *UTTypeMPEG4;
UTType *UTTypeQuickTimeMovie;
UTType *UTTypeWAV;
UTType *UTTypeFont;
UTType *UTTypeTrueTypeFont;
UTType *UTTypeOpenTypeFont;
UTType *UTTypeExecutable;
UTType *UTTypeUnixExecutable;
UTType *UTTypeDatabase;
UTType *UTTypeVCard;
UTType *UTTypeMessage;
UTType *UTTypeEmailMessage;
UTType *UTTypeSpreadsheet;
UTType *UTTypePresentation;
UTType *UTTypeX509Certificate;
UTType *UTTypeEPUB;

@interface UTType ()
- (instancetype)_initWithIdentifier:(NSString *)identifier;
@end

static UTType *ut_type(UTType *t) { return t; }

@implementation UTType {
    NSString *_identifier;
}
+ (void)load
{
    UTTypeItem = [[UTType alloc] _initWithIdentifier:@"public.item"];
    UTTypeContent = [[UTType alloc] _initWithIdentifier:@"public.content"];
    UTTypeCompositeContent = [[UTType alloc] _initWithIdentifier:@"public.composite-content"];
    UTTypeData = [[UTType alloc] _initWithIdentifier:@"public.data"];
    UTTypeDirectory = [[UTType alloc] _initWithIdentifier:@"public.directory"];
    UTTypeFolder = [[UTType alloc] _initWithIdentifier:@"public.folder"];
    UTTypeVolume = [[UTType alloc] _initWithIdentifier:@"public.volume"];
    UTTypePackage = [[UTType alloc] _initWithIdentifier:@"com.apple.package"];
    UTTypeBundle = [[UTType alloc] _initWithIdentifier:@"com.apple.bundle"];
    UTTypeApplication = [[UTType alloc] _initWithIdentifier:@"com.apple.application"];
    UTTypeApplicationBundle = [[UTType alloc] _initWithIdentifier:@"com.apple.application-bundle"];
    UTTypeFramework = [[UTType alloc] _initWithIdentifier:@"com.apple.framework"];
    UTTypePlugIn = [[UTType alloc] _initWithIdentifier:@"com.apple.plugin"];
    UTTypeSymLink = [[UTType alloc] _initWithIdentifier:@"public.symlink"];
    UTTypeAliasFile = [[UTType alloc] _initWithIdentifier:@"com.apple.alias-file"];
    UTTypeURL = [[UTType alloc] _initWithIdentifier:@"public.url"];
    UTTypeFileURL = [[UTType alloc] _initWithIdentifier:@"public.file-url"];
    UTTypeText = [[UTType alloc] _initWithIdentifier:@"public.text"];
    UTTypePlainText = [[UTType alloc] _initWithIdentifier:@"public.plain-text"];
    UTTypeUTF8PlainText = [[UTType alloc] _initWithIdentifier:@"public.utf8-plain-text"];
    UTTypeUTF16PlainText = [[UTType alloc] _initWithIdentifier:@"public.utf16-plain-text"];
    UTTypeRTF = [[UTType alloc] _initWithIdentifier:@"public.rtf"];
    UTTypeHTML = [[UTType alloc] _initWithIdentifier:@"public.html"];
    UTTypeXML = [[UTType alloc] _initWithIdentifier:@"public.xml"];
    UTTypeJSON = [[UTType alloc] _initWithIdentifier:@"public.json"];
    UTTypeCommaSeparatedText = [[UTType alloc] _initWithIdentifier:@"public.comma-separated-values-text"];
    UTTypeTabSeparatedText = [[UTType alloc] _initWithIdentifier:@"public.tab-separated-values-text"];
    UTTypeSourceCode = [[UTType alloc] _initWithIdentifier:@"public.source-code"];
    UTTypeCSource = [[UTType alloc] _initWithIdentifier:@"public.c-source"];
    UTTypeObjectiveCSource = [[UTType alloc] _initWithIdentifier:@"public.objective-c-source"];
    UTTypeCHeader = [[UTType alloc] _initWithIdentifier:@"public.c-header"];
    UTTypeScript = [[UTType alloc] _initWithIdentifier:@"public.script"];
    UTTypeShellScript = [[UTType alloc] _initWithIdentifier:@"public.shell-script"];
    UTTypePythonScript = [[UTType alloc] _initWithIdentifier:@"public.python-script"];
    UTTypeJavaScript = [[UTType alloc] _initWithIdentifier:@"com.netscape.javascript-source"];
    UTTypeLog = [[UTType alloc] _initWithIdentifier:@"public.log"];
    UTTypeImage = [[UTType alloc] _initWithIdentifier:@"public.image"];
    UTTypePNG = [[UTType alloc] _initWithIdentifier:@"public.png"];
    UTTypeJPEG = [[UTType alloc] _initWithIdentifier:@"public.jpeg"];
    UTTypeTIFF = [[UTType alloc] _initWithIdentifier:@"public.tiff"];
    UTTypeGIF = [[UTType alloc] _initWithIdentifier:@"com.compuserve.gif"];
    UTTypeBMP = [[UTType alloc] _initWithIdentifier:@"com.microsoft.bmp"];
    UTTypeICO = [[UTType alloc] _initWithIdentifier:@"com.microsoft.ico"];
    UTTypeICNS = [[UTType alloc] _initWithIdentifier:@"com.apple.icns"];
    UTTypeSVG = [[UTType alloc] _initWithIdentifier:@"public.svg-image"];
    UTTypePDF = [[UTType alloc] _initWithIdentifier:@"com.adobe.pdf"];
    UTTypeRTFD = [[UTType alloc] _initWithIdentifier:@"com.apple.rtfd"];
    UTTypeFlatRTFD = [[UTType alloc] _initWithIdentifier:@"com.apple.flat-rtfd"];
    UTTypeWebArchive = [[UTType alloc] _initWithIdentifier:@"com.apple.webarchive"];
    UTTypePropertyList = [[UTType alloc] _initWithIdentifier:@"com.apple.property-list"];
    UTTypeXMLPropertyList = [[UTType alloc] _initWithIdentifier:@"com.apple.xml-property-list"];
    UTTypeArchive = [[UTType alloc] _initWithIdentifier:@"public.archive"];
    UTTypeZipArchive = [[UTType alloc] _initWithIdentifier:@"com.pkware.zip-archive"];
    UTTypeGZIP = [[UTType alloc] _initWithIdentifier:@"org.gnu.gnu-zip-archive"];
    UTTypeBZ2 = [[UTType alloc] _initWithIdentifier:@"public.bzip2-archive"];
    UTTypeDiskImage = [[UTType alloc] _initWithIdentifier:@"public.disk-image"];
    UTTypeAudiovisual = [[UTType alloc] _initWithIdentifier:@"public.audiovisual-content"];
    UTTypeMovie = [[UTType alloc] _initWithIdentifier:@"public.movie"];
    UTTypeAudio = [[UTType alloc] _initWithIdentifier:@"public.audio"];
    UTTypeMP3 = [[UTType alloc] _initWithIdentifier:@"public.mp3"];
    UTTypeMPEG4 = [[UTType alloc] _initWithIdentifier:@"public.mpeg-4"];
    UTTypeQuickTimeMovie = [[UTType alloc] _initWithIdentifier:@"com.apple.quicktime-movie"];
    UTTypeWAV = [[UTType alloc] _initWithIdentifier:@"com.microsoft.waveform-audio"];
    UTTypeFont = [[UTType alloc] _initWithIdentifier:@"public.font"];
    UTTypeTrueTypeFont = [[UTType alloc] _initWithIdentifier:@"public.truetype-font"];
    UTTypeOpenTypeFont = [[UTType alloc] _initWithIdentifier:@"public.opentype-font"];
    UTTypeExecutable = [[UTType alloc] _initWithIdentifier:@"public.executable"];
    UTTypeUnixExecutable = [[UTType alloc] _initWithIdentifier:@"public.unix-executable"];
    UTTypeDatabase = [[UTType alloc] _initWithIdentifier:@"public.database"];
    UTTypeVCard = [[UTType alloc] _initWithIdentifier:@"public.vcard"];
    UTTypeMessage = [[UTType alloc] _initWithIdentifier:@"public.message"];
    UTTypeEmailMessage = [[UTType alloc] _initWithIdentifier:@"public.email-message"];
    UTTypeSpreadsheet = [[UTType alloc] _initWithIdentifier:@"public.spreadsheet"];
    UTTypePresentation = [[UTType alloc] _initWithIdentifier:@"public.presentation"];
    UTTypeX509Certificate = [[UTType alloc] _initWithIdentifier:@"public.x509-certificate"];
    UTTypeEPUB = [[UTType alloc] _initWithIdentifier:@"org.idpf.epub-container"];
}
+ (BOOL)supportsSecureCoding { return YES; }
- (instancetype)_initWithIdentifier:(NSString *)identifier
{
    if ((self = [super init]))
        _identifier = [identifier copy];
    return self;
}
- (void)dealloc
{
    [_identifier release];
    [super dealloc];
}
+ (instancetype)typeWithIdentifier:(NSString *)identifier
{
    if (![identifier isKindOfClass:[NSString class]] || ![identifier length])
        return nil;
    return [[[self alloc] _initWithIdentifier:identifier] autorelease];
}
+ (instancetype)typeWithTag:(NSString *)tag tagClass:(NSString *)tagClass conformingToType:(UTType *)supertype
{
    if (!tag || !tagClass)
        return nil;
    CFStringRef uti = UTTypeCreatePreferredIdentifierForTag((CFStringRef)tagClass, (CFStringRef)tag,
                                                            (CFStringRef)[ut_type(supertype) identifier]);
    UTType *t = [self typeWithIdentifier:(NSString *)uti];
    if (uti)
        CFRelease(uti);
    return t;
}
+ (NSArray *)typesWithTag:(NSString *)tag tagClass:(NSString *)tagClass conformingToType:(UTType *)supertype
{
    if (!tag || !tagClass)
        return @[];
    CFArrayRef all = UTTypeCreateAllIdentifiersForTag((CFStringRef)tagClass, (CFStringRef)tag,
                                                      (CFStringRef)[ut_type(supertype) identifier]);
    NSMutableArray *out = [NSMutableArray array];
    for (NSString *uti in (NSArray *)all)
        [out addObject:[self typeWithIdentifier:uti]];
    if (all)
        CFRelease(all);
    return out;
}
+ (instancetype)typeWithFilenameExtension:(NSString *)ext
{
    return [self typeWithTag:ext tagClass:UTTagClassFilenameExtension conformingToType:nil];
}
+ (instancetype)typeWithFilenameExtension:(NSString *)ext conformingToType:(UTType *)supertype
{
    return [self typeWithTag:ext tagClass:UTTagClassFilenameExtension conformingToType:supertype];
}
+ (instancetype)typeWithMIMEType:(NSString *)mime
{
    return [self typeWithTag:mime tagClass:UTTagClassMIMEType conformingToType:nil];
}
+ (instancetype)typeWithMIMEType:(NSString *)mime conformingToType:(UTType *)supertype
{
    return [self typeWithTag:mime tagClass:UTTagClassMIMEType conformingToType:supertype];
}
/* a type the program declares in its Info.plist is known by its
 * identifier; one it doesn't is still that identifier */
+ (instancetype)exportedTypeWithIdentifier:(NSString *)identifier { return [self typeWithIdentifier:identifier]; }
+ (instancetype)exportedTypeWithIdentifier:(NSString *)identifier conformingToType:(UTType *)parentType
{
    return [self typeWithIdentifier:identifier];
}
+ (instancetype)importedTypeWithIdentifier:(NSString *)identifier { return [self typeWithIdentifier:identifier]; }
+ (instancetype)importedTypeWithIdentifier:(NSString *)identifier conformingToType:(UTType *)parentType
{
    return [self typeWithIdentifier:identifier];
}

- (NSString *)identifier { return _identifier; }
- (NSString *)preferredFilenameExtension
{
    return [(NSString *)UTTypeCopyPreferredTagWithClass((CFStringRef)_identifier,
                                                        (CFStringRef)UTTagClassFilenameExtension) autorelease];
}
- (NSString *)preferredMIMEType
{
    return [(NSString *)UTTypeCopyPreferredTagWithClass((CFStringRef)_identifier, (CFStringRef)UTTagClassMIMEType)
        autorelease];
}
- (NSString *)localizedDescription
{
    return [(NSString *)UTTypeCopyDescription((CFStringRef)_identifier) autorelease];
}
- (NSDictionary *)tags
{
    NSMutableDictionary *out = [NSMutableDictionary dictionary];
    for (NSString *cls in @[ UTTagClassFilenameExtension, UTTagClassMIMEType ]) {
        NSArray *all = [(NSArray *)UTTypeCopyAllTagsWithClass((CFStringRef)_identifier, (CFStringRef)cls) autorelease];
        if ([all count])
            out[cls] = all;
    }
    return out;
}
- (NSNumber *)version
{
    NSDictionary *d = [(NSDictionary *)UTTypeCopyDeclaration((CFStringRef)_identifier) autorelease];
    id v = d[(NSString *)kUTTypeVersionKey];
    return [v isKindOfClass:[NSNumber class]] ? v : nil;
}
- (NSURL *)referenceURL
{
    NSDictionary *d = [(NSDictionary *)UTTypeCopyDeclaration((CFStringRef)_identifier) autorelease];
    id v = d[(NSString *)kUTTypeReferenceURLKey];
    return [v isKindOfClass:[NSString class]] ? [NSURL URLWithString:v] : nil;
}
- (BOOL)isDynamic { return UTTypeIsDynamic((CFStringRef)_identifier); }
- (BOOL)isDeclared { return UTTypeIsDeclared((CFStringRef)_identifier); }
- (BOOL)isPublicType { return [_identifier hasPrefix:@"public."]; }
- (BOOL)conformsToType:(UTType *)type
{
    NSString *other = [ut_type(type) identifier];
    return other && UTTypeConformsTo((CFStringRef)_identifier, (CFStringRef)other);
}
- (BOOL)isSupertypeOfType:(UTType *)type { return [ut_type(type) conformsToType:self] && ![self isEqual:type]; }
- (BOOL)isSubtypeOfType:(UTType *)type { return [self conformsToType:type] && ![self isEqual:ut_type(type)]; }
/* the system types it conforms to, besides itself */
- (NSSet *)supertypes
{
    NSMutableSet *out = [NSMutableSet set];
    for (NSString *uti in @[ @"public.item", @"public.content", @"public.composite-content", @"public.data", @"public.directory", @"public.folder", @"public.volume", @"com.apple.package", @"com.apple.bundle", @"com.apple.application", @"com.apple.application-bundle", @"com.apple.framework", @"com.apple.plugin", @"public.symlink", @"com.apple.alias-file", @"public.url", @"public.file-url", @"public.text", @"public.plain-text", @"public.utf8-plain-text", @"public.utf16-plain-text", @"public.rtf", @"public.html", @"public.xml", @"public.json", @"public.comma-separated-values-text", @"public.tab-separated-values-text", @"public.source-code", @"public.c-source", @"public.objective-c-source", @"public.c-header", @"public.script", @"public.shell-script", @"public.python-script", @"com.netscape.javascript-source", @"public.log", @"public.image", @"public.png", @"public.jpeg", @"public.tiff", @"com.compuserve.gif", @"com.microsoft.bmp", @"com.microsoft.ico", @"com.apple.icns", @"public.svg-image", @"com.adobe.pdf", @"com.apple.rtfd", @"com.apple.flat-rtfd", @"com.apple.webarchive", @"com.apple.property-list", @"com.apple.xml-property-list", @"public.archive", @"com.pkware.zip-archive", @"org.gnu.gnu-zip-archive", @"public.bzip2-archive", @"public.disk-image", @"public.audiovisual-content", @"public.movie", @"public.audio", @"public.mp3", @"public.mpeg-4", @"com.apple.quicktime-movie", @"com.microsoft.waveform-audio", @"public.font", @"public.truetype-font", @"public.opentype-font", @"public.executable", @"public.unix-executable", @"public.database", @"public.vcard", @"public.message", @"public.email-message", @"public.spreadsheet", @"public.presentation", @"public.x509-certificate", @"org.idpf.epub-container" ])
        if (![uti isEqualToString:_identifier] && UTTypeConformsTo((CFStringRef)_identifier, (CFStringRef)uti))
            [out addObject:[UTType typeWithIdentifier:uti]];
    return out;
}
- (BOOL)isEqual:(id)other
{
    return other == self || ([other isKindOfClass:[UTType class]] &&
                             UTTypeEqual((CFStringRef)_identifier, (CFStringRef)[(UTType *)other identifier]));
}
- (NSUInteger)hash { return [[_identifier lowercaseString] hash]; }
- (id)copyWithZone:(NSZone *)zone { return [self retain]; }
- (NSString *)description { return _identifier; }
- (NSString *)debugDescription { return [NSString stringWithFormat:@"<UTType: %p> %@", self, _identifier]; }
- (void)encodeWithCoder:(NSCoder *)coder { [coder encodeObject:_identifier forKey:@"UTTypeIdentifier"]; }
- (instancetype)initWithCoder:(NSCoder *)coder
{
    NSString *ident = [coder decodeObjectOfClass:[NSString class] forKey:@"UTTypeIdentifier"];
    if (![ident length]) {
        [self release];
        return nil;
    }
    return [self _initWithIdentifier:ident];
}
@end

@implementation NSString (UTAdditions)
- (NSString *)stringByAppendingPathComponent:(NSString *)partialName conformingToType:(UTType *)contentType
{
    return [[self stringByAppendingPathComponent:partialName] stringByAppendingPathExtensionForType:contentType];
}
- (NSString *)stringByAppendingPathExtensionForType:(UTType *)contentType
{
    UTType *t = ut_type(contentType);
    NSString *ext = [t preferredFilenameExtension];
    UTType *have = [[self pathExtension] length] ? [UTType typeWithFilenameExtension:[self pathExtension]] : nil;
    if (!ext || (have && [have conformsToType:t]))
        return self;
    return [self stringByAppendingPathExtension:ext];
}
@end
@implementation NSURL (UTAdditions)
- (NSURL *)URLByAppendingPathComponent:(NSString *)partialName conformingToType:(UTType *)contentType
{
    return [[self URLByAppendingPathComponent:partialName] URLByAppendingPathExtensionForType:contentType];
}
- (NSURL *)URLByAppendingPathExtensionForType:(UTType *)contentType
{
    NSString *last = [self lastPathComponent];
    NSString *with = [last stringByAppendingPathExtensionForType:contentType];
    return [with isEqualToString:last] ? self : [[self URLByDeletingLastPathComponent] URLByAppendingPathComponent:with];
}
@end
