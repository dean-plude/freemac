/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: the Accessibility API's calls for finding and moving windows
 * (AXUIElement and AXValue), written from Apple's public documentation
 * (freemac 1.215, Ferry 0.41.0). On freemac they reach other apps' windows
 * through the compositor, once the user has allowed the app. */
#ifndef _FERRY_HISERVICES_ACCESSIBILITY_H_
#define _FERRY_HISERVICES_ACCESSIBILITY_H_
#include <CoreFoundation/CoreFoundation.h>
#include <CoreGraphics/CGGeometry.h>
#include <sys/types.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef const struct __AXUIElement *AXUIElementRef;
typedef const struct __AXValue *AXValueRef;
typedef int32_t AXError;

enum {
    kAXErrorSuccess = 0,
    kAXErrorFailure = -25200,
    kAXErrorIllegalArgument = -25201,
    kAXErrorInvalidUIElement = -25202,
    kAXErrorInvalidUIElementObserver = -25203,
    kAXErrorCannotComplete = -25204,
    kAXErrorAttributeUnsupported = -25205,
    kAXErrorActionUnsupported = -25206,
    kAXErrorNotificationUnsupported = -25207,
    kAXErrorNotImplemented = -25208,
    kAXErrorNotificationAlreadyRegistered = -25209,
    kAXErrorNotificationNotRegistered = -25210,
    kAXErrorAPIDisabled = -25211,
    kAXErrorNoValue = -25212,
    kAXErrorParameterizedAttributeUnsupported = -25213,
    kAXErrorNotEnoughPrecision = -25214,
};

typedef uint32_t AXValueType;
enum {
    kAXValueTypeCGPoint = 1,
    kAXValueTypeCGSize = 2,
    kAXValueTypeCGRect = 3,
    kAXValueTypeCFRange = 4,
    kAXValueTypeAXError = 5,
    kAXValueTypeIllegal = 0,
    kAXValueCGPointType = kAXValueTypeCGPoint,
    kAXValueCGSizeType = kAXValueTypeCGSize,
    kAXValueCGRectType = kAXValueTypeCGRect,
    kAXValueCFRangeType = kAXValueTypeCFRange,
    kAXValueAXErrorType = kAXValueTypeAXError,
    kAXValueIllegalType = kAXValueTypeIllegal,
};

Boolean AXIsProcessTrusted(void);
Boolean AXIsProcessTrustedWithOptions(CFDictionaryRef options);
Boolean AXAPIEnabled(void);
extern const CFStringRef kAXTrustedCheckOptionPrompt;

CFTypeID AXUIElementGetTypeID(void);
AXUIElementRef AXUIElementCreateSystemWide(void);
AXUIElementRef AXUIElementCreateApplication(pid_t pid);
AXError AXUIElementCopyAttributeNames(AXUIElementRef element, CFArrayRef *names);
AXError AXUIElementCopyAttributeValue(AXUIElementRef element, CFStringRef attribute, CFTypeRef *value);
AXError AXUIElementGetAttributeValueCount(AXUIElementRef element, CFStringRef attribute, CFIndex *count);
AXError AXUIElementCopyAttributeValues(AXUIElementRef element, CFStringRef attribute, CFIndex index,
                                       CFIndex maxValues, CFArrayRef *values);
AXError AXUIElementIsAttributeSettable(AXUIElementRef element, CFStringRef attribute, Boolean *settable);
AXError AXUIElementSetAttributeValue(AXUIElementRef element, CFStringRef attribute, CFTypeRef value);
AXError AXUIElementCopyActionNames(AXUIElementRef element, CFArrayRef *names);
AXError AXUIElementPerformAction(AXUIElementRef element, CFStringRef action);
AXError AXUIElementGetPid(AXUIElementRef element, pid_t *pid);
AXError AXUIElementSetMessagingTimeout(AXUIElementRef element, float timeoutInSeconds);
AXError AXUIElementCopyElementAtPosition(AXUIElementRef application, float x, float y, AXUIElementRef *element);

CFTypeID AXValueGetTypeID(void);
AXValueRef AXValueCreate(AXValueType theType, const void *valuePtr);
AXValueType AXValueGetType(AXValueRef value);
Boolean AXValueGetValue(AXValueRef value, AXValueType theType, void *valuePtr);

