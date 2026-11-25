/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's WebKit: the older web view of macOS (WebView, the "legacy" WebKit
 * that MacDown and Sequel Pro use), its frames, data sources, preferences,
 * delegates and script objects, written from Apple's public documentation.
 * Imported by WebKit.h. Ferry builds it on the same WebKitGTK view as
 * WKWebView. */
#ifndef _FERRY_WEBKIT_WEBVIEW_H_
#define _FERRY_WEBKIT_WEBVIEW_H_
#import <AppKit/AppKit.h>

#ifndef WEBKIT_EXTERN
#define WEBKIT_EXTERN extern
#endif

@class WebView, WebFrame, WebDataSource, WebPreferences, WebScriptObject;
@class WebFrameView, DOMDocument, DOMHTMLElement;   /* WebFrameView.h, DOM.h (freemac 1.217, Ferry 0.42.0) */
@class DOMRange, JSContext;   /* DOM.h, JavaScriptCore (freemac 1.225) */

/* ---- preferences -------------------------------------------------------------------- */

typedef NS_ENUM(NSUInteger, WebCacheModel) {
    WebCacheModelDocumentViewer = 0,
    WebCacheModelDocumentBrowser = 1,
    WebCacheModelPrimaryWebBrowser = 2,
};
WEBKIT_EXTERN NSString *const WebPreferencesChangedNotification;

@interface WebPreferences : NSObject <NSCoding>
+ (WebPreferences *)standardPreferences;
- (instancetype)initWithIdentifier:(NSString *)identifier;
@property (readonly, copy) NSString *identifier;
@property (copy) NSString *standardFontFamily;
@property (copy) NSString *fixedFontFamily;
@property (copy) NSString *serifFontFamily;
@property (copy) NSString *sansSerifFontFamily;
@property (copy) NSString *cursiveFontFamily;
@property (copy) NSString *fantasyFontFamily;
@property int defaultFontSize;
@property int defaultFixedFontSize;
@property int minimumFontSize;
@property int minimumLogicalFontSize;
@property (copy) NSString *defaultTextEncodingName;
@property BOOL userStyleSheetEnabled;
@property (retain) NSURL *userStyleSheetLocation;
@property (getter=isJavaEnabled) BOOL javaEnabled;
@property (getter=isJavaScriptEnabled) BOOL javaScriptEnabled;
@property BOOL javaScriptCanOpenWindowsAutomatically;
@property BOOL plugInsEnabled;
@property BOOL allowsAnimatedImages;
@property BOOL allowsAnimatedImageLooping;
@property BOOL loadsImagesAutomatically;
@property BOOL autosaves;
@property BOOL shouldPrintBackgrounds;
@property BOOL privateBrowsingEnabled;
@property BOOL tabsToLinks;
@property BOOL usesPageCache;
@property WebCacheModel cacheModel;
@end

/* ---- script objects ----------------------------------------------------------------- */

/* JavaScript's undefined, as an object */
@interface WebUndefined : NSObject <NSCoding, NSCopying>
+ (WebUndefined *)undefined;
@end

/* A JavaScript object of a page, reached from Objective-C */
@interface WebScriptObject : NSObject
+ (BOOL)throwException:(NSString *)exceptionMessage;
- (id)callWebScriptMethod:(NSString *)name withArguments:(NSArray *)arguments;
- (id)evaluateWebScript:(NSString *)script;
- (void)removeWebScriptKey:(NSString *)name;
- (NSString *)stringRepresentation;
- (id)webScriptValueAtIndex:(unsigned)index;
- (void)setWebScriptValueAtIndex:(unsigned)index value:(id)value;
- (void)setException:(NSString *)description;
@end

/* ---- frames and their data ---------------------------------------------------------- */

@interface WebDataSource : NSObject
- (instancetype)initWithRequest:(NSURLRequest *)request;
@property (readonly, retain) NSData *data;
@property (readonly, retain) id representation;
@property (readonly) WebFrame *webFrame;
@property (readonly, retain) NSURLRequest *initialRequest;
@property (readonly, retain) NSMutableURLRequest *request;
@property (readonly, retain) NSURLResponse *response;
@property (readonly, copy) NSString *textEncodingName;
@property (readonly, getter=isLoading) BOOL loading;
@property (readonly, copy) NSString *pageTitle;
@property (readonly) NSURL *unreachableURL;
@end

@interface WebFrame : NSObject
@property (readonly, copy) NSString *name;
@property (readonly) WebView *webView;
@property (readonly) WebDataSource *dataSource;
@property (readonly) WebDataSource *provisionalDataSource;
@property (readonly) WebFrame *parentFrame;
@property (readonly, copy) NSArray *childFrames;
@property (readonly) WebScriptObject *windowObject;
@property (readonly) DOMDocument *DOMDocument;
@property (readonly) DOMHTMLElement *frameElement;
@property (readonly) WebFrameView *frameView;
- (void)loadRequest:(NSURLRequest *)request;
- (void)loadData:(NSData *)data MIMEType:(NSString *)MIMEType textEncodingName:(NSString *)encodingName
         baseURL:(NSURL *)URL;
