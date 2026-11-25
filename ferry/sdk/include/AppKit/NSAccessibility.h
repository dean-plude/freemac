/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: NSAccessibility (freemac 1.222, Ferry 0.46.0), written from
 * Apple's public documentation: the attribute, role, subrole, action and
 * notification names, the NSAccessibility protocol that views, windows,
 * cells, menus and the application follow, the older informal methods
 * (accessibilityAttributeValue: and the rest) and the helper functions.
 * Ferry has no screen reader to answer, so values an app sets are kept and
 * read back, views answer their frame, parent, children and window, and
 * notifications go nowhere. Included from AppKit.h. */
#import <Foundation/Foundation.h>

typedef NSString *NSAccessibilityAttributeName;
typedef NSString *NSAccessibilityParameterizedAttributeName;
typedef NSString *NSAccessibilityRole;
typedef NSString *NSAccessibilitySubrole;
typedef NSString *NSAccessibilityActionName;
typedef NSString *NSAccessibilityNotificationName;
typedef NSString *NSAccessibilityNotificationUserInfoKey;
typedef NSString *NSAccessibilityOrientationValue;
typedef NSString *NSAccessibilitySortDirectionValue;
typedef NSString *NSAccessibilityRulerMarkerTypeValue;
typedef NSString *NSAccessibilityRulerUnitValue;
typedef NSString *NSAccessibilityLoadingToken;

typedef NS_ENUM(NSInteger, NSAccessibilityOrientation) {
    NSAccessibilityOrientationUnknown = 0,
    NSAccessibilityOrientationVertical = 1,
    NSAccessibilityOrientationHorizontal = 2,
};
typedef NS_ENUM(NSInteger, NSAccessibilitySortDirection) {
    NSAccessibilitySortDirectionUnknown = 0,
    NSAccessibilitySortDirectionAscending = 1,
    NSAccessibilitySortDirectionDescending = 2,
};
typedef NS_ENUM(NSInteger, NSAccessibilityPriorityLevel) {
    NSAccessibilityPriorityLow = 10,
    NSAccessibilityPriorityMedium = 50,
    NSAccessibilityPriorityHigh = 90,
};