/* attributes */
#define kAXRoleAttribute CFSTR("AXRole")
#define kAXSubroleAttribute CFSTR("AXSubrole")
#define kAXRoleDescriptionAttribute CFSTR("AXRoleDescription")
#define kAXTitleAttribute CFSTR("AXTitle")
#define kAXPositionAttribute CFSTR("AXPosition")
#define kAXSizeAttribute CFSTR("AXSize")
#define kAXParentAttribute CFSTR("AXParent")
#define kAXWindowsAttribute CFSTR("AXWindows")
#define kAXMainWindowAttribute CFSTR("AXMainWindow")
#define kAXFocusedWindowAttribute CFSTR("AXFocusedWindow")
#define kAXFocusedApplicationAttribute CFSTR("AXFocusedApplication")
#define kAXFocusedUIElementAttribute CFSTR("AXFocusedUIElement")
#define kAXFocusedAttribute CFSTR("AXFocused")
#define kAXMainAttribute CFSTR("AXMain")
#define kAXMinimizedAttribute CFSTR("AXMinimized")
#define kAXFrontmostAttribute CFSTR("AXFrontmost")
#define kAXHiddenAttribute CFSTR("AXHidden")
#define kAXEnabledAttribute CFSTR("AXEnabled")
#define kAXModalAttribute CFSTR("AXModal")
/* more attributes, roles and actions (freemac 1.222, Ferry 0.46.0), as ShiftIt and Spectacle read them */
#define kAXChildrenAttribute CFSTR("AXChildren")
#define kAXValueAttribute CFSTR("AXValue")
#define kAXDescriptionAttribute CFSTR("AXDescription")
#define kAXHelpAttribute CFSTR("AXHelp")
#define kAXIdentifierAttribute CFSTR("AXIdentifier")
#define kAXWindowAttribute CFSTR("AXWindow")
#define kAXTopLevelUIElementAttribute CFSTR("AXTopLevelUIElement")
#define kAXFullScreenAttribute CFSTR("AXFullScreen")
#define kAXCloseButtonAttribute CFSTR("AXCloseButton")
#define kAXZoomButtonAttribute CFSTR("AXZoomButton")
#define kAXMinimizeButtonAttribute CFSTR("AXMinimizeButton")
#define kAXToolbarButtonAttribute CFSTR("AXToolbarButton")
#define kAXFullScreenButtonAttribute CFSTR("AXFullScreenButton")
#define kAXDefaultButtonAttribute CFSTR("AXDefaultButton")
#define kAXCancelButtonAttribute CFSTR("AXCancelButton")
#define kAXGrowAreaAttribute CFSTR("AXGrowArea")
#define kAXProxyAttribute CFSTR("AXProxy")
#define kAXDocumentAttribute CFSTR("AXDocument")
#define kAXMenuBarAttribute CFSTR("AXMenuBar")
#define kAXSelectedAttribute CFSTR("AXSelected")
#define kAXSelectedTextAttribute CFSTR("AXSelectedText")
/* roles and subroles */
#define kAXApplicationRole CFSTR("AXApplication")
#define kAXSystemWideRole CFSTR("AXSystemWide")
#define kAXWindowRole CFSTR("AXWindow")
#define kAXStandardWindowSubrole CFSTR("AXStandardWindow")
#define kAXDialogSubrole CFSTR("AXDialog")
#define kAXSystemDialogSubrole CFSTR("AXSystemDialog")
#define kAXFloatingWindowSubrole CFSTR("AXFloatingWindow")
#define kAXSystemFloatingWindowSubrole CFSTR("AXSystemFloatingWindow")
#define kAXCloseButtonSubrole CFSTR("AXCloseButton")
#define kAXZoomButtonSubrole CFSTR("AXZoomButton")
#define kAXMinimizeButtonSubrole CFSTR("AXMinimizeButton")
#define kAXFullScreenButtonSubrole CFSTR("AXFullScreenButton")
#define kAXUnknownSubrole CFSTR("AXUnknown")
#define kAXSheetRole CFSTR("AXSheet")
#define kAXDrawerRole CFSTR("AXDrawer")
#define kAXButtonRole CFSTR("AXButton")
#define kAXGroupRole CFSTR("AXGroup")
#define kAXMenuBarRole CFSTR("AXMenuBar")
#define kAXMenuRole CFSTR("AXMenu")
#define kAXMenuItemRole CFSTR("AXMenuItem")
#define kAXStaticTextRole CFSTR("AXStaticText")
#define kAXTextFieldRole CFSTR("AXTextField")
#define kAXUnknownRole CFSTR("AXUnknown")
/* actions */
#define kAXRaiseAction CFSTR("AXRaise")
#define kAXPressAction CFSTR("AXPress")
#define kAXCancelAction CFSTR("AXCancel")
#define kAXConfirmAction CFSTR("AXConfirm")
#define kAXIncrementAction CFSTR("AXIncrement")
#define kAXDecrementAction CFSTR("AXDecrement")
#define kAXShowMenuAction CFSTR("AXShowMenu")
#define kAXPickAction CFSTR("AXPick")

#ifdef __cplusplus
}
#endif
#endif