- (void)loadHTMLString:(NSString *)string baseURL:(NSURL *)URL;
- (void)loadAlternateHTMLString:(NSString *)string baseURL:(NSURL *)baseURL forUnreachableURL:(NSURL *)unreachableURL;
- (void)stopLoading;
- (void)reload;
- (void)reloadFromOrigin;
- (WebFrame *)findFrameNamed:(NSString *)name;
@end
@interface WebFrame (FerryJavaScriptContext)
/* a JavaScriptCore context whose scripts run in the frame's page; what
 * they give back comes as a copy, as JSON carries it (freemac 1.225) */
@property (readonly) JSContext *javaScriptContext;
@end

/* ---- the delegates ------------------------------------------------------------------ */

typedef NS_ENUM(NSInteger, WebNavigationType) {
    WebNavigationTypeLinkClicked,
    WebNavigationTypeFormSubmitted,
    WebNavigationTypeBackForward,
    WebNavigationTypeReload,
    WebNavigationTypeFormResubmitted,
    WebNavigationTypeOther,
};
WEBKIT_EXTERN NSString *const WebActionNavigationTypeKey;
WEBKIT_EXTERN NSString *const WebActionElementKey;
WEBKIT_EXTERN NSString *const WebActionButtonKey;
WEBKIT_EXTERN NSString *const WebActionModifierFlagsKey;
WEBKIT_EXTERN NSString *const WebActionOriginalURLKey;

@protocol WebPolicyDecisionListener <NSObject>
- (void)use;
- (void)download;
- (void)ignore;
@end

@protocol WebPolicyDelegate <NSObject>
@optional
- (void)webView:(WebView *)webView decidePolicyForNavigationAction:(NSDictionary *)actionInformation
                                                           request:(NSURLRequest *)request
                                                             frame:(WebFrame *)frame
                                                  decisionListener:(id<WebPolicyDecisionListener>)listener;
- (void)webView:(WebView *)webView decidePolicyForNewWindowAction:(NSDictionary *)actionInformation
                                                          request:(NSURLRequest *)request
                                                     newFrameName:(NSString *)frameName
                                                 decisionListener:(id<WebPolicyDecisionListener>)listener;
- (void)webView:(WebView *)webView decidePolicyForMIMEType:(NSString *)type
                                                   request:(NSURLRequest *)request
                                                     frame:(WebFrame *)frame
                                          decisionListener:(id<WebPolicyDecisionListener>)listener;
- (void)webView:(WebView *)webView unableToImplementPolicyWithError:(NSError *)error frame:(WebFrame *)frame;
@end

@protocol WebFrameLoadDelegate <NSObject>
@optional
- (void)webView:(WebView *)sender didStartProvisionalLoadForFrame:(WebFrame *)frame;
- (void)webView:(WebView *)sender didReceiveServerRedirectForProvisionalLoadForFrame:(WebFrame *)frame;
- (void)webView:(WebView *)sender didFailProvisionalLoadWithError:(NSError *)error forFrame:(WebFrame *)frame;
- (void)webView:(WebView *)sender didCommitLoadForFrame:(WebFrame *)frame;
- (void)webView:(WebView *)sender didReceiveTitle:(NSString *)title forFrame:(WebFrame *)frame;
- (void)webView:(WebView *)sender didFinishLoadForFrame:(WebFrame *)frame;
- (void)webView:(WebView *)sender didFailLoadWithError:(NSError *)error forFrame:(WebFrame *)frame;
- (void)webView:(WebView *)webView didClearWindowObject:(WebScriptObject *)windowObject forFrame:(WebFrame *)frame;
- (void)webView:(WebView *)webView windowScriptObjectAvailable:(WebScriptObject *)windowScriptObject;
@end

/* The tags of the items of a web view's context menu, as WebUIDelegate's
 * contextMenuItemsForElement: sees them (freemac 1.223, Ferry 0.47.0).
 * Ferry's web view makes its own menu, so the delegate isn't asked. */