/* attributes */
APPKIT_EXTERN NSAccessibilityAttributeName const NSAccessibilityRoleAttribute;
APPKIT_EXTERN NSAccessibilityAttributeName const NSAccessibilityRoleDescriptionAttribute;
APPKIT_EXTERN NSAccessibilityAttributeName const NSAccessibilitySubroleAttribute;
APPKIT_EXTERN NSAccessibilityAttributeName const NSAccessibilityDescriptionAttribute;
APPKIT_EXTERN NSAccessibilityAttributeName const NSAccessibilityTitleAttribute;
APPKIT_EXTERN NSAccessibilityAttributeName const NSAccessibilityValueAttribute;
APPKIT_EXTERN NSAccessibilityAttributeName const NSAccessibilityValueDescriptionAttribute;
APPKIT_EXTERN NSAccessibilityAttributeName const NSAccessibilityHelpAttribute;
APPKIT_EXTERN NSAccessibilityAttributeName const NSAccessibilityIdentifierAttribute;
APPKIT_EXTERN NSAccessibilityAttributeName const NSAccessibilityPlaceholderValueAttribute;
APPKIT_EXTERN NSAccessibilityAttributeName const NSAccessibilityParentAttribute;
APPKIT_EXTERN NSAccessibilityAttributeName const NSAccessibilityChildrenAttribute;
APPKIT_EXTERN NSAccessibilityAttributeName const NSAccessibilityChildrenInNavigationOrderAttribute;
APPKIT_EXTERN NSAccessibilityAttributeName const NSAccessibilityVisibleChildrenAttribute;
APPKIT_EXTERN NSAccessibilityAttributeName const NSAccessibilitySelectedChildrenAttribute;
APPKIT_EXTERN NSAccessibilityAttributeName const NSAccessibilityWindowAttribute;
APPKIT_EXTERN NSAccessibilityAttributeName const NSAccessibilityTopLevelUIElementAttribute;
APPKIT_EXTERN NSAccessibilityAttributeName const NSAccessibilityTitleUIElementAttribute;
APPKIT_EXTERN NSAccessibilityAttributeName const NSAccessibilityServesAsTitleForUIElementsAttribute;
APPKIT_EXTERN NSAccessibilityAttributeName const NSAccessibilityLinkedUIElementsAttribute;
APPKIT_EXTERN NSAccessibilityAttributeName const NSAccessibilitySharedFocusElementsAttribute;
APPKIT_EXTERN NSAccessibilityAttributeName const NSAccessibilityURLAttribute;
APPKIT_EXTERN NSAccessibilityAttributeName const NSAccessibilityFilenameAttribute;
APPKIT_EXTERN NSAccessibilityAttributeName const NSAccessibilityMinValueAttribute;
APPKIT_EXTERN NSAccessibilityAttributeName const NSAccessibilityMaxValueAttribute;
APPKIT_EXTERN NSAccessibilityAttributeName const NSAccessibilityContentsAttribute;
APPKIT_EXTERN NSAccessibilityAttributeName const NSAccessibilityHeaderAttribute;
APPKIT_EXTERN NSAccessibilityAttributeName const NSAccessibilityTabsAttribute;
APPKIT_EXTERN NSAccessibilityAttributeName const NSAccessibilityRowsAttribute;
APPKIT_EXTERN NSAccessibilityAttributeName const NSAccessibilityColumnsAttribute;
APPKIT_EXTERN NSAccessibilityAttributeName const NSAccessibilitySelectedRowsAttribute;
APPKIT_EXTERN NSAccessibilityAttributeName const NSAccessibilitySelectedColumnsAttribute;
APPKIT_EXTERN NSAccessibilityAttributeName const NSAccessibilityVisibleRowsAttribute;
APPKIT_EXTERN NSAccessibilityAttributeName const NSAccessibilityVisibleColumnsAttribute;
APPKIT_EXTERN NSAccessibilityAttributeName const NSAccessibilitySelectedCellsAttribute;
APPKIT_EXTERN NSAccessibilityAttributeName const NSAccessibilityColumnTitlesAttribute;
APPKIT_EXTERN NSAccessibilityAttributeName const NSAccessibilityWindowsAttribute;
APPKIT_EXTERN NSAccessibilityAttributeName const NSAccessibilityMainWindowAttribute;
APPKIT_EXTERN NSAccessibilityAttributeName const NSAccessibilityFocusedWindowAttribute;
APPKIT_EXTERN NSAccessibilityAttributeName const NSAccessibilityMenuBarAttribute;
APPKIT_EXTERN NSAccessibilityAttributeName const NSAccessibilityExtrasMenuBarAttribute;
APPKIT_EXTERN NSAccessibilityAttributeName const NSAccessibilityFocusedUIElementAttribute;
APPKIT_EXTERN NSAccessibilityAttributeName const NSAccessibilityCloseButtonAttribute;
APPKIT_EXTERN NSAccessibilityAttributeName const NSAccessibilityZoomButtonAttribute;
APPKIT_EXTERN NSAccessibilityAttributeName const NSAccessibilityMinimizeButtonAttribute;
APPKIT_EXTERN NSAccessibilityAttributeName const NSAccessibilityToolbarButtonAttribute;
APPKIT_EXTERN NSAccessibilityAttributeName const NSAccessibilityFullScreenButtonAttribute;
APPKIT_EXTERN NSAccessibilityAttributeName const NSAccessibilityDefaultButtonAttribute;
APPKIT_EXTERN NSAccessibilityAttributeName const NSAccessibilityCancelButtonAttribute;
APPKIT_EXTERN NSAccessibilityAttributeName const NSAccessibilityClearButtonAttribute;
APPKIT_EXTERN NSAccessibilityAttributeName const NSAccessibilitySearchButtonAttribute;
APPKIT_EXTERN NSAccessibilityAttributeName const NSAccessibilityProxyAttribute;
APPKIT_EXTERN NSAccessibilityAttributeName const NSAccessibilityGrowAreaAttribute;
APPKIT_EXTERN NSAccessibilityAttributeName const NSAccessibilityOverflowButtonAttribute;
APPKIT_EXTERN NSAccessibilityAttributeName const NSAccessibilityShownMenuAttribute;
APPKIT_EXTERN NSAccessibilityAttributeName const NSAccessibilitySearchMenuAttribute;
APPKIT_EXTERN NSAccessibilityAttributeName const NSAccessibilityDocumentAttribute;
APPKIT_EXTERN NSAccessibilityAttributeName const NSAccessibilitySelectedTextAttribute;
APPKIT_EXTERN NSAccessibilityAttributeName const NSAccessibilityUserInputLabelsAttribute;
APPKIT_EXTERN NSAccessibilityAttributeName const NSAccessibilityNextContentsAttribute;
APPKIT_EXTERN NSAccessibilityAttributeName const NSAccessibilityPreviousContentsAttribute;
APPKIT_EXTERN NSAccessibilityAttributeName const NSAccessibilityFocusedAttribute;
APPKIT_EXTERN NSAccessibilityAttributeName const NSAccessibilityEnabledAttribute;
APPKIT_EXTERN NSAccessibilityAttributeName const NSAccessibilitySelectedAttribute;
APPKIT_EXTERN NSAccessibilityAttributeName const NSAccessibilityExpandedAttribute;
APPKIT_EXTERN NSAccessibilityAttributeName const NSAccessibilityEditedAttribute;
APPKIT_EXTERN NSAccessibilityAttributeName const NSAccessibilityHiddenAttribute;
APPKIT_EXTERN NSAccessibilityAttributeName const NSAccessibilityMainAttribute;
APPKIT_EXTERN NSAccessibilityAttributeName const NSAccessibilityMinimizedAttribute;
APPKIT_EXTERN NSAccessibilityAttributeName const NSAccessibilityModalAttribute;
APPKIT_EXTERN NSAccessibilityAttributeName const NSAccessibilityFrontmostAttribute;
APPKIT_EXTERN NSAccessibilityAttributeName const NSAccessibilityDisclosingAttribute;
APPKIT_EXTERN NSAccessibilityAttributeName const NSAccessibilityRequiredAttribute;
APPKIT_EXTERN NSAccessibilityAttributeName const NSAccessibilityAlternateUIVisibleAttribute;
APPKIT_EXTERN NSAccessibilityAttributeName const NSAccessibilityOrderedByRowAttribute;
APPKIT_EXTERN NSAccessibilityAttributeName const NSAccessibilityIndexAttribute;
APPKIT_EXTERN NSAccessibilityAttributeName const NSAccessibilityDisclosureLevelAttribute;
APPKIT_EXTERN NSAccessibilityAttributeName const NSAccessibilityNumberOfCharactersAttribute;
APPKIT_EXTERN NSAccessibilityAttributeName const NSAccessibilityInsertionPointLineNumberAttribute;
APPKIT_EXTERN NSAccessibilityAttributeName const NSAccessibilitySelectedTextRangeAttribute;
APPKIT_EXTERN NSAccessibilityAttributeName const NSAccessibilityVisibleCharacterRangeAttribute;
APPKIT_EXTERN NSAccessibilityAttributeName const NSAccessibilityPositionAttribute;
APPKIT_EXTERN NSAccessibilityAttributeName const NSAccessibilitySizeAttribute;
APPKIT_EXTERN NSAccessibilityAttributeName const NSAccessibilityOrientationAttribute;
APPKIT_EXTERN NSAccessibilityAttributeName const NSAccessibilitySelectedRangesAttribute;
APPKIT_EXTERN NSAccessibilityAttributeName const NSAccessibilityVisibleTextAttribute;
APPKIT_EXTERN NSAccessibilityAttributeName const NSAccessibilityUnitsAttribute;
APPKIT_EXTERN NSAccessibilityAttributeName const NSAccessibilityHorizontalScrollBarAttribute;
APPKIT_EXTERN NSAccessibilityAttributeName const NSAccessibilityVerticalScrollBarAttribute;
APPKIT_EXTERN NSAccessibilityAttributeName const NSAccessibilitySplittersAttribute;
APPKIT_EXTERN NSAccessibilityAttributeName const NSAccessibilityIncrementorAttribute;
APPKIT_EXTERN NSAccessibilityAttributeName const NSAccessibilityDecrementButtonAttribute;
APPKIT_EXTERN NSAccessibilityAttributeName const NSAccessibilityIncrementButtonAttribute;
APPKIT_EXTERN NSAccessibilityAttributeName const NSAccessibilityDisclosureAttribute;
APPKIT_EXTERN NSAccessibilityAttributeName const NSAccessibilityDisclosedRowsAttribute;
APPKIT_EXTERN NSAccessibilityAttributeName const NSAccessibilityDisclosedByRowAttribute;
APPKIT_EXTERN NSAccessibilityAttributeName const NSAccessibilityWarningAttribute;
APPKIT_EXTERN NSAccessibilityAttributeName const NSAccessibilityCriticalAttribute;
APPKIT_EXTERN NSAccessibilityAttributeName const NSAccessibilityPlaceholderAttribute;
APPKIT_EXTERN NSAccessibilityAttributeName const NSAccessibilityAllowedValuesAttribute;
APPKIT_EXTERN NSAccessibilityAttributeName const NSAccessibilityLabelValueAttribute;
/* attributes that take a parameter */
APPKIT_EXTERN NSAccessibilityParameterizedAttributeName const NSAccessibilityLineForIndexParameterizedAttribute;
APPKIT_EXTERN NSAccessibilityParameterizedAttributeName const NSAccessibilityRangeForLineParameterizedAttribute;
APPKIT_EXTERN NSAccessibilityParameterizedAttributeName const NSAccessibilityStringForRangeParameterizedAttribute;
APPKIT_EXTERN NSAccessibilityParameterizedAttributeName const NSAccessibilityRangeForPositionParameterizedAttribute;
APPKIT_EXTERN NSAccessibilityParameterizedAttributeName const NSAccessibilityRangeForIndexParameterizedAttribute;
APPKIT_EXTERN NSAccessibilityParameterizedAttributeName const NSAccessibilityBoundsForRangeParameterizedAttribute;
APPKIT_EXTERN NSAccessibilityParameterizedAttributeName const NSAccessibilityRTFForRangeParameterizedAttribute;
APPKIT_EXTERN NSAccessibilityParameterizedAttributeName const NSAccessibilityStyleRangeForIndexParameterizedAttribute;
APPKIT_EXTERN NSAccessibilityParameterizedAttributeName const NSAccessibilityAttributedStringForRangeParameterizedAttribute;
APPKIT_EXTERN NSAccessibilityParameterizedAttributeName const NSAccessibilityCellForColumnAndRowParameterizedAttribute;
/* roles */
APPKIT_EXTERN NSAccessibilityRole const NSAccessibilityUnknownRole;
APPKIT_EXTERN NSAccessibilityRole const NSAccessibilityButtonRole;
APPKIT_EXTERN NSAccessibilityRole const NSAccessibilityRadioButtonRole;
APPKIT_EXTERN NSAccessibilityRole const NSAccessibilityCheckBoxRole;
APPKIT_EXTERN NSAccessibilityRole const NSAccessibilitySliderRole;
APPKIT_EXTERN NSAccessibilityRole const NSAccessibilityTabGroupRole;
APPKIT_EXTERN NSAccessibilityRole const NSAccessibilityTextFieldRole;
APPKIT_EXTERN NSAccessibilityRole const NSAccessibilityStaticTextRole;
APPKIT_EXTERN NSAccessibilityRole const NSAccessibilityTextAreaRole;
APPKIT_EXTERN NSAccessibilityRole const NSAccessibilityScrollAreaRole;
APPKIT_EXTERN NSAccessibilityRole const NSAccessibilityPopUpButtonRole;
APPKIT_EXTERN NSAccessibilityRole const NSAccessibilityMenuButtonRole;
APPKIT_EXTERN NSAccessibilityRole const NSAccessibilityTableRole;
APPKIT_EXTERN NSAccessibilityRole const NSAccessibilityApplicationRole;
APPKIT_EXTERN NSAccessibilityRole const NSAccessibilityGroupRole;
APPKIT_EXTERN NSAccessibilityRole const NSAccessibilityRadioGroupRole;
APPKIT_EXTERN NSAccessibilityRole const NSAccessibilityListRole;
APPKIT_EXTERN NSAccessibilityRole const NSAccessibilityScrollBarRole;
APPKIT_EXTERN NSAccessibilityRole const NSAccessibilityValueIndicatorRole;
APPKIT_EXTERN NSAccessibilityRole const NSAccessibilityImageRole;
APPKIT_EXTERN NSAccessibilityRole const NSAccessibilityMenuBarRole;
APPKIT_EXTERN NSAccessibilityRole const NSAccessibilityMenuRole;
APPKIT_EXTERN NSAccessibilityRole const NSAccessibilityMenuItemRole;
APPKIT_EXTERN NSAccessibilityRole const NSAccessibilityMenuBarItemRole;
APPKIT_EXTERN NSAccessibilityRole const NSAccessibilityColumnRole;
APPKIT_EXTERN NSAccessibilityRole const NSAccessibilityRowRole;
APPKIT_EXTERN NSAccessibilityRole const NSAccessibilityToolbarRole;
APPKIT_EXTERN NSAccessibilityRole const NSAccessibilityBusyIndicatorRole;
APPKIT_EXTERN NSAccessibilityRole const NSAccessibilityProgressIndicatorRole;
APPKIT_EXTERN NSAccessibilityRole const NSAccessibilityWindowRole;
APPKIT_EXTERN NSAccessibilityRole const NSAccessibilityDrawerRole;
APPKIT_EXTERN NSAccessibilityRole const NSAccessibilitySystemWideRole;
APPKIT_EXTERN NSAccessibilityRole const NSAccessibilityOutlineRole;
APPKIT_EXTERN NSAccessibilityRole const NSAccessibilityIncrementorRole;
APPKIT_EXTERN NSAccessibilityRole const NSAccessibilityBrowserRole;
APPKIT_EXTERN NSAccessibilityRole const NSAccessibilityComboBoxRole;
APPKIT_EXTERN NSAccessibilityRole const NSAccessibilitySplitGroupRole;
APPKIT_EXTERN NSAccessibilityRole const NSAccessibilitySplitterRole;
APPKIT_EXTERN NSAccessibilityRole const NSAccessibilityColorWellRole;
APPKIT_EXTERN NSAccessibilityRole const NSAccessibilityGrowAreaRole;
APPKIT_EXTERN NSAccessibilityRole const NSAccessibilitySheetRole;
APPKIT_EXTERN NSAccessibilityRole const NSAccessibilityHelpTagRole;
APPKIT_EXTERN NSAccessibilityRole const NSAccessibilityMatteRole;
APPKIT_EXTERN NSAccessibilityRole const NSAccessibilityRulerRole;
APPKIT_EXTERN NSAccessibilityRole const NSAccessibilityRulerMarkerRole;
APPKIT_EXTERN NSAccessibilityRole const NSAccessibilityLinkRole;
APPKIT_EXTERN NSAccessibilityRole const NSAccessibilityDisclosureTriangleRole;
APPKIT_EXTERN NSAccessibilityRole const NSAccessibilityGridRole;
APPKIT_EXTERN NSAccessibilityRole const NSAccessibilityRelevanceIndicatorRole;
APPKIT_EXTERN NSAccessibilityRole const NSAccessibilityLevelIndicatorRole;
APPKIT_EXTERN NSAccessibilityRole const NSAccessibilityCellRole;
APPKIT_EXTERN NSAccessibilityRole const NSAccessibilityPopoverRole;
APPKIT_EXTERN NSAccessibilityRole const NSAccessibilityPageRole;
APPKIT_EXTERN NSAccessibilityRole const NSAccessibilityLayoutAreaRole;
APPKIT_EXTERN NSAccessibilityRole const NSAccessibilityLayoutItemRole;
APPKIT_EXTERN NSAccessibilityRole const NSAccessibilityHandleRole;
/* subroles */
APPKIT_EXTERN NSAccessibilitySubrole const NSAccessibilityUnknownSubrole;
APPKIT_EXTERN NSAccessibilitySubrole const NSAccessibilityCloseButtonSubrole;
APPKIT_EXTERN NSAccessibilitySubrole const NSAccessibilityZoomButtonSubrole;
APPKIT_EXTERN NSAccessibilitySubrole const NSAccessibilityMinimizeButtonSubrole;
APPKIT_EXTERN NSAccessibilitySubrole const NSAccessibilityToolbarButtonSubrole;
APPKIT_EXTERN NSAccessibilitySubrole const NSAccessibilityFullScreenButtonSubrole;
APPKIT_EXTERN NSAccessibilitySubrole const NSAccessibilityTableRowSubrole;
APPKIT_EXTERN NSAccessibilitySubrole const NSAccessibilityOutlineRowSubrole;
APPKIT_EXTERN NSAccessibilitySubrole const NSAccessibilitySecureTextFieldSubrole;
APPKIT_EXTERN NSAccessibilitySubrole const NSAccessibilityStandardWindowSubrole;
APPKIT_EXTERN NSAccessibilitySubrole const NSAccessibilityDialogSubrole;
APPKIT_EXTERN NSAccessibilitySubrole const NSAccessibilitySystemDialogSubrole;
APPKIT_EXTERN NSAccessibilitySubrole const NSAccessibilityFloatingWindowSubrole;
APPKIT_EXTERN NSAccessibilitySubrole const NSAccessibilitySystemFloatingWindowSubrole;
APPKIT_EXTERN NSAccessibilitySubrole const NSAccessibilityIncrementArrowSubrole;
APPKIT_EXTERN NSAccessibilitySubrole const NSAccessibilityDecrementArrowSubrole;
APPKIT_EXTERN NSAccessibilitySubrole const NSAccessibilityIncrementPageSubrole;
APPKIT_EXTERN NSAccessibilitySubrole const NSAccessibilityDecrementPageSubrole;
APPKIT_EXTERN NSAccessibilitySubrole const NSAccessibilitySearchFieldSubrole;
APPKIT_EXTERN NSAccessibilitySubrole const NSAccessibilityTextAttachmentSubrole;
APPKIT_EXTERN NSAccessibilitySubrole const NSAccessibilityTextLinkSubrole;
APPKIT_EXTERN NSAccessibilitySubrole const NSAccessibilityTimelineSubrole;
APPKIT_EXTERN NSAccessibilitySubrole const NSAccessibilitySortButtonSubrole;
APPKIT_EXTERN NSAccessibilitySubrole const NSAccessibilityRatingIndicatorSubrole;
APPKIT_EXTERN NSAccessibilitySubrole const NSAccessibilityContentListSubrole;
APPKIT_EXTERN NSAccessibilitySubrole const NSAccessibilityDefinitionListSubrole;
APPKIT_EXTERN NSAccessibilitySubrole const NSAccessibilityToggleSubrole;
APPKIT_EXTERN NSAccessibilitySubrole const NSAccessibilitySwitchSubrole;
APPKIT_EXTERN NSAccessibilitySubrole const NSAccessibilityDescriptionListSubrole;
APPKIT_EXTERN NSAccessibilitySubrole const NSAccessibilityTabButtonSubrole;
APPKIT_EXTERN NSAccessibilitySubrole const NSAccessibilityCollectionListSubrole;
APPKIT_EXTERN NSAccessibilitySubrole const NSAccessibilitySectionListSubrole;
/* actions */
APPKIT_EXTERN NSAccessibilityActionName const NSAccessibilityPressAction;
APPKIT_EXTERN NSAccessibilityActionName const NSAccessibilityIncrementAction;
APPKIT_EXTERN NSAccessibilityActionName const NSAccessibilityDecrementAction;
APPKIT_EXTERN NSAccessibilityActionName const NSAccessibilityConfirmAction;
APPKIT_EXTERN NSAccessibilityActionName const NSAccessibilityPickAction;
APPKIT_EXTERN NSAccessibilityActionName const NSAccessibilityCancelAction;
APPKIT_EXTERN NSAccessibilityActionName const NSAccessibilityRaiseAction;
APPKIT_EXTERN NSAccessibilityActionName const NSAccessibilityShowMenuAction;
APPKIT_EXTERN NSAccessibilityActionName const NSAccessibilityDeleteAction;
APPKIT_EXTERN NSAccessibilityActionName const NSAccessibilityShowAlternateUIAction;
APPKIT_EXTERN NSAccessibilityActionName const NSAccessibilityShowDefaultUIAction;
/* notifications, and the keys of their user info */
APPKIT_EXTERN NSAccessibilityNotificationName const NSAccessibilityMainWindowChangedNotification;
APPKIT_EXTERN NSAccessibilityNotificationName const NSAccessibilityFocusedWindowChangedNotification;
APPKIT_EXTERN NSAccessibilityNotificationName const NSAccessibilityFocusedUIElementChangedNotification;
APPKIT_EXTERN NSAccessibilityNotificationName const NSAccessibilityApplicationActivatedNotification;
APPKIT_EXTERN NSAccessibilityNotificationName const NSAccessibilityApplicationDeactivatedNotification;
APPKIT_EXTERN NSAccessibilityNotificationName const NSAccessibilityApplicationHiddenNotification;
APPKIT_EXTERN NSAccessibilityNotificationName const NSAccessibilityApplicationShownNotification;
APPKIT_EXTERN NSAccessibilityNotificationName const NSAccessibilityWindowCreatedNotification;
APPKIT_EXTERN NSAccessibilityNotificationName const NSAccessibilityWindowMovedNotification;
APPKIT_EXTERN NSAccessibilityNotificationName const NSAccessibilityWindowResizedNotification;
APPKIT_EXTERN NSAccessibilityNotificationName const NSAccessibilityWindowMiniaturizedNotification;
APPKIT_EXTERN NSAccessibilityNotificationName const NSAccessibilityWindowDeminiaturizedNotification;
APPKIT_EXTERN NSAccessibilityNotificationName const NSAccessibilityDrawerCreatedNotification;
APPKIT_EXTERN NSAccessibilityNotificationName const NSAccessibilitySheetCreatedNotification;
APPKIT_EXTERN NSAccessibilityNotificationName const NSAccessibilityUIElementDestroyedNotification;
APPKIT_EXTERN NSAccessibilityNotificationName const NSAccessibilityValueChangedNotification;
APPKIT_EXTERN NSAccessibilityNotificationName const NSAccessibilityTitleChangedNotification;
APPKIT_EXTERN NSAccessibilityNotificationName const NSAccessibilityResizedNotification;
APPKIT_EXTERN NSAccessibilityNotificationName const NSAccessibilityMovedNotification;
APPKIT_EXTERN NSAccessibilityNotificationName const NSAccessibilityCreatedNotification;
APPKIT_EXTERN NSAccessibilityNotificationName const NSAccessibilityLayoutChangedNotification;
APPKIT_EXTERN NSAccessibilityNotificationName const NSAccessibilityHelpTagCreatedNotification;
APPKIT_EXTERN NSAccessibilityNotificationName const NSAccessibilitySelectedTextChangedNotification;
APPKIT_EXTERN NSAccessibilityNotificationName const NSAccessibilityRowCountChangedNotification;
APPKIT_EXTERN NSAccessibilityNotificationName const NSAccessibilitySelectedChildrenChangedNotification;
APPKIT_EXTERN NSAccessibilityNotificationName const NSAccessibilitySelectedRowsChangedNotification;
APPKIT_EXTERN NSAccessibilityNotificationName const NSAccessibilitySelectedColumnsChangedNotification;
APPKIT_EXTERN NSAccessibilityNotificationName const NSAccessibilityRowExpandedNotification;
APPKIT_EXTERN NSAccessibilityNotificationName const NSAccessibilityRowCollapsedNotification;
APPKIT_EXTERN NSAccessibilityNotificationName const NSAccessibilitySelectedCellsChangedNotification;
APPKIT_EXTERN NSAccessibilityNotificationName const NSAccessibilityUnitsChangedNotification;
APPKIT_EXTERN NSAccessibilityNotificationName const NSAccessibilitySelectedChildrenMovedNotification;
APPKIT_EXTERN NSAccessibilityNotificationName const NSAccessibilityAnnouncementRequestedNotification;
APPKIT_EXTERN NSAccessibilityNotificationUserInfoKey const NSAccessibilityUIElementsKey;
APPKIT_EXTERN NSAccessibilityNotificationUserInfoKey const NSAccessibilityPriorityKey;
APPKIT_EXTERN NSAccessibilityNotificationUserInfoKey const NSAccessibilityAnnouncementKey;
/* orientation values */
APPKIT_EXTERN NSAccessibilityOrientationValue const NSAccessibilityVerticalOrientationValue;
APPKIT_EXTERN NSAccessibilityOrientationValue const NSAccessibilityHorizontalOrientationValue;
APPKIT_EXTERN NSAccessibilityOrientationValue const NSAccessibilityUnknownOrientationValue;
APPKIT_EXTERN NSAccessibilitySortDirectionValue const NSAccessibilityAscendingSortDirectionValue;
APPKIT_EXTERN NSAccessibilitySortDirectionValue const NSAccessibilityDescendingSortDirectionValue;
APPKIT_EXTERN NSAccessibilitySortDirectionValue const NSAccessibilityUnknownSortDirectionValue;
/* raised by NSAccessibilityRaiseBadArgumentException */
APPKIT_EXTERN NSString *const NSAccessibilityException;
APPKIT_EXTERN NSString *const NSAccessibilityErrorCodeExceptionInfo;

