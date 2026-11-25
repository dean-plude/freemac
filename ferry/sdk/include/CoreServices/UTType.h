/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry SDK) */
/* Uniform type identifiers, the calls of Apple's public "UTType Reference"
 * (freemac 1.223, Ferry 0.47.0): which types a type conforms to, a type
 * from a filename extension or MIME type and back, and a type's
 * description. Ferry knows the common system types (UTCoreTypes.h) and the
 * types the program's own Info.plist declares; an extension or MIME type it
 * doesn't know gets a dynamic identifier ("dyn." and the tag). */
#ifndef _FERRY_UTTYPE_H
#define _FERRY_UTTYPE_H
#include <CoreFoundation/CoreFoundation.h>
#include <CoreServices/UTCoreTypes.h>

#ifdef __cplusplus
extern "C" {
#endif

extern const CFStringRef kUTTagClassFilenameExtension; /* "public.filename-extension" */
extern const CFStringRef kUTTagClassMIMEType;          /* "public.mime-type" */
extern const CFStringRef kUTTagClassNSPboardType;      /* "com.apple.nspboard-type" */
extern const CFStringRef kUTTagClassOSType;            /* "com.apple.ostype" */

extern const CFStringRef kUTExportedTypeDeclarationsKey;
extern const CFStringRef kUTImportedTypeDeclarationsKey;
extern const CFStringRef kUTTypeIdentifierKey;
extern const CFStringRef kUTTypeTagSpecificationKey;
extern const CFStringRef kUTTypeConformsToKey;
extern const CFStringRef kUTTypeDescriptionKey;
extern const CFStringRef kUTTypeIconFileKey;
extern const CFStringRef kUTTypeReferenceURLKey;
extern const CFStringRef kUTTypeVersionKey;

CFStringRef UTTypeCreatePreferredIdentifierForTag(CFStringRef tagClass, CFStringRef tag, CFStringRef conformingToUTI);
CFArrayRef UTTypeCreateAllIdentifiersForTag(CFStringRef tagClass, CFStringRef tag, CFStringRef conformingToUTI);
CFStringRef UTTypeCopyPreferredTagWithClass(CFStringRef uti, CFStringRef tagClass);
CFArrayRef UTTypeCopyAllTagsWithClass(CFStringRef uti, CFStringRef tagClass);
Boolean UTTypeEqual(CFStringRef a, CFStringRef b);
Boolean UTTypeConformsTo(CFStringRef uti, CFStringRef conformsToUTI);
CFStringRef UTTypeCopyDescription(CFStringRef uti);
CFDictionaryRef UTTypeCopyDeclaration(CFStringRef uti);
CFURLRef UTTypeCopyDeclaringBundleURL(CFStringRef uti);
Boolean UTTypeIsDeclared(CFStringRef uti);
Boolean UTTypeIsDynamic(CFStringRef uti);
CFStringRef UTCreateStringForOSType(OSType type);
OSType UTGetOSTypeFromString(CFStringRef string);

#ifdef __cplusplus
}
#endif
#endif
