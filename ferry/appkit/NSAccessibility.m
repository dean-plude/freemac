/* SPDX-License-Identifier: GPL-3.0-or-later
 * NSAccessibility (freemac 1.222, Ferry 0.46.0): the names, and the
 * protocol's methods with plain answers. There's no screen reader to tell,
 * so a value an app sets is kept on the object and read back; views,
 * windows and the application answer what they know of themselves (frame,
 * parent, children, window, title); and the older informal methods read
 * and write the same values by attribute name. The methods live on
 * AAccessibility and are copied, at load, onto the classes that follow the
 * protocol on a Mac, never replacing a method a class has of its own. */
#import "AInternal.h"
#include <objc/runtime.h>
#include <objc/message.h>

NSString *const NSAccessibilityRoleAttribute = @"AXRole";
NSString *const NSAccessibilityRoleDescriptionAttribute = @"AXRoleDescription";
NSString *const NSAccessibilitySubroleAttribute = @"AXSubrole";
NSString *const NSAccessibilityDescriptionAttribute = @"AXDescription";
NSString *const NSAccessibilityTitleAttribute = @"AXTitle";
NSString *const NSAccessibilityValueAttribute = @"AXValue";
NSString *const NSAccessibilityValueDescriptionAttribute = @"AXValueDescription";
NSString *const NSAccessibilityHelpAttribute = @"AXHelp";
NSString *const NSAccessibilityIdentifierAttribute = @"AXIdentifier";
NSString *const NSAccessibilityPlaceholderValueAttribute = @"AXPlaceholderValue";
NSString *const NSAccessibilityParentAttribute = @"AXParent";
NSString *const NSAccessibilityChildrenAttribute = @"AXChildren";
NSString *const NSAccessibilityChildrenInNavigationOrderAttribute = @"AXChildrenInNavigationOrder";
NSString *const NSAccessibilityVisibleChildrenAttribute = @"AXVisibleChildren";
NSString *const NSAccessibilitySelectedChildrenAttribute = @"AXSelectedChildren";
NSString *const NSAccessibilityWindowAttribute = @"AXWindow";
NSString *const NSAccessibilityTopLevelUIElementAttribute = @"AXTopLevelUIElement";
NSString *const NSAccessibilityTitleUIElementAttribute = @"AXTitleUIElement";
NSString *const NSAccessibilityServesAsTitleForUIElementsAttribute = @"AXServesAsTitleForUIElements";
NSString *const NSAccessibilityLinkedUIElementsAttribute = @"AXLinkedUIElements";
NSString *const NSAccessibilitySharedFocusElementsAttribute = @"AXSharedFocusElements";
NSString *const NSAccessibilityURLAttribute = @"AXURL";
NSString *const NSAccessibilityFilenameAttribute = @"AXFilename";
NSString *const NSAccessibilityMinValueAttribute = @"AXMinValue";
NSString *const NSAccessibilityMaxValueAttribute = @"AXMaxValue";
NSString *const NSAccessibilityContentsAttribute = @"AXContents";
NSString *const NSAccessibilityHeaderAttribute = @"AXHeader";
NSString *const NSAccessibilityTabsAttribute = @"AXTabs";
NSString *const NSAccessibilityRowsAttribute = @"AXRows";
NSString *const NSAccessibilityColumnsAttribute = @"AXColumns";
NSString *const NSAccessibilitySelectedRowsAttribute = @"AXSelectedRows";
NSString *const NSAccessibilitySelectedColumnsAttribute = @"AXSelectedColumns";
NSString *const NSAccessibilityVisibleRowsAttribute = @"AXVisibleRows";
NSString *const NSAccessibilityVisibleColumnsAttribute = @"AXVisibleColumns";
NSString *const NSAccessibilitySelectedCellsAttribute = @"AXSelectedCells";
NSString *const NSAccessibilityColumnTitlesAttribute = @"AXColumnTitles";
NSString *const NSAccessibilityWindowsAttribute = @"AXWindows";
NSString *const NSAccessibilityMainWindowAttribute = @"AXMainWindow";
NSString *const NSAccessibilityFocusedWindowAttribute = @"AXFocusedWindow";
NSString *const NSAccessibilityMenuBarAttribute = @"AXMenuBar";
NSString *const NSAccessibilityExtrasMenuBarAttribute = @"AXExtrasMenuBar";
NSString *const NSAccessibilityFocusedUIElementAttribute = @"AXFocusedUIElement";
NSString *const NSAccessibilityCloseButtonAttribute = @"AXCloseButton";
NSString *const NSAccessibilityZoomButtonAttribute = @"AXZoomButton";
NSString *const NSAccessibilityMinimizeButtonAttribute = @"AXMinimizeButton";
NSString *const NSAccessibilityToolbarButtonAttribute = @"AXToolbarButton";
NSString *const NSAccessibilityFullScreenButtonAttribute = @"AXFullScreenButton";
NSString *const NSAccessibilityDefaultButtonAttribute = @"AXDefaultButton";
NSString *const NSAccessibilityCancelButtonAttribute = @"AXCancelButton";
NSString *const NSAccessibilityClearButtonAttribute = @"AXClearButton";
NSString *const NSAccessibilitySearchButtonAttribute = @"AXSearchButton";
NSString *const NSAccessibilityProxyAttribute = @"AXProxy";
NSString *const NSAccessibilityGrowAreaAttribute = @"AXGrowArea";
NSString *const NSAccessibilityOverflowButtonAttribute = @"AXOverflowButton";
NSString *const NSAccessibilityShownMenuAttribute = @"AXShownMenu";
NSString *const NSAccessibilitySearchMenuAttribute = @"AXSearchMenu";
NSString *const NSAccessibilityDocumentAttribute = @"AXDocument";
NSString *const NSAccessibilitySelectedTextAttribute = @"AXSelectedText";
NSString *const NSAccessibilityUserInputLabelsAttribute = @"AXUserInputLabels";
NSString *const NSAccessibilityNextContentsAttribute = @"AXNextContents";
NSString *const NSAccessibilityPreviousContentsAttribute = @"AXPreviousContents";
NSString *const NSAccessibilityFocusedAttribute = @"AXFocused";
NSString *const NSAccessibilityEnabledAttribute = @"AXEnabled";
NSString *const NSAccessibilitySelectedAttribute = @"AXSelected";
NSString *const NSAccessibilityExpandedAttribute = @"AXExpanded";
NSString *const NSAccessibilityEditedAttribute = @"AXEdited";
NSString *const NSAccessibilityHiddenAttribute = @"AXHidden";
NSString *const NSAccessibilityMainAttribute = @"AXMain";
NSString *const NSAccessibilityMinimizedAttribute = @"AXMinimized";
NSString *const NSAccessibilityModalAttribute = @"AXModal";
NSString *const NSAccessibilityFrontmostAttribute = @"AXFrontmost";
NSString *const NSAccessibilityDisclosingAttribute = @"AXDisclosing";
NSString *const NSAccessibilityRequiredAttribute = @"AXRequired";
NSString *const NSAccessibilityAlternateUIVisibleAttribute = @"AXAlternateUIVisible";
NSString *const NSAccessibilityOrderedByRowAttribute = @"AXOrderedByRow";
NSString *const NSAccessibilityIndexAttribute = @"AXIndex";
NSString *const NSAccessibilityDisclosureLevelAttribute = @"AXDisclosureLevel";
NSString *const NSAccessibilityNumberOfCharactersAttribute = @"AXNumberOfCharacters";
NSString *const NSAccessibilityInsertionPointLineNumberAttribute = @"AXInsertionPointLineNumber";
NSString *const NSAccessibilitySelectedTextRangeAttribute = @"AXSelectedTextRange";
NSString *const NSAccessibilityVisibleCharacterRangeAttribute = @"AXVisibleCharacterRange";
NSString *const NSAccessibilityPositionAttribute = @"AXPosition";
NSString *const NSAccessibilitySizeAttribute = @"AXSize";
NSString *const NSAccessibilityOrientationAttribute = @"AXOrientation";
NSString *const NSAccessibilitySelectedRangesAttribute = @"AXSelectedRanges";
NSString *const NSAccessibilityVisibleTextAttribute = @"AXVisibleText";
NSString *const NSAccessibilityUnitsAttribute = @"AXUnits";
NSString *const NSAccessibilityHorizontalScrollBarAttribute = @"AXHorizontalScrollBar";
NSString *const NSAccessibilityVerticalScrollBarAttribute = @"AXVerticalScrollBar";
NSString *const NSAccessibilitySplittersAttribute = @"AXSplitters";
NSString *const NSAccessibilityIncrementorAttribute = @"AXIncrementor";
NSString *const NSAccessibilityDecrementButtonAttribute = @"AXDecrementButton";
NSString *const NSAccessibilityIncrementButtonAttribute = @"AXIncrementButton";
NSString *const NSAccessibilityDisclosureAttribute = @"AXDisclosure";
NSString *const NSAccessibilityDisclosedRowsAttribute = @"AXDisclosedRows";
NSString *const NSAccessibilityDisclosedByRowAttribute = @"AXDisclosedByRow";
NSString *const NSAccessibilityWarningAttribute = @"AXWarning";
NSString *const NSAccessibilityCriticalAttribute = @"AXCritical";
NSString *const NSAccessibilityPlaceholderAttribute = @"AXPlaceholder";
NSString *const NSAccessibilityAllowedValuesAttribute = @"AXAllowedValues";
NSString *const NSAccessibilityLabelValueAttribute = @"AXLabelValue";
NSString *const NSAccessibilityLineForIndexParameterizedAttribute = @"AXLineForIndex";
NSString *const NSAccessibilityRangeForLineParameterizedAttribute = @"AXRangeForLine";
NSString *const NSAccessibilityStringForRangeParameterizedAttribute = @"AXStringForRange";
NSString *const NSAccessibilityRangeForPositionParameterizedAttribute = @"AXRangeForPosition";
NSString *const NSAccessibilityRangeForIndexParameterizedAttribute = @"AXRangeForIndex";
NSString *const NSAccessibilityBoundsForRangeParameterizedAttribute = @"AXBoundsForRange";
NSString *const NSAccessibilityRTFForRangeParameterizedAttribute = @"AXRTFForRange";
NSString *const NSAccessibilityStyleRangeForIndexParameterizedAttribute = @"AXStyleRangeForIndex";
NSString *const NSAccessibilityAttributedStringForRangeParameterizedAttribute = @"AXAttributedStringForRange";
NSString *const NSAccessibilityCellForColumnAndRowParameterizedAttribute = @"AXCellForColumnAndRow";
NSString *const NSAccessibilityUnknownRole = @"AXUnknown";
NSString *const NSAccessibilityButtonRole = @"AXButton";
NSString *const NSAccessibilityRadioButtonRole = @"AXRadioButton";
NSString *const NSAccessibilityCheckBoxRole = @"AXCheckBox";
NSString *const NSAccessibilitySliderRole = @"AXSlider";
NSString *const NSAccessibilityTabGroupRole = @"AXTabGroup";
NSString *const NSAccessibilityTextFieldRole = @"AXTextField";
NSString *const NSAccessibilityStaticTextRole = @"AXStaticText";
NSString *const NSAccessibilityTextAreaRole = @"AXTextArea";
NSString *const NSAccessibilityScrollAreaRole = @"AXScrollArea";
NSString *const NSAccessibilityPopUpButtonRole = @"AXPopUpButton";
NSString *const NSAccessibilityMenuButtonRole = @"AXMenuButton";
NSString *const NSAccessibilityTableRole = @"AXTable";
NSString *const NSAccessibilityApplicationRole = @"AXApplication";
NSString *const NSAccessibilityGroupRole = @"AXGroup";
NSString *const NSAccessibilityRadioGroupRole = @"AXRadioGroup";
NSString *const NSAccessibilityListRole = @"AXList";
NSString *const NSAccessibilityScrollBarRole = @"AXScrollBar";
NSString *const NSAccessibilityValueIndicatorRole = @"AXValueIndicator";
NSString *const NSAccessibilityImageRole = @"AXImage";
NSString *const NSAccessibilityMenuBarRole = @"AXMenuBar";
NSString *const NSAccessibilityMenuRole = @"AXMenu";
NSString *const NSAccessibilityMenuItemRole = @"AXMenuItem";
NSString *const NSAccessibilityMenuBarItemRole = @"AXMenuBarItem";
NSString *const NSAccessibilityColumnRole = @"AXColumn";
NSString *const NSAccessibilityRowRole = @"AXRow";
NSString *const NSAccessibilityToolbarRole = @"AXToolbar";
NSString *const NSAccessibilityBusyIndicatorRole = @"AXBusyIndicator";
NSString *const NSAccessibilityProgressIndicatorRole = @"AXProgressIndicator";
NSString *const NSAccessibilityWindowRole = @"AXWindow";
NSString *const NSAccessibilityDrawerRole = @"AXDrawer";
NSString *const NSAccessibilitySystemWideRole = @"AXSystemWide";
NSString *const NSAccessibilityOutlineRole = @"AXOutline";
NSString *const NSAccessibilityIncrementorRole = @"AXIncrementor";
NSString *const NSAccessibilityBrowserRole = @"AXBrowser";
NSString *const NSAccessibilityComboBoxRole = @"AXComboBox";
NSString *const NSAccessibilitySplitGroupRole = @"AXSplitGroup";
NSString *const NSAccessibilitySplitterRole = @"AXSplitter";
NSString *const NSAccessibilityColorWellRole = @"AXColorWell";
NSString *const NSAccessibilityGrowAreaRole = @"AXGrowArea";
NSString *const NSAccessibilitySheetRole = @"AXSheet";
NSString *const NSAccessibilityHelpTagRole = @"AXHelpTag";
NSString *const NSAccessibilityMatteRole = @"AXMatte";
NSString *const NSAccessibilityRulerRole = @"AXRuler";
NSString *const NSAccessibilityRulerMarkerRole = @"AXRulerMarker";
NSString *const NSAccessibilityLinkRole = @"AXLink";
NSString *const NSAccessibilityDisclosureTriangleRole = @"AXDisclosureTriangle";
NSString *const NSAccessibilityGridRole = @"AXGrid";
NSString *const NSAccessibilityRelevanceIndicatorRole = @"AXRelevanceIndicator";
NSString *const NSAccessibilityLevelIndicatorRole = @"AXLevelIndicator";
NSString *const NSAccessibilityCellRole = @"AXCell";
NSString *const NSAccessibilityPopoverRole = @"AXPopover";
NSString *const NSAccessibilityPageRole = @"AXPage";
NSString *const NSAccessibilityLayoutAreaRole = @"AXLayoutArea";
NSString *const NSAccessibilityLayoutItemRole = @"AXLayoutItem";
NSString *const NSAccessibilityHandleRole = @"AXHandle";
NSString *const NSAccessibilityUnknownSubrole = @"AXUnknown";
NSString *const NSAccessibilityCloseButtonSubrole = @"AXCloseButton";
NSString *const NSAccessibilityZoomButtonSubrole = @"AXZoomButton";
NSString *const NSAccessibilityMinimizeButtonSubrole = @"AXMinimizeButton";
NSString *const NSAccessibilityToolbarButtonSubrole = @"AXToolbarButton";
NSString *const NSAccessibilityFullScreenButtonSubrole = @"AXFullScreenButton";
NSString *const NSAccessibilityTableRowSubrole = @"AXTableRow";
NSString *const NSAccessibilityOutlineRowSubrole = @"AXOutlineRow";
NSString *const NSAccessibilitySecureTextFieldSubrole = @"AXSecureTextField";
NSString *const NSAccessibilityStandardWindowSubrole = @"AXStandardWindow";
NSString *const NSAccessibilityDialogSubrole = @"AXDialog";
NSString *const NSAccessibilitySystemDialogSubrole = @"AXSystemDialog";
NSString *const NSAccessibilityFloatingWindowSubrole = @"AXFloatingWindow";
NSString *const NSAccessibilitySystemFloatingWindowSubrole = @"AXSystemFloatingWindow";
NSString *const NSAccessibilityIncrementArrowSubrole = @"AXIncrementArrow";
NSString *const NSAccessibilityDecrementArrowSubrole = @"AXDecrementArrow";
NSString *const NSAccessibilityIncrementPageSubrole = @"AXIncrementPage";
NSString *const NSAccessibilityDecrementPageSubrole = @"AXDecrementPage";
NSString *const NSAccessibilitySearchFieldSubrole = @"AXSearchField";
NSString *const NSAccessibilityTextAttachmentSubrole = @"AXTextAttachment";
NSString *const NSAccessibilityTextLinkSubrole = @"AXTextLink";
NSString *const NSAccessibilityTimelineSubrole = @"AXTimeline";
NSString *const NSAccessibilitySortButtonSubrole = @"AXSortButton";
NSString *const NSAccessibilityRatingIndicatorSubrole = @"AXRatingIndicator";
NSString *const NSAccessibilityContentListSubrole = @"AXContentList";
NSString *const NSAccessibilityDefinitionListSubrole = @"AXDefinitionList";
NSString *const NSAccessibilityToggleSubrole = @"AXToggle";
NSString *const NSAccessibilitySwitchSubrole = @"AXSwitch";
NSString *const NSAccessibilityDescriptionListSubrole = @"AXDescriptionList";
NSString *const NSAccessibilityTabButtonSubrole = @"AXTabButton";
NSString *const NSAccessibilityCollectionListSubrole = @"AXCollectionList";
NSString *const NSAccessibilitySectionListSubrole = @"AXSectionList";
NSString *const NSAccessibilityPressAction = @"AXPress";
NSString *const NSAccessibilityIncrementAction = @"AXIncrement";
NSString *const NSAccessibilityDecrementAction = @"AXDecrement";
NSString *const NSAccessibilityConfirmAction = @"AXConfirm";
NSString *const NSAccessibilityPickAction = @"AXPick";
NSString *const NSAccessibilityCancelAction = @"AXCancel";
NSString *const NSAccessibilityRaiseAction = @"AXRaise";
NSString *const NSAccessibilityShowMenuAction = @"AXShowMenu";
NSString *const NSAccessibilityDeleteAction = @"AXDelete";
NSString *const NSAccessibilityShowAlternateUIAction = @"AXShowAlternateUI";
NSString *const NSAccessibilityShowDefaultUIAction = @"AXShowDefaultUI";
NSString *const NSAccessibilityMainWindowChangedNotification = @"AXMainWindowChanged";
NSString *const NSAccessibilityFocusedWindowChangedNotification = @"AXFocusedWindowChanged";
NSString *const NSAccessibilityFocusedUIElementChangedNotification = @"AXFocusedUIElementChanged";
NSString *const NSAccessibilityApplicationActivatedNotification = @"AXApplicationActivated";
NSString *const NSAccessibilityApplicationDeactivatedNotification = @"AXApplicationDeactivated";
NSString *const NSAccessibilityApplicationHiddenNotification = @"AXApplicationHidden";
NSString *const NSAccessibilityApplicationShownNotification = @"AXApplicationShown";
NSString *const NSAccessibilityWindowCreatedNotification = @"AXWindowCreated";
NSString *const NSAccessibilityWindowMovedNotification = @"AXWindowMoved";
NSString *const NSAccessibilityWindowResizedNotification = @"AXWindowResized";
NSString *const NSAccessibilityWindowMiniaturizedNotification = @"AXWindowMiniaturized";
NSString *const NSAccessibilityWindowDeminiaturizedNotification = @"AXWindowDeminiaturized";
NSString *const NSAccessibilityDrawerCreatedNotification = @"AXDrawerCreated";
NSString *const NSAccessibilitySheetCreatedNotification = @"AXSheetCreated";
NSString *const NSAccessibilityUIElementDestroyedNotification = @"AXUIElementDestroyed";
NSString *const NSAccessibilityValueChangedNotification = @"AXValueChanged";
NSString *const NSAccessibilityTitleChangedNotification = @"AXTitleChanged";
NSString *const NSAccessibilityResizedNotification = @"AXResized";
NSString *const NSAccessibilityMovedNotification = @"AXMoved";
NSString *const NSAccessibilityCreatedNotification = @"AXCreated";
NSString *const NSAccessibilityLayoutChangedNotification = @"AXLayoutChanged";
NSString *const NSAccessibilityHelpTagCreatedNotification = @"AXHelpTagCreated";
NSString *const NSAccessibilitySelectedTextChangedNotification = @"AXSelectedTextChanged";
NSString *const NSAccessibilityRowCountChangedNotification = @"AXRowCountChanged";
NSString *const NSAccessibilitySelectedChildrenChangedNotification = @"AXSelectedChildrenChanged";
NSString *const NSAccessibilitySelectedRowsChangedNotification = @"AXSelectedRowsChanged";
NSString *const NSAccessibilitySelectedColumnsChangedNotification = @"AXSelectedColumnsChanged";
NSString *const NSAccessibilityRowExpandedNotification = @"AXRowExpanded";
NSString *const NSAccessibilityRowCollapsedNotification = @"AXRowCollapsed";
NSString *const NSAccessibilitySelectedCellsChangedNotification = @"AXSelectedCellsChanged";
NSString *const NSAccessibilityUnitsChangedNotification = @"AXUnitsChanged";
NSString *const NSAccessibilitySelectedChildrenMovedNotification = @"AXSelectedChildrenMoved";
NSString *const NSAccessibilityAnnouncementRequestedNotification = @"AXAnnouncementRequested";
NSString *const NSAccessibilityUIElementsKey = @"AXUIElementsKey";
NSString *const NSAccessibilityPriorityKey = @"AXPriorityKey";
NSString *const NSAccessibilityAnnouncementKey = @"AXAnnouncementKey";
NSString *const NSAccessibilityVerticalOrientationValue = @"AXVerticalOrientation";
NSString *const NSAccessibilityHorizontalOrientationValue = @"AXHorizontalOrientation";
NSString *const NSAccessibilityUnknownOrientationValue = @"AXUnknownOrientation";
NSString *const NSAccessibilityAscendingSortDirectionValue = @"AXAscendingSortDirection";
NSString *const NSAccessibilityDescendingSortDirectionValue = @"AXDescendingSortDirection";
NSString *const NSAccessibilityUnknownSortDirectionValue = @"AXUnknownSortDirection";
NSString *const NSAccessibilityException = @"NSAccessibilityException";
NSString *const NSAccessibilityErrorCodeExceptionInfo = @"NSAccessibilityErrorCodeExceptionInfo";