/* What every accessibility element answers. */
@protocol NSAccessibilityElement <NSObject>
@required
- (NSRect)accessibilityFrame;
- (id)accessibilityParent;
@optional
- (BOOL)isAccessibilityFocused;
- (NSString *)accessibilityIdentifier;
@end

/* The modern accessibility API (OS X 10.10). */
@protocol NSAccessibility <NSObject>
@required
@property (copy) NSAccessibilityRole accessibilityRole;
@property (copy) NSString *accessibilityRoleDescription;
@property (copy) NSAccessibilitySubrole accessibilitySubrole;
@property (copy) NSString *accessibilityLabel;
@property (copy) NSString *accessibilityTitle;
@property (strong) id accessibilityValue;
@property (copy) NSString *accessibilityValueDescription;
@property (copy) NSString *accessibilityHelp;
@property (copy) NSString *accessibilityIdentifier;
@property (copy) NSString *accessibilityPlaceholderValue;
@property (weak) id accessibilityParent;
@property (copy) NSArray *accessibilityChildren;
@property (copy) NSArray *accessibilityChildrenInNavigationOrder;
@property (copy) NSArray *accessibilityVisibleChildren;
@property (copy) NSArray *accessibilitySelectedChildren;
@property (weak) id accessibilityWindow;
@property (weak) id accessibilityTopLevelUIElement;
@property (weak) id accessibilityTitleUIElement;
@property (copy) NSArray *accessibilityServesAsTitleForUIElements;
@property (copy) NSArray *accessibilityLinkedUIElements;
@property (copy) NSArray *accessibilitySharedFocusElements;
@property (copy) NSURL *accessibilityURL;
@property (copy) NSString *accessibilityFilename;
@property (strong) id accessibilityMinValue;
@property (strong) id accessibilityMaxValue;
@property (copy) NSArray *accessibilityContents;
@property (strong) id accessibilityHeader;
@property (copy) NSArray *accessibilityTabs;
@property (copy) NSArray *accessibilityRows;
@property (copy) NSArray *accessibilityColumns;
@property (copy) NSArray *accessibilitySelectedRows;
@property (copy) NSArray *accessibilitySelectedColumns;
@property (copy) NSArray *accessibilityVisibleRows;
@property (copy) NSArray *accessibilityVisibleColumns;
@property (copy) NSArray *accessibilitySelectedCells;
@property (copy) NSArray *accessibilityColumnTitles;
@property (copy) NSArray *accessibilityWindows;
@property (strong) id accessibilityMainWindow;
@property (strong) id accessibilityFocusedWindow;
@property (strong) id accessibilityMenuBar;
@property (strong) id accessibilityExtrasMenuBar;
@property (strong) id accessibilityApplicationFocusedUIElement;
@property (strong) id accessibilityCloseButton;
@property (strong) id accessibilityZoomButton;
@property (strong) id accessibilityMinimizeButton;
@property (strong) id accessibilityToolbarButton;
@property (strong) id accessibilityFullScreenButton;
@property (strong) id accessibilityDefaultButton;
@property (strong) id accessibilityCancelButton;
@property (strong) id accessibilityClearButton;
@property (strong) id accessibilitySearchButton;
@property (strong) id accessibilityProxy;
@property (strong) id accessibilityGrowArea;
@property (strong) id accessibilityOverflowButton;
@property (strong) id accessibilityShownMenu;
@property (strong) id accessibilitySearchMenu;
@property (copy) NSString *accessibilityDocument;
@property (copy) NSString *accessibilitySelectedText;
@property (copy) NSArray *accessibilityUserInputLabels;
@property (copy) NSArray *accessibilityNextContents;
@property (copy) NSArray *accessibilityPreviousContents;
@property (getter=isAccessibilityElement) BOOL accessibilityElement;
@property (getter=isAccessibilityFocused) BOOL accessibilityFocused;
@property (getter=isAccessibilityEnabled) BOOL accessibilityEnabled;
@property (getter=isAccessibilitySelected) BOOL accessibilitySelected;
@property (getter=isAccessibilityExpanded) BOOL accessibilityExpanded;
@property (getter=isAccessibilityEdited) BOOL accessibilityEdited;
@property (getter=isAccessibilityHidden) BOOL accessibilityHidden;
@property (getter=isAccessibilityMain) BOOL accessibilityMain;
@property (getter=isAccessibilityMinimized) BOOL accessibilityMinimized;
@property (getter=isAccessibilityModal) BOOL accessibilityModal;
@property (getter=isAccessibilityFrontmost) BOOL accessibilityFrontmost;
@property (getter=isAccessibilityDisclosed) BOOL accessibilityDisclosed;
@property (getter=isAccessibilityRequired) BOOL accessibilityRequired;
@property (getter=isAccessibilityProtectedContent) BOOL accessibilityProtectedContent;
@property (getter=isAccessibilityAlternateUIVisible) BOOL accessibilityAlternateUIVisible;
@property (getter=isAccessibilityOrderedByRow) BOOL accessibilityOrderedByRow;
@property NSRect accessibilityFrame;
@property NSRect accessibilityFrameInParentSpace;
@property NSPoint accessibilityActivationPoint;
@property NSAccessibilityOrientation accessibilityOrientation;
@property NSInteger accessibilityIndex;
@property NSInteger accessibilityDisclosureLevel;
@property NSInteger accessibilityNumberOfCharacters;
@property NSInteger accessibilityInsertionPointLineNumber;
@property NSRange accessibilitySelectedTextRange;
@property NSRange accessibilityVisibleCharacterRange;
- (id)accessibilityFocusedUIElement;
- (id)accessibilityHitTest:(NSPoint)point;
- (BOOL)isAccessibilitySelectorAllowed:(SEL)selector;
- (NSInteger)accessibilityLineForIndex:(NSInteger)index;
- (NSRange)accessibilityRangeForLine:(NSInteger)line;
- (NSString *)accessibilityStringForRange:(NSRange)range;
- (NSRect)accessibilityFrameForRange:(NSRange)range;
- (NSRange)accessibilityRangeForPosition:(NSPoint)point;
- (NSRange)accessibilityRangeForIndex:(NSInteger)index;
- (NSAttributedString *)accessibilityAttributedStringForRange:(NSRange)range;
- (BOOL)accessibilityPerformPress;
- (BOOL)accessibilityPerformIncrement;
- (BOOL)accessibilityPerformDecrement;
- (BOOL)accessibilityPerformConfirm;
- (BOOL)accessibilityPerformPick;
- (BOOL)accessibilityPerformCancel;
- (BOOL)accessibilityPerformRaise;
- (BOOL)accessibilityPerformShowMenu;
- (BOOL)accessibilityPerformDelete;
- (BOOL)accessibilityPerformShowAlternateUI;
- (BOOL)accessibilityPerformShowDefaultUI;
@end