enum {
    WebMenuItemTagOpenLinkInNewWindow = 1,
    WebMenuItemTagDownloadLinkToDisk,
    WebMenuItemTagCopyLinkToClipboard,
    WebMenuItemTagOpenImageInNewWindow,
    WebMenuItemTagDownloadImageToDisk,
    WebMenuItemTagCopyImageToClipboard,
    WebMenuItemTagOpenFrameInNewWindow,
    WebMenuItemTagCopy,
    WebMenuItemTagGoBack,
    WebMenuItemTagGoForward,
    WebMenuItemTagStop,
    WebMenuItemTagReload,
    WebMenuItemTagCut,
    WebMenuItemTagPaste,
    WebMenuItemTagSpellingGuess,
    WebMenuItemTagNoGuessesFound,
    WebMenuItemTagIgnoreSpelling,
    WebMenuItemTagLearnSpelling,
    WebMenuItemTagOther,
    WebMenuItemTagSearchInSpotlight,
    WebMenuItemTagSearchWeb,
    WebMenuItemTagLookUpInDictionary,
    WebMenuItemTagOpenWithDefaultApplication,
    WebMenuItemPDFActualSize,
    WebMenuItemPDFZoomIn,
    WebMenuItemPDFZoomOut,
    WebMenuItemPDFAutoSize,
    WebMenuItemPDFSinglePage,
    WebMenuItemPDFFacingPages,
    WebMenuItemPDFContinuous,
    WebMenuItemPDFNextPage,
    WebMenuItemPDFPreviousPage,
    WebMenuItemTagOpenLink = 2000,
    WebMenuItemTagIgnoreGrammar,
    WebMenuItemTagSpellingMenu,
    WebMenuItemTagShowSpellingPanel,
    WebMenuItemTagCheckSpelling,
    WebMenuItemTagCheckSpellingWhileTyping,
    WebMenuItemTagCheckGrammarWithSpelling,
    WebMenuItemTagFontMenu,
    WebMenuItemTagShowFonts,
    WebMenuItemTagBold,
    WebMenuItemTagItalic,
    WebMenuItemTagUnderline,
    WebMenuItemTagOutline,
    WebMenuItemTagStyles,
    WebMenuItemTagShowColors,
    WebMenuItemTagSpeechMenu,
    WebMenuItemTagStartSpeaking,
    WebMenuItemTagStopSpeaking,
    WebMenuItemTagWritingDirectionMenu,
    WebMenuItemTagDefaultDirection,
    WebMenuItemTagLeftToRight,
    WebMenuItemTagRightToLeft,
    WebMenuItemTagPDFSinglePageScrolling,
    WebMenuItemTagPDFFacingPagesScrolling,
    WebMenuItemTagInspectElement,
};

@protocol WebUIDelegate <NSObject>
@optional
- (NSArray *)webView:(WebView *)sender
    contextMenuItemsForElement:(NSDictionary *)element
              defaultMenuItems:(NSArray *)defaultMenuItems;
- (WebView *)webView:(WebView *)sender createWebViewWithRequest:(NSURLRequest *)request;
- (void)webViewShow:(WebView *)sender;
- (void)webViewClose:(WebView *)sender;
- (void)webView:(WebView *)sender runJavaScriptAlertPanelWithMessage:(NSString *)message;
- (void)webView:(WebView *)sender runJavaScriptAlertPanelWithMessage:(NSString *)message
    initiatedByFrame:(WebFrame *)frame;
- (BOOL)webView:(WebView *)sender runJavaScriptConfirmPanelWithMessage:(NSString *)message;
- (BOOL)webView:(WebView *)sender runJavaScriptConfirmPanelWithMessage:(NSString *)message
    initiatedByFrame:(WebFrame *)frame;
- (NSString *)webView:(WebView *)sender runJavaScriptTextInputPanelWithPrompt:(NSString *)prompt
          defaultText:(NSString *)defaultText;
- (NSString *)webView:(WebView *)sender runJavaScriptTextInputPanelWithPrompt:(NSString *)prompt
          defaultText:(NSString *)defaultText
     initiatedByFrame:(WebFrame *)frame;
@end

/* the editing delegate and dragging (freemac 1.225, Ferry 0.49.0) */
typedef NS_OPTIONS(NSUInteger, WebDragDestinationAction) {
    WebDragDestinationActionNone = 0,
    WebDragDestinationActionDHTML = 1,
    WebDragDestinationActionEdit = 2,
    WebDragDestinationActionLoad = 4,
    WebDragDestinationActionAny = NSUIntegerMax,
};
typedef NS_OPTIONS(NSUInteger, WebDragSourceAction) {
    WebDragSourceActionNone = 0,
    WebDragSourceActionDHTML = 1,
    WebDragSourceActionImage = 2,
    WebDragSourceActionLink = 4,
    WebDragSourceActionSelection = 8,
    WebDragSourceActionAny = NSUIntegerMax,
};
typedef NS_ENUM(NSInteger, WebViewInsertAction) {
    WebViewInsertActionTyped,
    WebViewInsertActionPasted,
    WebViewInsertActionDropped,
};
WEBKIT_EXTERN NSString *const WebViewDidBeginEditingNotification;
WEBKIT_EXTERN NSString *const WebViewDidChangeNotification;
WEBKIT_EXTERN NSString *const WebViewDidEndEditingNotification;
WEBKIT_EXTERN NSString *const WebViewDidChangeSelectionNotification;