/* ---- values kept on the object ---- */

static id kept(id self, SEL key) { return objc_getAssociatedObject(self, key); }
static void keep(id self, SEL key, id value)
{
    objc_setAssociatedObject(self, key, value, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
static void keep_copy(id self, SEL key, id value)
{
    objc_setAssociatedObject(self, key, value, OBJC_ASSOCIATION_COPY_NONATOMIC);
}

/* the attributes the older methods read and write, and the methods behind them */
typedef enum { K_OBJ, K_BOOL, K_RECT, K_POINT, K_INT, K_RANGE, K_POSITION, K_SIZE, K_ORIENT } kind_t;
typedef struct {
    NSString *const *name;
    const char *getter, *setter;
    kind_t kind;
} attribute_t;
static const attribute_t attributes[] = {
    {&NSAccessibilityRoleAttribute, "accessibilityRole", "setAccessibilityRole:", K_OBJ},
    {&NSAccessibilityRoleDescriptionAttribute, "accessibilityRoleDescription", "setAccessibilityRoleDescription:", K_OBJ},
    {&NSAccessibilitySubroleAttribute, "accessibilitySubrole", "setAccessibilitySubrole:", K_OBJ},
    {&NSAccessibilityDescriptionAttribute, "accessibilityLabel", "setAccessibilityLabel:", K_OBJ},
    {&NSAccessibilityTitleAttribute, "accessibilityTitle", "setAccessibilityTitle:", K_OBJ},
    {&NSAccessibilityValueAttribute, "accessibilityValue", "setAccessibilityValue:", K_OBJ},
    {&NSAccessibilityValueDescriptionAttribute, "accessibilityValueDescription", "setAccessibilityValueDescription:", K_OBJ},
    {&NSAccessibilityHelpAttribute, "accessibilityHelp", "setAccessibilityHelp:", K_OBJ},
    {&NSAccessibilityIdentifierAttribute, "accessibilityIdentifier", "setAccessibilityIdentifier:", K_OBJ},
    {&NSAccessibilityPlaceholderValueAttribute, "accessibilityPlaceholderValue", "setAccessibilityPlaceholderValue:", K_OBJ},
    {&NSAccessibilityParentAttribute, "accessibilityParent", "setAccessibilityParent:", K_OBJ},
    {&NSAccessibilityChildrenAttribute, "accessibilityChildren", "setAccessibilityChildren:", K_OBJ},
    {&NSAccessibilityChildrenInNavigationOrderAttribute, "accessibilityChildrenInNavigationOrder", "setAccessibilityChildrenInNavigationOrder:", K_OBJ},
    {&NSAccessibilityVisibleChildrenAttribute, "accessibilityVisibleChildren", "setAccessibilityVisibleChildren:", K_OBJ},
    {&NSAccessibilitySelectedChildrenAttribute, "accessibilitySelectedChildren", "setAccessibilitySelectedChildren:", K_OBJ},
    {&NSAccessibilityWindowAttribute, "accessibilityWindow", "setAccessibilityWindow:", K_OBJ},
    {&NSAccessibilityTopLevelUIElementAttribute, "accessibilityTopLevelUIElement", "setAccessibilityTopLevelUIElement:", K_OBJ},
    {&NSAccessibilityTitleUIElementAttribute, "accessibilityTitleUIElement", "setAccessibilityTitleUIElement:", K_OBJ},
    {&NSAccessibilityServesAsTitleForUIElementsAttribute, "accessibilityServesAsTitleForUIElements", "setAccessibilityServesAsTitleForUIElements:", K_OBJ},
    {&NSAccessibilityLinkedUIElementsAttribute, "accessibilityLinkedUIElements", "setAccessibilityLinkedUIElements:", K_OBJ},
    {&NSAccessibilitySharedFocusElementsAttribute, "accessibilitySharedFocusElements", "setAccessibilitySharedFocusElements:", K_OBJ},
    {&NSAccessibilityURLAttribute, "accessibilityURL", "setAccessibilityURL:", K_OBJ},
    {&NSAccessibilityFilenameAttribute, "accessibilityFilename", "setAccessibilityFilename:", K_OBJ},
    {&NSAccessibilityMinValueAttribute, "accessibilityMinValue", "setAccessibilityMinValue:", K_OBJ},
    {&NSAccessibilityMaxValueAttribute, "accessibilityMaxValue", "setAccessibilityMaxValue:", K_OBJ},
    {&NSAccessibilityContentsAttribute, "accessibilityContents", "setAccessibilityContents:", K_OBJ},
    {&NSAccessibilityHeaderAttribute, "accessibilityHeader", "setAccessibilityHeader:", K_OBJ},
    {&NSAccessibilityTabsAttribute, "accessibilityTabs", "setAccessibilityTabs:", K_OBJ},
    {&NSAccessibilityRowsAttribute, "accessibilityRows", "setAccessibilityRows:", K_OBJ},
    {&NSAccessibilityColumnsAttribute, "accessibilityColumns", "setAccessibilityColumns:", K_OBJ},
    {&NSAccessibilitySelectedRowsAttribute, "accessibilitySelectedRows", "setAccessibilitySelectedRows:", K_OBJ},
    {&NSAccessibilitySelectedColumnsAttribute, "accessibilitySelectedColumns", "setAccessibilitySelectedColumns:", K_OBJ},
    {&NSAccessibilityVisibleRowsAttribute, "accessibilityVisibleRows", "setAccessibilityVisibleRows:", K_OBJ},
    {&NSAccessibilityVisibleColumnsAttribute, "accessibilityVisibleColumns", "setAccessibilityVisibleColumns:", K_OBJ},
    {&NSAccessibilitySelectedCellsAttribute, "accessibilitySelectedCells", "setAccessibilitySelectedCells:", K_OBJ},
    {&NSAccessibilityColumnTitlesAttribute, "accessibilityColumnTitles", "setAccessibilityColumnTitles:", K_OBJ},
    {&NSAccessibilityWindowsAttribute, "accessibilityWindows", "setAccessibilityWindows:", K_OBJ},
    {&NSAccessibilityMainWindowAttribute, "accessibilityMainWindow", "setAccessibilityMainWindow:", K_OBJ},
    {&NSAccessibilityFocusedWindowAttribute, "accessibilityFocusedWindow", "setAccessibilityFocusedWindow:", K_OBJ},
    {&NSAccessibilityMenuBarAttribute, "accessibilityMenuBar", "setAccessibilityMenuBar:", K_OBJ},
    {&NSAccessibilityExtrasMenuBarAttribute, "accessibilityExtrasMenuBar", "setAccessibilityExtrasMenuBar:", K_OBJ},
    {&NSAccessibilityFocusedUIElementAttribute, "accessibilityApplicationFocusedUIElement", "setAccessibilityApplicationFocusedUIElement:", K_OBJ},
    {&NSAccessibilityCloseButtonAttribute, "accessibilityCloseButton", "setAccessibilityCloseButton:", K_OBJ},
    {&NSAccessibilityZoomButtonAttribute, "accessibilityZoomButton", "setAccessibilityZoomButton:", K_OBJ},
    {&NSAccessibilityMinimizeButtonAttribute, "accessibilityMinimizeButton", "setAccessibilityMinimizeButton:", K_OBJ},
    {&NSAccessibilityToolbarButtonAttribute, "accessibilityToolbarButton", "setAccessibilityToolbarButton:", K_OBJ},
    {&NSAccessibilityFullScreenButtonAttribute, "accessibilityFullScreenButton", "setAccessibilityFullScreenButton:", K_OBJ},
    {&NSAccessibilityDefaultButtonAttribute, "accessibilityDefaultButton", "setAccessibilityDefaultButton:", K_OBJ},
    {&NSAccessibilityCancelButtonAttribute, "accessibilityCancelButton", "setAccessibilityCancelButton:", K_OBJ},
    {&NSAccessibilityClearButtonAttribute, "accessibilityClearButton", "setAccessibilityClearButton:", K_OBJ},
    {&NSAccessibilitySearchButtonAttribute, "accessibilitySearchButton", "setAccessibilitySearchButton:", K_OBJ},
    {&NSAccessibilityProxyAttribute, "accessibilityProxy", "setAccessibilityProxy:", K_OBJ},
    {&NSAccessibilityGrowAreaAttribute, "accessibilityGrowArea", "setAccessibilityGrowArea:", K_OBJ},
    {&NSAccessibilityOverflowButtonAttribute, "accessibilityOverflowButton", "setAccessibilityOverflowButton:", K_OBJ},
    {&NSAccessibilityShownMenuAttribute, "accessibilityShownMenu", "setAccessibilityShownMenu:", K_OBJ},
    {&NSAccessibilitySearchMenuAttribute, "accessibilitySearchMenu", "setAccessibilitySearchMenu:", K_OBJ},
    {&NSAccessibilityDocumentAttribute, "accessibilityDocument", "setAccessibilityDocument:", K_OBJ},
    {&NSAccessibilitySelectedTextAttribute, "accessibilitySelectedText", "setAccessibilitySelectedText:", K_OBJ},
    {&NSAccessibilityUserInputLabelsAttribute, "accessibilityUserInputLabels", "setAccessibilityUserInputLabels:", K_OBJ},
    {&NSAccessibilityNextContentsAttribute, "accessibilityNextContents", "setAccessibilityNextContents:", K_OBJ},
    {&NSAccessibilityPreviousContentsAttribute, "accessibilityPreviousContents", "setAccessibilityPreviousContents:", K_OBJ},
    {&NSAccessibilityFocusedAttribute, "isAccessibilityFocused", "setAccessibilityFocused:", K_BOOL},
    {&NSAccessibilityEnabledAttribute, "isAccessibilityEnabled", "setAccessibilityEnabled:", K_BOOL},
    {&NSAccessibilitySelectedAttribute, "isAccessibilitySelected", "setAccessibilitySelected:", K_BOOL},
    {&NSAccessibilityExpandedAttribute, "isAccessibilityExpanded", "setAccessibilityExpanded:", K_BOOL},
    {&NSAccessibilityEditedAttribute, "isAccessibilityEdited", "setAccessibilityEdited:", K_BOOL},
    {&NSAccessibilityHiddenAttribute, "isAccessibilityHidden", "setAccessibilityHidden:", K_BOOL},
    {&NSAccessibilityMainAttribute, "isAccessibilityMain", "setAccessibilityMain:", K_BOOL},
    {&NSAccessibilityMinimizedAttribute, "isAccessibilityMinimized", "setAccessibilityMinimized:", K_BOOL},
    {&NSAccessibilityModalAttribute, "isAccessibilityModal", "setAccessibilityModal:", K_BOOL},
    {&NSAccessibilityFrontmostAttribute, "isAccessibilityFrontmost", "setAccessibilityFrontmost:", K_BOOL},
    {&NSAccessibilityDisclosingAttribute, "isAccessibilityDisclosed", "setAccessibilityDisclosed:", K_BOOL},
    {&NSAccessibilityRequiredAttribute, "isAccessibilityRequired", "setAccessibilityRequired:", K_BOOL},
    {&NSAccessibilityAlternateUIVisibleAttribute, "isAccessibilityAlternateUIVisible", "setAccessibilityAlternateUIVisible:", K_BOOL},
    {&NSAccessibilityOrderedByRowAttribute, "isAccessibilityOrderedByRow", "setAccessibilityOrderedByRow:", K_BOOL},
    {&NSAccessibilityIndexAttribute, "accessibilityIndex", "setAccessibilityIndex:", K_INT},
    {&NSAccessibilityDisclosureLevelAttribute, "accessibilityDisclosureLevel", "setAccessibilityDisclosureLevel:", K_INT},
    {&NSAccessibilityNumberOfCharactersAttribute, "accessibilityNumberOfCharacters", "setAccessibilityNumberOfCharacters:", K_INT},
    {&NSAccessibilityInsertionPointLineNumberAttribute, "accessibilityInsertionPointLineNumber", "setAccessibilityInsertionPointLineNumber:", K_INT},
    {&NSAccessibilitySelectedTextRangeAttribute, "accessibilitySelectedTextRange", "setAccessibilitySelectedTextRange:", K_RANGE},
    {&NSAccessibilityVisibleCharacterRangeAttribute, "accessibilityVisibleCharacterRange", "setAccessibilityVisibleCharacterRange:", K_RANGE},
    {&NSAccessibilityPositionAttribute, "accessibilityFrame", NULL, K_POSITION},
    {&NSAccessibilitySizeAttribute, "accessibilityFrame", NULL, K_SIZE},
    {&NSAccessibilityOrientationAttribute, "accessibilityOrientation", NULL, K_ORIENT},
};
#define NATTRIBUTES (sizeof attributes / sizeof attributes[0])

@interface AAccessibility : NSObject
@end

@implementation AAccessibility

/* copies these methods onto the classes that follow the protocol */
+ (void)load
{
    static const char *const classes[] = {"NSView", "NSWindow", "NSApplication", "NSCell", "NSMenu", "NSMenuItem",
                                          "NSAccessibilityElement"};
    unsigned int n = 0;
    Method *ms = class_copyMethodList(self, &n);
    for (size_t c = 0; c < sizeof classes / sizeof classes[0]; c++) {
        Class cls = objc_getClass(classes[c]);
        if (!cls)
            continue;
        for (unsigned int i = 0; i < n; i++)
            class_addMethod(cls, method_getName(ms[i]), method_getImplementation(ms[i]),
                            method_getTypeEncoding(ms[i]));
        class_addProtocol(cls, @protocol(NSAccessibility));
        class_addProtocol(cls, @protocol(NSAccessibilityElement));
    }
    free(ms);
}

- (NSString *)accessibilityRoleDescription { return kept(self, @selector(accessibilityRoleDescription)); }
- (void)setAccessibilityRoleDescription:(NSString *)v { keep_copy(self, @selector(accessibilityRoleDescription), v); }
- (NSAccessibilitySubrole )accessibilitySubrole { return kept(self, @selector(accessibilitySubrole)); }
- (void)setAccessibilitySubrole:(NSAccessibilitySubrole )v { keep_copy(self, @selector(accessibilitySubrole), v); }
- (id )accessibilityValue { return kept(self, @selector(accessibilityValue)); }
- (void)setAccessibilityValue:(id )v { keep(self, @selector(accessibilityValue), v); }
- (NSString *)accessibilityValueDescription { return kept(self, @selector(accessibilityValueDescription)); }
- (void)setAccessibilityValueDescription:(NSString *)v { keep_copy(self, @selector(accessibilityValueDescription), v); }
- (NSString *)accessibilityPlaceholderValue { return kept(self, @selector(accessibilityPlaceholderValue)); }
- (void)setAccessibilityPlaceholderValue:(NSString *)v { keep_copy(self, @selector(accessibilityPlaceholderValue), v); }
- (NSArray *)accessibilityChildrenInNavigationOrder { return kept(self, @selector(accessibilityChildrenInNavigationOrder)); }
- (void)setAccessibilityChildrenInNavigationOrder:(NSArray *)v { keep_copy(self, @selector(accessibilityChildrenInNavigationOrder), v); }
- (NSArray *)accessibilityVisibleChildren { return kept(self, @selector(accessibilityVisibleChildren)); }
- (void)setAccessibilityVisibleChildren:(NSArray *)v { keep_copy(self, @selector(accessibilityVisibleChildren), v); }
- (NSArray *)accessibilitySelectedChildren { return kept(self, @selector(accessibilitySelectedChildren)); }
- (void)setAccessibilitySelectedChildren:(NSArray *)v { keep_copy(self, @selector(accessibilitySelectedChildren), v); }
- (id )accessibilityTitleUIElement { return kept(self, @selector(accessibilityTitleUIElement)); }
- (void)setAccessibilityTitleUIElement:(id )v { keep(self, @selector(accessibilityTitleUIElement), v); }
- (NSArray *)accessibilityServesAsTitleForUIElements { return kept(self, @selector(accessibilityServesAsTitleForUIElements)); }
- (void)setAccessibilityServesAsTitleForUIElements:(NSArray *)v { keep_copy(self, @selector(accessibilityServesAsTitleForUIElements), v); }
- (NSArray *)accessibilityLinkedUIElements { return kept(self, @selector(accessibilityLinkedUIElements)); }
- (void)setAccessibilityLinkedUIElements:(NSArray *)v { keep_copy(self, @selector(accessibilityLinkedUIElements), v); }
- (NSArray *)accessibilitySharedFocusElements { return kept(self, @selector(accessibilitySharedFocusElements)); }
- (void)setAccessibilitySharedFocusElements:(NSArray *)v { keep_copy(self, @selector(accessibilitySharedFocusElements), v); }
- (NSURL *)accessibilityURL { return kept(self, @selector(accessibilityURL)); }
- (void)setAccessibilityURL:(NSURL *)v { keep_copy(self, @selector(accessibilityURL), v); }
- (NSString *)accessibilityFilename { return kept(self, @selector(accessibilityFilename)); }
- (void)setAccessibilityFilename:(NSString *)v { keep_copy(self, @selector(accessibilityFilename), v); }
- (id )accessibilityMinValue { return kept(self, @selector(accessibilityMinValue)); }
- (void)setAccessibilityMinValue:(id )v { keep(self, @selector(accessibilityMinValue), v); }
- (id )accessibilityMaxValue { return kept(self, @selector(accessibilityMaxValue)); }
- (void)setAccessibilityMaxValue:(id )v { keep(self, @selector(accessibilityMaxValue), v); }
- (NSArray *)accessibilityContents { return kept(self, @selector(accessibilityContents)); }
- (void)setAccessibilityContents:(NSArray *)v { keep_copy(self, @selector(accessibilityContents), v); }
- (id )accessibilityHeader { return kept(self, @selector(accessibilityHeader)); }
- (void)setAccessibilityHeader:(id )v { keep(self, @selector(accessibilityHeader), v); }
- (NSArray *)accessibilityTabs { return kept(self, @selector(accessibilityTabs)); }
- (void)setAccessibilityTabs:(NSArray *)v { keep_copy(self, @selector(accessibilityTabs), v); }
- (NSArray *)accessibilityRows { return kept(self, @selector(accessibilityRows)); }
- (void)setAccessibilityRows:(NSArray *)v { keep_copy(self, @selector(accessibilityRows), v); }
- (NSArray *)accessibilityColumns { return kept(self, @selector(accessibilityColumns)); }
- (void)setAccessibilityColumns:(NSArray *)v { keep_copy(self, @selector(accessibilityColumns), v); }
- (NSArray *)accessibilitySelectedRows { return kept(self, @selector(accessibilitySelectedRows)); }
- (void)setAccessibilitySelectedRows:(NSArray *)v { keep_copy(self, @selector(accessibilitySelectedRows), v); }
- (NSArray *)accessibilitySelectedColumns { return kept(self, @selector(accessibilitySelectedColumns)); }
- (void)setAccessibilitySelectedColumns:(NSArray *)v { keep_copy(self, @selector(accessibilitySelectedColumns), v); }
- (NSArray *)accessibilityVisibleRows { return kept(self, @selector(accessibilityVisibleRows)); }
- (void)setAccessibilityVisibleRows:(NSArray *)v { keep_copy(self, @selector(accessibilityVisibleRows), v); }
- (NSArray *)accessibilityVisibleColumns { return kept(self, @selector(accessibilityVisibleColumns)); }
- (void)setAccessibilityVisibleColumns:(NSArray *)v { keep_copy(self, @selector(accessibilityVisibleColumns), v); }
- (NSArray *)accessibilitySelectedCells { return kept(self, @selector(accessibilitySelectedCells)); }
- (void)setAccessibilitySelectedCells:(NSArray *)v { keep_copy(self, @selector(accessibilitySelectedCells), v); }
- (NSArray *)accessibilityColumnTitles { return kept(self, @selector(accessibilityColumnTitles)); }
- (void)setAccessibilityColumnTitles:(NSArray *)v { keep_copy(self, @selector(accessibilityColumnTitles), v); }
- (id )accessibilityMenuBar { return kept(self, @selector(accessibilityMenuBar)); }
- (void)setAccessibilityMenuBar:(id )v { keep(self, @selector(accessibilityMenuBar), v); }
- (id )accessibilityExtrasMenuBar { return kept(self, @selector(accessibilityExtrasMenuBar)); }
- (void)setAccessibilityExtrasMenuBar:(id )v { keep(self, @selector(accessibilityExtrasMenuBar), v); }
- (id )accessibilityApplicationFocusedUIElement { return kept(self, @selector(accessibilityApplicationFocusedUIElement)); }
- (void)setAccessibilityApplicationFocusedUIElement:(id )v { keep(self, @selector(accessibilityApplicationFocusedUIElement), v); }
- (id )accessibilityCloseButton { return kept(self, @selector(accessibilityCloseButton)); }
- (void)setAccessibilityCloseButton:(id )v { keep(self, @selector(accessibilityCloseButton), v); }
- (id )accessibilityZoomButton { return kept(self, @selector(accessibilityZoomButton)); }
- (void)setAccessibilityZoomButton:(id )v { keep(self, @selector(accessibilityZoomButton), v); }
- (id )accessibilityMinimizeButton { return kept(self, @selector(accessibilityMinimizeButton)); }
- (void)setAccessibilityMinimizeButton:(id )v { keep(self, @selector(accessibilityMinimizeButton), v); }
- (id )accessibilityToolbarButton { return kept(self, @selector(accessibilityToolbarButton)); }
- (void)setAccessibilityToolbarButton:(id )v { keep(self, @selector(accessibilityToolbarButton), v); }
- (id )accessibilityFullScreenButton { return kept(self, @selector(accessibilityFullScreenButton)); }
- (void)setAccessibilityFullScreenButton:(id )v { keep(self, @selector(accessibilityFullScreenButton), v); }
- (id )accessibilityDefaultButton { return kept(self, @selector(accessibilityDefaultButton)); }
- (void)setAccessibilityDefaultButton:(id )v { keep(self, @selector(accessibilityDefaultButton), v); }
- (id )accessibilityCancelButton { return kept(self, @selector(accessibilityCancelButton)); }
- (void)setAccessibilityCancelButton:(id )v { keep(self, @selector(accessibilityCancelButton), v); }
- (id )accessibilityClearButton { return kept(self, @selector(accessibilityClearButton)); }
- (void)setAccessibilityClearButton:(id )v { keep(self, @selector(accessibilityClearButton), v); }
- (id )accessibilitySearchButton { return kept(self, @selector(accessibilitySearchButton)); }
- (void)setAccessibilitySearchButton:(id )v { keep(self, @selector(accessibilitySearchButton), v); }
- (id )accessibilityProxy { return kept(self, @selector(accessibilityProxy)); }
- (void)setAccessibilityProxy:(id )v { keep(self, @selector(accessibilityProxy), v); }
- (id )accessibilityGrowArea { return kept(self, @selector(accessibilityGrowArea)); }
- (void)setAccessibilityGrowArea:(id )v { keep(self, @selector(accessibilityGrowArea), v); }
- (id )accessibilityOverflowButton { return kept(self, @selector(accessibilityOverflowButton)); }
- (void)setAccessibilityOverflowButton:(id )v { keep(self, @selector(accessibilityOverflowButton), v); }
- (id )accessibilityShownMenu { return kept(self, @selector(accessibilityShownMenu)); }
- (void)setAccessibilityShownMenu:(id )v { keep(self, @selector(accessibilityShownMenu), v); }
- (id )accessibilitySearchMenu { return kept(self, @selector(accessibilitySearchMenu)); }
- (void)setAccessibilitySearchMenu:(id )v { keep(self, @selector(accessibilitySearchMenu), v); }
- (NSString *)accessibilityDocument { return kept(self, @selector(accessibilityDocument)); }
- (void)setAccessibilityDocument:(NSString *)v { keep_copy(self, @selector(accessibilityDocument), v); }
- (NSString *)accessibilitySelectedText { return kept(self, @selector(accessibilitySelectedText)); }
- (void)setAccessibilitySelectedText:(NSString *)v { keep_copy(self, @selector(accessibilitySelectedText), v); }
- (NSArray *)accessibilityUserInputLabels { return kept(self, @selector(accessibilityUserInputLabels)); }
- (void)setAccessibilityUserInputLabels:(NSArray *)v { keep_copy(self, @selector(accessibilityUserInputLabels), v); }
- (NSArray *)accessibilityNextContents { return kept(self, @selector(accessibilityNextContents)); }
- (void)setAccessibilityNextContents:(NSArray *)v { keep_copy(self, @selector(accessibilityNextContents), v); }
- (NSArray *)accessibilityPreviousContents { return kept(self, @selector(accessibilityPreviousContents)); }
- (void)setAccessibilityPreviousContents:(NSArray *)v { keep_copy(self, @selector(accessibilityPreviousContents), v); }
- (BOOL)isAccessibilitySelected { return [kept(self, @selector(isAccessibilitySelected)) boolValue]; }
- (void)setAccessibilitySelected:(BOOL)v { keep(self, @selector(isAccessibilitySelected), @(v)); }
- (BOOL)isAccessibilityExpanded { return [kept(self, @selector(isAccessibilityExpanded)) boolValue]; }
- (void)setAccessibilityExpanded:(BOOL)v { keep(self, @selector(isAccessibilityExpanded), @(v)); }
- (BOOL)isAccessibilityEdited { return [kept(self, @selector(isAccessibilityEdited)) boolValue]; }
- (void)setAccessibilityEdited:(BOOL)v { keep(self, @selector(isAccessibilityEdited), @(v)); }
- (BOOL)isAccessibilityHidden { return [kept(self, @selector(isAccessibilityHidden)) boolValue]; }
- (void)setAccessibilityHidden:(BOOL)v { keep(self, @selector(isAccessibilityHidden), @(v)); }
- (BOOL)isAccessibilityModal { return [kept(self, @selector(isAccessibilityModal)) boolValue]; }
- (void)setAccessibilityModal:(BOOL)v { keep(self, @selector(isAccessibilityModal), @(v)); }
- (BOOL)isAccessibilityFrontmost { return [kept(self, @selector(isAccessibilityFrontmost)) boolValue]; }
- (void)setAccessibilityFrontmost:(BOOL)v { keep(self, @selector(isAccessibilityFrontmost), @(v)); }
- (BOOL)isAccessibilityDisclosed { return [kept(self, @selector(isAccessibilityDisclosed)) boolValue]; }
- (void)setAccessibilityDisclosed:(BOOL)v { keep(self, @selector(isAccessibilityDisclosed), @(v)); }
- (BOOL)isAccessibilityRequired { return [kept(self, @selector(isAccessibilityRequired)) boolValue]; }
- (void)setAccessibilityRequired:(BOOL)v { keep(self, @selector(isAccessibilityRequired), @(v)); }
- (BOOL)isAccessibilityProtectedContent { return [kept(self, @selector(isAccessibilityProtectedContent)) boolValue]; }
- (void)setAccessibilityProtectedContent:(BOOL)v { keep(self, @selector(isAccessibilityProtectedContent), @(v)); }
- (BOOL)isAccessibilityAlternateUIVisible { return [kept(self, @selector(isAccessibilityAlternateUIVisible)) boolValue]; }
- (void)setAccessibilityAlternateUIVisible:(BOOL)v { keep(self, @selector(isAccessibilityAlternateUIVisible), @(v)); }
- (BOOL)isAccessibilityOrderedByRow { return [kept(self, @selector(isAccessibilityOrderedByRow)) boolValue]; }
- (void)setAccessibilityOrderedByRow:(BOOL)v { keep(self, @selector(isAccessibilityOrderedByRow), @(v)); }
- (NSRect)accessibilityFrameInParentSpace { return [kept(self, @selector(accessibilityFrameInParentSpace)) rectValue]; }
- (void)setAccessibilityFrameInParentSpace:(NSRect)v { keep(self, @selector(accessibilityFrameInParentSpace), [NSValue valueWithRect:v]); }
- (NSPoint)accessibilityActivationPoint { return [kept(self, @selector(accessibilityActivationPoint)) pointValue]; }
- (void)setAccessibilityActivationPoint:(NSPoint)v { keep(self, @selector(accessibilityActivationPoint), [NSValue valueWithPoint:v]); }
- (NSAccessibilityOrientation)accessibilityOrientation { return [kept(self, @selector(accessibilityOrientation)) integerValue]; }
- (void)setAccessibilityOrientation:(NSAccessibilityOrientation)v { keep(self, @selector(accessibilityOrientation), @(v)); }
- (NSInteger)accessibilityIndex { return [kept(self, @selector(accessibilityIndex)) integerValue]; }
- (void)setAccessibilityIndex:(NSInteger)v { keep(self, @selector(accessibilityIndex), @(v)); }
- (NSInteger)accessibilityDisclosureLevel { return [kept(self, @selector(accessibilityDisclosureLevel)) integerValue]; }
- (void)setAccessibilityDisclosureLevel:(NSInteger)v { keep(self, @selector(accessibilityDisclosureLevel), @(v)); }
- (NSInteger)accessibilityNumberOfCharacters { return [kept(self, @selector(accessibilityNumberOfCharacters)) integerValue]; }
- (void)setAccessibilityNumberOfCharacters:(NSInteger)v { keep(self, @selector(accessibilityNumberOfCharacters), @(v)); }
- (NSInteger)accessibilityInsertionPointLineNumber { return [kept(self, @selector(accessibilityInsertionPointLineNumber)) integerValue]; }
- (void)setAccessibilityInsertionPointLineNumber:(NSInteger)v { keep(self, @selector(accessibilityInsertionPointLineNumber), @(v)); }
- (NSRange)accessibilitySelectedTextRange { return [kept(self, @selector(accessibilitySelectedTextRange)) rangeValue]; }
- (void)setAccessibilitySelectedTextRange:(NSRange)v { keep(self, @selector(accessibilitySelectedTextRange), [NSValue valueWithRange:v]); }
- (NSRange)accessibilityVisibleCharacterRange { return [kept(self, @selector(accessibilityVisibleCharacterRange)) rangeValue]; }
- (void)setAccessibilityVisibleCharacterRange:(NSRange)v { keep(self, @selector(accessibilityVisibleCharacterRange), [NSValue valueWithRange:v]); }

/* ---- what views, windows, cells, menus and the application know of themselves ---- */

static BOOL is_a(id o, const char *name)
{
    Class c = objc_getClass(name);
    return c && [o isKindOfClass:c];
}

/* the role a Mac gives each kind of control */
static NSAccessibilityRole role_of(id self)
{
    if (is_a(self, "NSWindow") || is_a(self, "NSPanel"))
        return NSAccessibilityWindowRole;
    if (is_a(self, "NSApplication"))
        return NSAccessibilityApplicationRole;
    if (is_a(self, "NSMenu"))
        return NSAccessibilityMenuRole;
    if (is_a(self, "NSMenuItem"))
        return NSAccessibilityMenuItemRole;
    static const struct {
        const char *cls;
        NSString *const *role;
    } roles[] = {
        {"NSPopUpButton", &NSAccessibilityPopUpButtonRole}, {"NSPopUpButtonCell", &NSAccessibilityPopUpButtonRole},
        {"NSComboBox", &NSAccessibilityComboBoxRole}, {"NSSearchField", &NSAccessibilityTextFieldRole},
        {"NSSecureTextField", &NSAccessibilityTextFieldRole}, {"NSColorWell", &NSAccessibilityColorWellRole},
        {"NSButton", &NSAccessibilityButtonRole}, {"NSButtonCell", &NSAccessibilityButtonRole},
        {"NSSlider", &NSAccessibilitySliderRole}, {"NSSliderCell", &NSAccessibilitySliderRole},
        {"NSLevelIndicator", &NSAccessibilityLevelIndicatorRole}, {"NSStepper", &NSAccessibilityIncrementorRole},
        {"NSImageView", &NSAccessibilityImageRole}, {"NSImageCell", &NSAccessibilityImageRole},
        {"NSProgressIndicator", &NSAccessibilityProgressIndicatorRole}, {"NSTextView", &NSAccessibilityTextAreaRole},
        {"NSOutlineView", &NSAccessibilityOutlineRole}, {"NSTableView", &NSAccessibilityTableRole},
        {"NSBrowser", &NSAccessibilityBrowserRole}, {"NSScroller", &NSAccessibilityScrollBarRole},
        {"NSScrollView", &NSAccessibilityScrollAreaRole}, {"NSTabView", &NSAccessibilityTabGroupRole},
        {"NSSplitView", &NSAccessibilitySplitGroupRole}, {"NSSegmentedControl", &NSAccessibilityRadioGroupRole},
        {"NSPathControl", &NSAccessibilityListRole}, {"NSRulerView", &NSAccessibilityRulerRole},
    };
    for (size_t i = 0; i < sizeof roles / sizeof roles[0]; i++)
        if (is_a(self, roles[i].cls)) {
            NSString *role = *roles[i].role;
            /* a checkbox or radio button is a button of another kind */
            if (role == NSAccessibilityButtonRole) {
                if ([self respondsToSelector:@selector(_buttonType)]) {
                    NSButtonType t = [(NSButton *)self _buttonType];
                    if (t == NSButtonTypeSwitch)
                        return NSAccessibilityCheckBoxRole;
                    if (t == NSButtonTypeRadio)
                        return NSAccessibilityRadioButtonRole;
                }
            }
            return role;
        }
    if (is_a(self, "NSTextField") || is_a(self, "NSTextFieldCell"))
        return [self respondsToSelector:@selector(isEditable)] && [self isEditable] ? NSAccessibilityTextFieldRole
                                                                                    : NSAccessibilityStaticTextRole;
    if (is_a(self, "NSView"))
        return NSAccessibilityGroupRole;
    return NSAccessibilityUnknownRole;
}

/* the parent before skipping ignored ones */
static id raw_parent(id self)
{
    if (is_a(self, "NSView")) {
        NSView *s = [(NSView *)self superview];
        return s ? (id)s : (id)[(NSView *)self window];
    }
    if (is_a(self, "NSWindow"))
        return NSApp;
    if (is_a(self, "NSMenuItem"))
        return [(NSMenuItem *)self menu];
    if (is_a(self, "NSCell"))
        return [(NSCell *)self controlView];
    return nil;
}

- (NSAccessibilityRole)accessibilityRole
{
    NSString *r = kept(self, @selector(accessibilityRole));
    return r ? r : role_of(self);
}
- (void)setAccessibilityRole:(NSAccessibilityRole)v { keep_copy(self, @selector(accessibilityRole), v); }

- (NSString *)accessibilityTitle
{
    NSString *t = kept(self, @selector(accessibilityTitle));
    if (t)
        return t;
    if ((is_a(self, "NSWindow") || is_a(self, "NSMenuItem") || is_a(self, "NSMenu") || is_a(self, "NSButton") ||
         is_a(self, "NSButtonCell")) && [self respondsToSelector:@selector(title)])
        return [(id)self title];
    return nil;
}
- (void)setAccessibilityTitle:(NSString *)v { keep_copy(self, @selector(accessibilityTitle), v); }

- (NSString *)accessibilityLabel
{
    NSString *l = kept(self, @selector(accessibilityLabel));
    if (l)
        return l;
    /* an image view says what its image shows */
    if (is_a(self, "NSImageView") && [self respondsToSelector:@selector(image)])
        return [[(NSImageView *)self image] accessibilityDescription];
    return nil;
}
- (void)setAccessibilityLabel:(NSString *)v { keep_copy(self, @selector(accessibilityLabel), v); }

- (NSString *)accessibilityHelp
{
    NSString *h = kept(self, @selector(accessibilityHelp));
    if (!h && [self respondsToSelector:@selector(toolTip)])
        h = [(id)self toolTip];
    return h;
}
- (void)setAccessibilityHelp:(NSString *)v { keep_copy(self, @selector(accessibilityHelp), v); }

- (NSString *)accessibilityIdentifier
{
    NSString *i = kept(self, @selector(accessibilityIdentifier));
    if (!i && (is_a(self, "NSView") || is_a(self, "NSMenuItem") || is_a(self, "NSWindow")) &&
        [self respondsToSelector:@selector(identifier)])
        i = [(id)self identifier];
    return i;
}
- (void)setAccessibilityIdentifier:(NSString *)v { keep_copy(self, @selector(accessibilityIdentifier), v); }

/* a parent and a window aren't retained, as on a Mac */
- (id)accessibilityParent
{
    id p = kept(self, @selector(accessibilityParent));
    return p ? p : NSAccessibilityUnignoredAncestor(raw_parent(self));
}
- (void)setAccessibilityParent:(id)v
{
    objc_setAssociatedObject(self, @selector(accessibilityParent), v, OBJC_ASSOCIATION_ASSIGN);
}

- (NSArray *)accessibilityChildren
{
    NSArray *c = kept(self, @selector(accessibilityChildren));
    if (c)
        return c;
    if (is_a(self, "NSView"))
        return NSAccessibilityUnignoredChildren([(NSView *)self subviews]);
    if (is_a(self, "NSWindow")) {
        NSView *content = [(NSWindow *)self contentView];
        return content ? NSAccessibilityUnignoredChildrenForOnlyChild(content) : @[];
    }
    if (is_a(self, "NSApplication"))
        return NSAccessibilityUnignoredChildren([(NSApplication *)self windows]);
    if (is_a(self, "NSMenu"))
        return [(NSMenu *)self itemArray];
    if (is_a(self, "NSMenuItem") && [(NSMenuItem *)self submenu])
        return @[ [(NSMenuItem *)self submenu] ];
    return nil;
}
- (void)setAccessibilityChildren:(NSArray *)v { keep_copy(self, @selector(accessibilityChildren), v); }

- (id)accessibilityWindow
{
    id w = kept(self, @selector(accessibilityWindow));
    if (w)
        return w;
    if (is_a(self, "NSView"))
        return [(NSView *)self window];
    if (is_a(self, "NSWindow"))
        return self;
    if (is_a(self, "NSCell"))
        return [[(NSCell *)self controlView] window];
    return nil;
}
- (void)setAccessibilityWindow:(id)v
{
    objc_setAssociatedObject(self, @selector(accessibilityWindow), v, OBJC_ASSOCIATION_ASSIGN);
}

- (id)accessibilityTopLevelUIElement
{
    id t = kept(self, @selector(accessibilityTopLevelUIElement));
    return t ? t : [self accessibilityWindow];
}
- (void)setAccessibilityTopLevelUIElement:(id)v
{
    objc_setAssociatedObject(self, @selector(accessibilityTopLevelUIElement), v, OBJC_ASSOCIATION_ASSIGN);
}

/* plain views and unknown things are left out; controls, windows and the rest are elements */
- (BOOL)isAccessibilityElement
{
    NSNumber *n = kept(self, @selector(isAccessibilityElement));
    if (n)
        return [n boolValue];
    NSString *role = [self accessibilityRole];
    return role && ![role isEqualToString:NSAccessibilityGroupRole] && ![role isEqualToString:NSAccessibilityUnknownRole];
}
- (void)setAccessibilityElement:(BOOL)v { keep(self, @selector(isAccessibilityElement), @(v)); }

- (BOOL)isAccessibilityEnabled
{
    NSNumber *n = kept(self, @selector(isAccessibilityEnabled));
    if (n)
        return [n boolValue];
    return [self respondsToSelector:@selector(isEnabled)] ? [(NSControl *)self isEnabled] : YES;
}
- (void)setAccessibilityEnabled:(BOOL)v { keep(self, @selector(isAccessibilityEnabled), @(v)); }

- (BOOL)isAccessibilityFocused
{
    NSNumber *n = kept(self, @selector(isAccessibilityFocused));
    if (n)
        return [n boolValue];
    if (is_a(self, "NSWindow"))
        return [(NSWindow *)self isKeyWindow];
    if (is_a(self, "NSView"))
        return [[(NSView *)self window] firstResponder] == (id)self;
    return NO;
}
- (void)setAccessibilityFocused:(BOOL)v { keep(self, @selector(isAccessibilityFocused), @(v)); }

- (BOOL)isAccessibilityMain
{
    NSNumber *n = kept(self, @selector(isAccessibilityMain));
    if (n)
        return [n boolValue];
    return is_a(self, "NSWindow") && [(NSWindow *)self isMainWindow];
}
- (void)setAccessibilityMain:(BOOL)v { keep(self, @selector(isAccessibilityMain), @(v)); }

- (BOOL)isAccessibilityMinimized
{
    NSNumber *n = kept(self, @selector(isAccessibilityMinimized));
    if (n)
        return [n boolValue];
    return is_a(self, "NSWindow") && [(NSWindow *)self isMiniaturized];
}
- (void)setAccessibilityMinimized:(BOOL)v { keep(self, @selector(isAccessibilityMinimized), @(v)); }

/* in screen coordinates */
- (NSRect)accessibilityFrame
{
    NSValue *f = kept(self, @selector(accessibilityFrame));
    if (f)
        return [f rectValue];
    if (is_a(self, "NSView")) {
        NSView *v = (NSView *)self;
        NSRect r = [v convertRect:[v bounds] toView:nil];
        return [v window] ? [[v window] convertRectToScreen:r] : r;
    }
    if (is_a(self, "NSWindow"))
        return [(NSWindow *)self frame];
    if (is_a(self, "NSCell")) {
        NSView *cv = [(NSCell *)self controlView];
        return cv ? [cv accessibilityFrame] : NSZeroRect;
    }
    return NSZeroRect;
}
- (void)setAccessibilityFrame:(NSRect)v { keep(self, @selector(accessibilityFrame), [NSValue valueWithRect:v]); }

- (NSArray *)accessibilityWindows
{
    NSArray *w = kept(self, @selector(accessibilityWindows));
    if (!w && is_a(self, "NSApplication"))
        w = [(NSApplication *)self windows];
    return w;
}
- (void)setAccessibilityWindows:(NSArray *)v { keep_copy(self, @selector(accessibilityWindows), v); }

- (id)accessibilityMainWindow
{
    id w = kept(self, @selector(accessibilityMainWindow));
    if (!w && is_a(self, "NSApplication"))
        w = [(NSApplication *)self mainWindow];
    return w;
}
- (void)setAccessibilityMainWindow:(id)v { keep(self, @selector(accessibilityMainWindow), v); }

- (id)accessibilityFocusedWindow
{
    id w = kept(self, @selector(accessibilityFocusedWindow));
    if (!w && is_a(self, "NSApplication"))
        w = [(NSApplication *)self keyWindow];
    return w;
}
- (void)setAccessibilityFocusedWindow:(id)v { keep(self, @selector(accessibilityFocusedWindow), v); }

- (id)accessibilityFocusedUIElement
{
    if (is_a(self, "NSApplication")) {
        NSWindow *key = [(NSApplication *)self keyWindow];
        id r = [key firstResponder];
        if ([r isKindOfClass:[NSView class]])
            return NSAccessibilityUnignoredAncestor(r);
        return key;
    }
    return NSAccessibilityUnignoredAncestor(self);
}

/* the deepest element at a point on the screen */
- (id)accessibilityHitTest:(NSPoint)point
{
    NSArray *children = [self accessibilityChildren];
    for (id child in [children reverseObjectEnumerator])
        if ([child respondsToSelector:@selector(accessibilityFrame)] && NSPointInRect(point, [child accessibilityFrame]))
            return [child accessibilityHitTest:point];
    return NSAccessibilityUnignoredAncestor(self);
}

- (BOOL)isAccessibilitySelectorAllowed:(SEL)selector { return YES; }

/* text: what a view holding a string can answer */
- (NSInteger)accessibilityLineForIndex:(NSInteger)index { return 0; }
- (NSRange)accessibilityRangeForLine:(NSInteger)line { return NSMakeRange(0, 0); }
- (NSString *)accessibilityStringForRange:(NSRange)range
{
    if (![self respondsToSelector:@selector(string)])
        return nil;
    NSString *s = [(NSTextView *)self string];
    return NSMaxRange(range) <= [s length] ? [s substringWithRange:range] : nil;
}
- (NSRect)accessibilityFrameForRange:(NSRange)range { return NSZeroRect; }
- (NSRange)accessibilityRangeForPosition:(NSPoint)point { return NSMakeRange(NSNotFound, 0); }
- (NSRange)accessibilityRangeForIndex:(NSInteger)index { return NSMakeRange((NSUInteger)index, 1); }
- (NSAttributedString *)accessibilityAttributedStringForRange:(NSRange)range
{
    NSString *s = [self accessibilityStringForRange:range];
    return s ? [[[NSAttributedString alloc] initWithString:s] autorelease] : nil;
}

/* pressing a control clicks it, raising a window brings it forward */
- (BOOL)accessibilityPerformPress
{
    if (is_a(self, "NSControl")) {
        [(NSControl *)self performClick:nil];
        return YES;
    }
    if (is_a(self, "NSMenuItem")) {
        NSMenuItem *item = (NSMenuItem *)self;
        if ([item isEnabled] && [item action])
            return [NSApp sendAction:[item action] to:[item target] from:item];
    }
    return NO;
}
- (BOOL)accessibilityPerformRaise
{
    if (is_a(self, "NSWindow")) {
        [(NSWindow *)self makeKeyAndOrderFront:nil];
        return YES;
    }
    return NO;
}
- (BOOL)accessibilityPerformIncrement { return NO; }
- (BOOL)accessibilityPerformDecrement { return NO; }
- (BOOL)accessibilityPerformConfirm { return NO; }
- (BOOL)accessibilityPerformPick { return NO; }
- (BOOL)accessibilityPerformCancel { return NO; }
- (BOOL)accessibilityPerformShowMenu { return NO; }
- (BOOL)accessibilityPerformDelete { return NO; }
- (BOOL)accessibilityPerformShowAlternateUI { return NO; }
- (BOOL)accessibilityPerformShowDefaultUI { return NO; }

/* the older API's actions, from the modern one */
- (NSArray *)accessibilityActionNames
{
    if (is_a(self, "NSControl") || is_a(self, "NSMenuItem"))
        return @[ NSAccessibilityPressAction ];
    if (is_a(self, "NSWindow"))
        return @[ NSAccessibilityRaiseAction ];
    return @[];
}
@end

/* ---- the older API, for every object ---- */

static const attribute_t *find_attribute(NSString *name)
{
    for (size_t i = 0; i < NATTRIBUTES; i++)
        if ([*attributes[i].name isEqualToString:name])
            return &attributes[i];
    return NULL;
}

/* through the method's own implementation, called with its real type, so that
 * a rectangle comes back as one */
static id read_attribute(id self, const attribute_t *a)
{
    SEL g = sel_getUid(a->getter);
    if (![self respondsToSelector:g])
        return nil;
    IMP imp = [self methodForSelector:g];
    switch (a->kind) {
    case K_OBJ: return ((id(*)(id, SEL))imp)(self, g);
    case K_BOOL: return @(((BOOL(*)(id, SEL))imp)(self, g));
    case K_INT: return @(((NSInteger(*)(id, SEL))imp)(self, g));
    case K_RECT: return [NSValue valueWithRect:((NSRect(*)(id, SEL))imp)(self, g)];
    case K_POINT: return [NSValue valueWithPoint:((NSPoint(*)(id, SEL))imp)(self, g)];
    case K_RANGE: return [NSValue valueWithRange:((NSRange(*)(id, SEL))imp)(self, g)];
    case K_POSITION: return [NSValue valueWithPoint:((NSRect(*)(id, SEL))imp)(self, g).origin];
    case K_SIZE: return [NSValue valueWithSize:((NSRect(*)(id, SEL))imp)(self, g).size];
    case K_ORIENT:
        switch (((NSInteger(*)(id, SEL))imp)(self, g)) {
        case NSAccessibilityOrientationVertical: return NSAccessibilityVerticalOrientationValue;
        case NSAccessibilityOrientationHorizontal: return NSAccessibilityHorizontalOrientationValue;
        default: return NSAccessibilityUnknownOrientationValue;
        }
    }
    return nil;
}

static BOOL write_attribute(id self, const attribute_t *a, id value)
{
    if (!a->setter)
        return NO;
    SEL s = sel_getUid(a->setter);
    if (![self respondsToSelector:s])
        return NO;
    IMP imp = [self methodForSelector:s];
    switch (a->kind) {
    case K_OBJ: ((void (*)(id, SEL, id))imp)(self, s, value); break;
    case K_BOOL: ((void (*)(id, SEL, BOOL))imp)(self, s, [value boolValue]); break;
    case K_INT: ((void (*)(id, SEL, NSInteger))imp)(self, s, [value integerValue]); break;
    case K_RECT: ((void (*)(id, SEL, NSRect))imp)(self, s, [value rectValue]); break;
    case K_POINT: ((void (*)(id, SEL, NSPoint))imp)(self, s, [value pointValue]); break;
    case K_RANGE: ((void (*)(id, SEL, NSRange))imp)(self, s, [value rangeValue]); break;
    default: return NO;
    }
    return YES;
}

static char overrides_key;

@implementation NSObject (NSAccessibility)
- (NSArray *)accessibilityAttributeNames
{
    NSMutableArray *names = [NSMutableArray array];
    NSDictionary *overrides = objc_getAssociatedObject(self, &overrides_key);
    for (size_t i = 0; i < NATTRIBUTES; i++) {
        NSString *name = *attributes[i].name;
        id v = overrides[name] ? overrides[name] : read_attribute(self, &attributes[i]);
        /* the attributes with something to say, and where it is */
        BOOL always = name == NSAccessibilityRoleAttribute || name == NSAccessibilityRoleDescriptionAttribute ||
                      name == NSAccessibilityPositionAttribute || name == NSAccessibilitySizeAttribute ||
                      name == NSAccessibilityEnabledAttribute || name == NSAccessibilityFocusedAttribute;
        if ((always && v) || (attributes[i].kind == K_OBJ && v && ![names containsObject:name]))
            [names addObject:name];
    }
    for (NSString *name in overrides)
        if (![names containsObject:name])
            [names addObject:name];
    return names;
}

- (id)accessibilityAttributeValue:(NSAccessibilityAttributeName)attribute
{
    id o = [objc_getAssociatedObject(self, &overrides_key) objectForKey:attribute];
    if (o)
        return o;
    if ([attribute isEqualToString:NSAccessibilityRoleDescriptionAttribute] &&
        ![self respondsToSelector:@selector(accessibilityRoleDescription)])
        return nil;
    if ([attribute isEqualToString:NSAccessibilityRoleDescriptionAttribute] &&
        ![(id<NSAccessibility>)self accessibilityRoleDescription])
        return NSAccessibilityRoleDescriptionForUIElement(self);
    const attribute_t *a = find_attribute(attribute);
    return a ? read_attribute(self, a) : nil;
}

- (BOOL)accessibilityIsAttributeSettable:(NSAccessibilityAttributeName)attribute
{
    static NSString *const *settable[] = {&NSAccessibilityValueAttribute, &NSAccessibilityFocusedAttribute,
                                          &NSAccessibilitySelectedAttribute, &NSAccessibilityExpandedAttribute,
                                          &NSAccessibilityDisclosingAttribute, &NSAccessibilitySelectedTextAttribute,
                                          &NSAccessibilitySelectedTextRangeAttribute,
                                          &NSAccessibilityMinimizedAttribute, &NSAccessibilityMainAttribute};
    const attribute_t *a = find_attribute(attribute);
    if (!a || !a->setter || ![self respondsToSelector:sel_getUid(a->setter)])
        return NO;
    for (size_t i = 0; i < sizeof settable / sizeof settable[0]; i++)
        if ([*settable[i] isEqualToString:attribute])
            return YES;
    return NO;
}

- (void)accessibilitySetValue:(id)value forAttribute:(NSAccessibilityAttributeName)attribute
{
    const attribute_t *a = find_attribute(attribute);
    if (a)
        write_attribute(self, a, value);
}

- (NSArray *)accessibilityParameterizedAttributeNames { return @[]; }

- (id)accessibilityAttributeValue:(NSAccessibilityParameterizedAttributeName)attribute forParameter:(id)parameter
{
    id<NSAccessibility> me = (id)self;
    if ([attribute isEqualToString:NSAccessibilityStringForRangeParameterizedAttribute] &&
        [self respondsToSelector:@selector(accessibilityStringForRange:)])
        return [me accessibilityStringForRange:[parameter rangeValue]];
    if ([attribute isEqualToString:NSAccessibilityLineForIndexParameterizedAttribute] &&
        [self respondsToSelector:@selector(accessibilityLineForIndex:)])
        return @([me accessibilityLineForIndex:[parameter integerValue]]);
    if ([attribute isEqualToString:NSAccessibilityRangeForLineParameterizedAttribute] &&
        [self respondsToSelector:@selector(accessibilityRangeForLine:)])
        return [NSValue valueWithRange:[me accessibilityRangeForLine:[parameter integerValue]]];
    if ([attribute isEqualToString:NSAccessibilityBoundsForRangeParameterizedAttribute] &&
        [self respondsToSelector:@selector(accessibilityFrameForRange:)])
        return [NSValue valueWithRect:[me accessibilityFrameForRange:[parameter rangeValue]]];
    return nil;
}

- (NSArray *)accessibilityActionNames { return @[]; }
- (NSString *)accessibilityActionDescription:(NSAccessibilityActionName)action
{
    return NSAccessibilityActionDescription(action);
}

- (void)accessibilityPerformAction:(NSAccessibilityActionName)action
{
    if (![action hasPrefix:@"AX"])
        return;
    SEL s = sel_getUid([[@"accessibilityPerform" stringByAppendingString:[action substringFromIndex:2]] UTF8String]);
    if ([self respondsToSelector:s])
        ((BOOL(*)(id, SEL))objc_msgSend)(self, s);
}

- (BOOL)accessibilityIsIgnored
{
    if ([self respondsToSelector:@selector(isAccessibilityElement)])
        return ![(id<NSAccessibility>)self isAccessibilityElement];
    return YES;
}

- (id)accessibilityHitTest:(NSPoint)point { return self; }
- (id)accessibilityFocusedUIElement { return self; }

- (NSUInteger)accessibilityIndexOfChild:(id)child
{
    NSArray *children = [self accessibilityAttributeValue:NSAccessibilityChildrenAttribute];
    return children ? [children indexOfObjectIdenticalTo:child] : NSNotFound;
}

- (NSUInteger)accessibilityArrayAttributeCount:(NSAccessibilityAttributeName)attribute
{
    id v = [self accessibilityAttributeValue:attribute];
    return [v isKindOfClass:[NSArray class]] ? [v count] : 0;
}

- (NSArray *)accessibilityArrayAttributeValues:(NSAccessibilityAttributeName)attribute index:(NSUInteger)index
                                      maxCount:(NSUInteger)maxCount
{
    NSArray *v = [self accessibilityAttributeValue:attribute];
    if (![v isKindOfClass:[NSArray class]] || index >= [v count])
        return @[];
    return [v subarrayWithRange:NSMakeRange(index, MIN(maxCount, [v count] - index))];
}

- (BOOL)accessibilityNotifiesWhenDestroyed { return NO; }

- (BOOL)accessibilitySetOverrideValue:(id)value forAttribute:(NSAccessibilityAttributeName)attribute
{
    NSMutableDictionary *d = objc_getAssociatedObject(self, &overrides_key);
    if (!d) {
        d = [NSMutableDictionary dictionary];
        objc_setAssociatedObject(self, &overrides_key, d, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (value)
        d[attribute] = value;
    else
        [d removeObjectForKey:attribute];
    return YES;
}
@end

/* ---- an element of the app's own ---- */

/* the protocol's other methods are AAccessibility's, added at load */
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wprotocol"
#pragma clang diagnostic ignored "-Wobjc-protocol-property-synthesis"
@implementation NSAccessibilityElement
+ (instancetype)accessibilityElementWithRole:(NSAccessibilityRole)role frame:(NSRect)frame
                                       label:(NSString *)label parent:(id)parent
{
    NSAccessibilityElement *e = [[[self alloc] init] autorelease];
    [e setAccessibilityRole:role];
    [e setAccessibilityFrame:frame];
    [e setAccessibilityLabel:label];
    [e setAccessibilityParent:parent];
    return e;
}

- (void)accessibilityAddChildElement:(NSAccessibilityElement *)child
{
    NSArray *now = [self accessibilityChildren];
    [self setAccessibilityChildren:now ? [now arrayByAddingObject:child] : @[ child ]];
    [child setAccessibilityParent:self];
}

/* one of the app's own is an element unless it says otherwise */
- (BOOL)isAccessibilityElement
{
    NSNumber *n = kept(self, @selector(isAccessibilityElement));
    return n ? [n boolValue] : YES;
}

- (NSAccessibilityRole)accessibilityRole { return kept(self, @selector(accessibilityRole)); }

/* a frame in its parent's space follows the parent */
- (NSRect)accessibilityFrame
{
    NSValue *inParent = kept(self, @selector(accessibilityFrameInParentSpace));
    if (inParent) {
        NSRect r = [inParent rectValue];
        id parent = [self accessibilityParent];
        if ([parent respondsToSelector:@selector(accessibilityFrame)]) {
            NSRect p = [parent accessibilityFrame];
            r.origin.x += p.origin.x, r.origin.y += p.origin.y;
        }
        return r;
    }
    NSValue *f = kept(self, @selector(accessibilityFrame));
    return f ? [f rectValue] : NSZeroRect;
}

- (id)accessibilityParent { return kept(self, @selector(accessibilityParent)); }
- (NSArray *)accessibilityChildren { return kept(self, @selector(accessibilityChildren)); }
@end
#pragma clang diagnostic pop

/* ---- the functions ---- */

id NSAccessibilityUnignoredAncestor(id element)
{
    while (element && [element accessibilityIsIgnored])
        element = [element accessibilityAttributeValue:NSAccessibilityParentAttribute];
    return element;
}

id NSAccessibilityUnignoredDescendant(id element)
{
    if (!element || ![element accessibilityIsIgnored])
        return element;
    for (id child in [element accessibilityAttributeValue:NSAccessibilityChildrenAttribute]) {
        id found = NSAccessibilityUnignoredDescendant(child);
        if (found)
            return found;
    }
    return nil;
}

static void add_unignored(NSMutableArray *out, id element)
{
    if (![element accessibilityIsIgnored]) {
        [out addObject:element];
        return;
    }
    /* an ignored element stands aside for its children */
    NSArray *children;
    if ([element isKindOfClass:[NSView class]])
        children = [(NSView *)element subviews];
    else if ([element isKindOfClass:[NSWindow class]])
        children = [(NSWindow *)element contentView] ? @[ [(NSWindow *)element contentView] ] : @[];
    else
        children = [element accessibilityAttributeValue:NSAccessibilityChildrenAttribute];
    for (id child in children)
        add_unignored(out, child);
}

NSArray *NSAccessibilityUnignoredChildren(NSArray *originalChildren)
{
    NSMutableArray *out = [NSMutableArray array];
    for (id child in originalChildren)
        add_unignored(out, child);
    return out;
}

NSArray *NSAccessibilityUnignoredChildrenForOnlyChild(id originalChild)
{
    return originalChild ? NSAccessibilityUnignoredChildren(@[ originalChild ]) : @[];
}

/* "AXPopUpButton" is "pop up button"; a run of capitals, as in "UI", stays as it is */
static NSString *words_of(NSString *name)
{
    if ([name hasPrefix:@"AX"])
        name = [name substringFromIndex:2];
    NSMutableArray *words = [NSMutableArray array];
    NSUInteger n = [name length], start = 0;
    for (NSUInteger i = 1; i <= n; i++) {
        BOOL split = i == n;
        if (!split) {
            unichar p = [name characterAtIndex:i - 1], c = [name characterAtIndex:i];
            unichar next = i + 1 < n ? [name characterAtIndex:i + 1] : 0;
            BOOL pu = p >= 'A' && p <= 'Z', cu = c >= 'A' && c <= 'Z', nl = next >= 'a' && next <= 'z';
            split = cu && (!pu || nl);
        }
        if (split) {
            NSString *w = [name substringWithRange:NSMakeRange(start, i - start)];
            [words addObject:[w length] > 1 && [w isEqualToString:[w uppercaseString]] ? w : [w lowercaseString]];
            start = i;
        }
    }
    return [words componentsJoinedByString:@" "];
}

NSString *NSAccessibilityRoleDescription(NSAccessibilityRole role, NSAccessibilitySubrole subrole)
{
    static const struct {
        NSString *const *name;
        NSString *words;
    } special[] = {
        {&NSAccessibilityCheckBoxRole, @"checkbox"}, {&NSAccessibilityStaticTextRole, @"text"},
        {&NSAccessibilityTextAreaRole, @"text entry area"}, {&NSAccessibilityIncrementorRole, @"stepper"},
        {&NSAccessibilitySearchFieldSubrole, @"search text field"}, {&NSAccessibilityToggleSubrole, @"toggle button"},
        {&NSAccessibilitySystemWideRole, @"system wide"}, {&NSAccessibilityUnknownRole, @"unknown"},
    };
    NSString *names[2] = {subrole, role};
    for (int k = 0; k < 2; k++) {
        NSString *name = names[k];
        if (!name || (k == 0 && [name isEqualToString:NSAccessibilityUnknownSubrole]))
            continue;
        for (size_t i = 0; i < sizeof special / sizeof special[0]; i++)
            if ([*special[i].name isEqualToString:name])
                return special[i].words;
        if ([name hasPrefix:@"AX"])
            return words_of(name);
    }
    return nil;
}

NSString *NSAccessibilityRoleDescriptionForUIElement(id element)
{
    NSString *role = nil, *subrole = nil;
    if ([element respondsToSelector:@selector(accessibilityRole)]) {
        role = [element accessibilityRole];
        subrole = [element accessibilitySubrole];
    } else {
        role = [element accessibilityAttributeValue:NSAccessibilityRoleAttribute];
        subrole = [element accessibilityAttributeValue:NSAccessibilitySubroleAttribute];
    }
    return NSAccessibilityRoleDescription(role, subrole);
}

NSString *NSAccessibilityActionDescription(NSAccessibilityActionName action)
{
    if ([action isEqualToString:NSAccessibilityPickAction])
        return @"select";
    if ([action isEqualToString:NSAccessibilityShowAlternateUIAction])
        return @"show alternate UI";
    if ([action isEqualToString:NSAccessibilityShowDefaultUIAction])
        return @"show default UI";
    static NSString *const *known[] = {&NSAccessibilityPressAction, &NSAccessibilityIncrementAction,
                                       &NSAccessibilityDecrementAction, &NSAccessibilityConfirmAction,
                                       &NSAccessibilityCancelAction, &NSAccessibilityRaiseAction,
                                       &NSAccessibilityShowMenuAction, &NSAccessibilityDeleteAction};
    for (size_t i = 0; i < sizeof known / sizeof known[0]; i++)
        if ([*known[i] isEqualToString:action])
            return words_of(action);
    return nil;
}

/* nobody to tell */
void NSAccessibilityPostNotification(id element, NSAccessibilityNotificationName notification) {}
void NSAccessibilityPostNotificationWithUserInfo(id element, NSAccessibilityNotificationName notification,
                                                 NSDictionary *userInfo)
{
}

NSRect NSAccessibilityFrameInView(NSView *view, NSRect frame)
{
    NSRect r = [view convertRect:frame toView:nil];
    return [view window] ? [[view window] convertRectToScreen:r] : r;
}

NSPoint NSAccessibilityPointInView(NSView *view, NSPoint point)
{
    return NSAccessibilityFrameInView(view, NSMakeRect(point.x, point.y, 0, 0)).origin;
}

BOOL NSAccessibilitySetMayContainProtectedContent(BOOL flag) { return YES; }

void NSAccessibilityRaiseBadArgumentException(id element, NSString *attribute, id value)
{
    [NSException raise:NSAccessibilityException format:@"%@ can't take %@ for %@", element, value, attribute];
}