/* The protocols for each kind of element, as an app adopts them. */
@protocol NSAccessibilityButton <NSAccessibilityElement>
@required
- (NSString *)accessibilityLabel;
- (BOOL)accessibilityPerformPress;
@end
@protocol NSAccessibilitySwitch <NSAccessibilityButton>
@required
- (NSString *)accessibilityValue;
@optional
- (BOOL)accessibilityPerformIncrement;
- (BOOL)accessibilityPerformDecrement;
@end
@protocol NSAccessibilityRadioButton <NSAccessibilityButton>
@required
- (NSNumber *)accessibilityValue;
@end
@protocol NSAccessibilityCheckBox <NSAccessibilityButton>
@required
- (NSNumber *)accessibilityValue;
@end
@protocol NSAccessibilityStaticText <NSAccessibilityElement>
@required
- (NSString *)accessibilityValue;
@optional
- (NSAttributedString *)accessibilityAttributedStringForRange:(NSRange)range;
- (NSRange)accessibilityVisibleCharacterRange;
@end
@protocol NSAccessibilityNavigableStaticText <NSAccessibilityStaticText>
@required
- (NSString *)accessibilityStringForRange:(NSRange)range;
- (NSInteger)accessibilityLineForIndex:(NSInteger)index;
- (NSRange)accessibilityRangeForLine:(NSInteger)lineNumber;
- (NSRect)accessibilityFrameForRange:(NSRange)range;
@end
@protocol NSAccessibilityGroup <NSAccessibilityElement>
@end
@protocol NSAccessibilityProgressIndicator <NSAccessibilityGroup>
@required
- (NSNumber *)accessibilityValue;
@end
@protocol NSAccessibilityImage <NSAccessibilityElement>
@required
- (NSString *)accessibilityLabel;
@end
@protocol NSAccessibilityContainsTransientUI <NSAccessibilityElement>
@required
- (BOOL)accessibilityPerformShowAlternateUI;
- (BOOL)accessibilityPerformShowDefaultUI;
- (BOOL)isAccessibilityAlternateUIVisible;
@end

