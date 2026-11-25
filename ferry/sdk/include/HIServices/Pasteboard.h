/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: the Pasteboard Manager, Carbon's C interface to the clipboard,
 * written from Apple's public "Pasteboard Manager Reference"; not Apple's
 * header. A PasteboardRef here wraps an NSPasteboard: the clipboard is the
 * general pasteboard, so what one side puts there the other reads, and the
 * desktop's clipboard sees its text. Flavors are uniform type identifiers;
 * a flavor put with no data is a promise, kept by the promise keeper when
 * something first asks for it. Served from AppKit's file, through Carbon
 * and ApplicationServices. */
#ifndef _FERRY_HISERVICES_PASTEBOARD_H_
#define _FERRY_HISERVICES_PASTEBOARD_H_
#include <CoreFoundation/CoreFoundation.h>
#include <CoreServices/CoreServices.h>
#include <MacTypes.h>

__FERRY_BEGIN

typedef struct OpaquePasteboardRef *PasteboardRef;
typedef void *PasteboardItemID;

typedef OptionBits PasteboardSyncFlags;
enum { kPasteboardModified = 1u << 0, kPasteboardClientIsOwner = 1u << 1 };

typedef OptionBits PasteboardFlavorFlags;
enum {
    kPasteboardFlavorNoFlags = 0,
    kPasteboardFlavorSenderOnly = 1u << 0,
    kPasteboardFlavorSenderTranslated = 1u << 1,
    kPasteboardFlavorNotSaved = 1u << 2,
    kPasteboardFlavorRequestOnly = 1u << 3,
    kPasteboardFlavorSystemTranslated = 1u << 8,
    kPasteboardFlavorPromised = 1u << 9
};

enum {
    badPasteboardSyncErr = -25130,
    badPasteboardIndexErr = -25131,
    badPasteboardItemErr = -25132,
    badPasteboardFlavorErr = -25133,
    duplicatePasteboardFlavorErr = -25134,
    notPasteboardOwnerErr = -25135,
    noPasteboardPromiseKeeperErr = -25136
};
#ifndef _FERRY_CANTGETFLAVORERR_
#define _FERRY_CANTGETFLAVORERR_
enum { cantGetFlavorErr = -1854 };
#endif

#define kPasteboardClipboard CFSTR("com.apple.pasteboard.clipboard")
#define kPasteboardFind CFSTR("com.apple.pasteboard.find")
#define kPasteboardUniqueName ((CFStringRef)NULL)
#define kPasteboardTypeFileURLPromise CFSTR("com.apple.pasteboard.promised-file-url")
#define kPasteboardTypeFilePromiseContent CFSTR("com.apple.pasteboard.promised-file-content-type")

typedef OSStatus (*PasteboardPromiseKeeperProcPtr)(PasteboardRef pasteboard, PasteboardItemID item,
                                                   CFStringRef flavorType, void *context);

OSStatus PasteboardCreate(CFStringRef inName, PasteboardRef *outPasteboard);
PasteboardSyncFlags PasteboardSynchronize(PasteboardRef inPasteboard);
OSStatus PasteboardClear(PasteboardRef inPasteboard);
OSStatus PasteboardCopyName(PasteboardRef inPasteboard, CFStringRef *outName);
OSStatus PasteboardGetItemCount(PasteboardRef inPasteboard, ItemCount *outItemCount);
OSStatus PasteboardGetItemIdentifier(PasteboardRef inPasteboard, CFIndex inIndex, PasteboardItemID *outItem);
OSStatus PasteboardCopyItemFlavors(PasteboardRef inPasteboard, PasteboardItemID inItem, CFArrayRef *outFlavorTypes);
OSStatus PasteboardGetItemFlavorFlags(PasteboardRef inPasteboard, PasteboardItemID inItem, CFStringRef inFlavorType,
                                      PasteboardFlavorFlags *outFlags);
OSStatus PasteboardCopyItemFlavorData(PasteboardRef inPasteboard, PasteboardItemID inItem, CFStringRef inFlavorType,
                                      CFDataRef *outData);
OSStatus PasteboardPutItemFlavor(PasteboardRef inPasteboard, PasteboardItemID inItem, CFStringRef inFlavorType,
                                 CFDataRef inData, PasteboardFlavorFlags inFlags);
OSStatus PasteboardSetPromiseKeeper(PasteboardRef inPasteboard, PasteboardPromiseKeeperProcPtr inPromiseKeeper,
                                    void *inContext);
OSStatus PasteboardResolvePromises(PasteboardRef inPasteboard);

__FERRY_END
#endif