@protocol WebEditingDelegate <NSObject>
@optional
- (BOOL)webView:(WebView *)webView shouldBeginEditingInDOMRange:(DOMRange *)range;
- (BOOL)webView:(WebView *)webView shouldEndEditingInDOMRange:(DOMRange *)range;
- (BOOL)webView:(WebView *)webView shouldInsertText:(NSString *)text replacingDOMRange:(DOMRange *)range
    givenAction:(WebViewInsertAction)action;
- (BOOL)webView:(WebView *)webView shouldChangeSelectedDOMRange:(DOMRange *)currentRange
              toDOMRange:(DOMRange *)proposedRange
                affinity:(NSSelectionAffinity)selectionAffinity
          stillSelecting:(BOOL)flag;
- (BOOL)webView:(WebView *)webView doCommandBySelector:(SEL)selector;
- (void)webViewDidBeginEditing:(NSNotification *)notification;
- (void)webViewDidChange:(NSNotification *)notification;
- (void)webViewDidEndEditing:(NSNotification *)notification;
- (void)webViewDidChangeSelection:(NSNotification *)notification;
@end

/* ---- the web view ------------------------------------------------------------------- */

WEBKIT_EXTERN NSString *const WebViewProgressStartedNotification;
WEBKIT_EXTERN NSString *const WebViewProgressEstimateChangedNotification;
WEBKIT_EXTERN NSString *const WebViewProgressFinishedNotification;

@interface WebView : NSView
+ (BOOL)canShowMIMEType:(NSString *)MIMEType;
+ (BOOL)canShowMIMETypeAsHTML:(NSString *)MIMEType;
+ (NSArray *)MIMETypesShownAsHTML;
- (instancetype)initWithFrame:(NSRect)frame frameName:(NSString *)frameName groupName:(NSString *)groupName;
- (void)close;
@property (readonly, retain) WebFrame *mainFrame;
@property (assign) id<WebFrameLoadDelegate> frameLoadDelegate;
@property (assign) id<WebPolicyDelegate> policyDelegate;
@property (assign) id<WebUIDelegate> UIDelegate;
@property (assign) id resourceLoadDelegate;
@property (assign) id downloadDelegate;
@property (assign) id editingDelegate;
@property (retain) WebPreferences *preferences;
@property (copy) NSString *preferencesIdentifier;
@property (copy) NSString *customUserAgent;
@property (copy) NSString *applicationNameForUserAgent;
- (NSString *)userAgentForURL:(NSURL *)URL;
@property (copy) NSString *mainFrameURL;
@property (readonly, copy) NSString *mainFrameTitle;
@property (readonly, getter=isLoading) BOOL loading;
@property (readonly) double estimatedProgress;
@property (readonly) BOOL canGoBack;
@property (readonly) BOOL canGoForward;
- (BOOL)goBack;
- (BOOL)goForward;
@property float textSizeMultiplier;
@property (getter=isEditable) BOOL editable;
@property BOOL drawsBackground;
@property BOOL shouldUpdateWhileOffscreen;
@property BOOL maintainsBackForwardList;
@property BOOL continuousSpellCheckingEnabled;
@property (retain) NSWindow *hostWindow;
@property (copy) NSString *groupName;
@property (readonly, retain) WebScriptObject *windowScriptObject;
@property (readonly) DOMDocument *mainFrameDocument;
- (NSString *)stringByEvaluatingJavaScriptFromString:(NSString *)script;
- (IBAction)takeStringURLFrom:(id)sender;
- (IBAction)stopLoading:(id)sender;
- (IBAction)reload:(id)sender;
- (IBAction)reloadFromOrigin:(id)sender;
- (IBAction)goBack:(id)sender;
- (IBAction)goForward:(id)sender;
- (IBAction)makeTextLarger:(id)sender;
- (IBAction)makeTextSmaller:(id)sender;
- (IBAction)makeTextStandardSize:(id)sender;
@property (readonly) BOOL canMakeTextLarger;
@property (readonly) BOOL canMakeTextSmaller;
@property (readonly) BOOL canMakeTextStandardSize;
@end

/* the page's selection (freemac 1.225, Ferry 0.49.0) */
@interface WebView (FerryEditing)
@property (readonly, retain) DOMRange *selectedDOMRange;
@property (readonly) NSSelectionAffinity selectionAffinity;
- (void)setSelectedDOMRange:(DOMRange *)range affinity:(NSSelectionAffinity)selectionAffinity;
- (DOMRange *)editableDOMRangeForPoint:(NSPoint)point;
@property (readonly) BOOL hasSelectedRange;
@end

#endif