/* The older accessibility API, which every object answers. */
@interface NSObject (NSAccessibility)
- (NSArray *)accessibilityAttributeNames;
- (id)accessibilityAttributeValue:(NSAccessibilityAttributeName)attribute;
- (BOOL)accessibilityIsAttributeSettable:(NSAccessibilityAttributeName)attribute;
- (void)accessibilitySetValue:(id)value forAttribute:(NSAccessibilityAttributeName)attribute;
- (NSArray *)accessibilityParameterizedAttributeNames;
- (id)accessibilityAttributeValue:(NSAccessibilityParameterizedAttributeName)attribute forParameter:(id)parameter;
- (NSArray *)accessibilityActionNames;
- (NSString *)accessibilityActionDescription:(NSAccessibilityActionName)action;
- (void)accessibilityPerformAction:(NSAccessibilityActionName)action;
- (BOOL)accessibilityIsIgnored;
- (id)accessibilityHitTest:(NSPoint)point;
- (id)accessibilityFocusedUIElement;
- (NSUInteger)accessibilityIndexOfChild:(id)child;
- (NSUInteger)accessibilityArrayAttributeCount:(NSAccessibilityAttributeName)attribute;
- (NSArray *)accessibilityArrayAttributeValues:(NSAccessibilityAttributeName)attribute index:(NSUInteger)index
                                      maxCount:(NSUInteger)maxCount;
@property (readonly) BOOL accessibilityNotifiesWhenDestroyed;
- (BOOL)accessibilitySetOverrideValue:(id)value forAttribute:(NSAccessibilityAttributeName)attribute;
@end

/* An element of the app's own, for something that isn't a view. */
@interface NSAccessibilityElement : NSObject <NSAccessibility>
+ (instancetype FERRY_SWIFT_NONNULL)accessibilityElementWithRole:(NSAccessibilityRole)role frame:(NSRect)frame
                                       label:(NSString *)label parent:(id)parent;
- (void)accessibilityAddChildElement:(NSAccessibilityElement *)childElement;
@end

@interface NSView (NSAccessibility) <NSAccessibility, NSAccessibilityElement>
@end
@interface NSWindow (NSAccessibility) <NSAccessibility, NSAccessibilityElement>
@end
@interface NSApplication (NSAccessibility) <NSAccessibility, NSAccessibilityElement>
@end
@interface NSCell (NSAccessibility) <NSAccessibility, NSAccessibilityElement>
@end
@interface NSMenu (NSAccessibility) <NSAccessibility, NSAccessibilityElement>
@end
@interface NSMenuItem (NSAccessibility) <NSAccessibility, NSAccessibilityElement>
@end

#ifdef __cplusplus
extern "C" {
#endif
NSString *NSAccessibilityRoleDescription(NSAccessibilityRole role, NSAccessibilitySubrole subrole);
NSString *NSAccessibilityRoleDescriptionForUIElement(id element);
NSString *NSAccessibilityActionDescription(NSAccessibilityActionName action);
id NSAccessibilityUnignoredAncestor(id element);
id NSAccessibilityUnignoredDescendant(id element);
NSArray *NSAccessibilityUnignoredChildren(NSArray *originalChildren);
NSArray *NSAccessibilityUnignoredChildrenForOnlyChild(id originalChild);
void NSAccessibilityPostNotification(id element, NSAccessibilityNotificationName notification);
void NSAccessibilityPostNotificationWithUserInfo(id element, NSAccessibilityNotificationName notification,
                                                 NSDictionary *userInfo);
NSRect NSAccessibilityFrameInView(NSView *parentView, NSRect frame);
NSPoint NSAccessibilityPointInView(NSView *parentView, NSPoint point);
BOOL NSAccessibilitySetMayContainProtectedContent(BOOL flag);
void NSAccessibilityRaiseBadArgumentException(id element, NSString *attribute, id value);
#ifdef __cplusplus
}
#endif
