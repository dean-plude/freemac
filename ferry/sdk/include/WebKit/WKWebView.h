/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's WebKit: the web view of current macOS (WKWebView) and the classes
 * around it, written from Apple's public documentation. Imported by
 * WebKit.h. Ferry shows the pages with this system's WebKitGTK. */
#ifndef _FERRY_WEBKIT_WKWEBVIEW_H_
#define _FERRY_WEBKIT_WKWEBVIEW_H_
#import <AppKit/AppKit.h>

#ifndef WK_EXTERN
#define WK_EXTERN extern
#endif

@class WKWebView, WKFrameInfo, WKNavigation, WKNavigationAction, WKNavigationResponse, WKWindowFeatures;
@class WKUserContentController, WKWebsiteDataStore, WKContentWorld, WKSecurityOrigin;

/* ---- errors ------------------------------------------------------------------------- */

WK_EXTERN NSString *const WKErrorDomain;
typedef NS_ENUM(NSInteger, WKErrorCode) {
    WKErrorUnknown = 1,
    WKErrorWebContentProcessTerminated = 2,
    WKErrorWebViewInvalidated = 3,
    WKErrorJavaScriptExceptionOccurred = 4,
    WKErrorJavaScriptResultTypeIsUnsupported = 5,
};
/* NSError user info keys of a JavaScript exception (macOS 10.15.4) */
WK_EXTERN NSString *const WKJavaScriptExceptionMessage;
WK_EXTERN NSString *const WKJavaScriptExceptionLineNumber;
WK_EXTERN NSString *const WKJavaScriptExceptionColumnNumber;
WK_EXTERN NSString *const WKJavaScriptExceptionSourceURL;

/* ---- the shared pieces of a configuration ---------------------------------------------- */

/* The web content processes; one stands for all here. */
@interface WKProcessPool : NSObject <NSSecureCoding>
@end

@interface WKPreferences : NSObject <NSSecureCoding>
@property CGFloat minimumFontSize;
@property BOOL javaScriptEnabled;
@property BOOL javaScriptCanOpenWindowsAutomatically;
@property BOOL tabFocusesLinks;
@property (getter=isFraudulentWebsiteWarningEnabled) BOOL fraudulentWebsiteWarningEnabled;
@property (getter=isTextInteractionEnabled) BOOL textInteractionEnabled;
@property (getter=isElementFullscreenEnabled) BOOL elementFullscreenEnabled;
@property BOOL javaEnabled;
@property BOOL plugInsEnabled;
@end

typedef NS_ENUM(NSInteger, WKContentMode) {
    WKContentModeRecommended,
    WKContentModeMobile,
    WKContentModeDesktop,
};
@interface WKWebpagePreferences : NSObject
@property BOOL allowsContentJavaScript;
@property WKContentMode preferredContentMode;
@end

typedef NS_ENUM(NSInteger, WKUserScriptInjectionTime) {
    WKUserScriptInjectionTimeAtDocumentStart,
    WKUserScriptInjectionTimeAtDocumentEnd,
};
@interface WKUserScript : NSObject <NSCopying>
- (instancetype)initWithSource:(NSString *)source injectionTime:(WKUserScriptInjectionTime)injectionTime
              forMainFrameOnly:(BOOL)forMainFrameOnly;
- (instancetype)initWithSource:(NSString *)source injectionTime:(WKUserScriptInjectionTime)injectionTime
              forMainFrameOnly:(BOOL)forMainFrameOnly inContentWorld:(WKContentWorld *)world;
@property (readonly, copy) NSString *source;
@property (readonly) WKUserScriptInjectionTime injectionTime;
@property (readonly, getter=isForMainFrameOnly) BOOL forMainFrameOnly;
@end

/* Where scripts run: the page's own world, or one of the app's. */
@interface WKContentWorld : NSObject
@property (class, readonly) WKContentWorld *pageWorld;
@property (class, readonly) WKContentWorld *defaultClientWorld;
+ (WKContentWorld *)worldWithName:(NSString *)name;
@property (readonly, copy) NSString *name;
@end

@interface WKScriptMessage : NSObject
@property (readonly, copy) id body;
@property (readonly, weak) WKWebView *webView;
@property (readonly, copy) WKFrameInfo *frameInfo;
@property (readonly, copy) NSString *name;
@property (readonly) WKContentWorld *world;
@end

@protocol WKScriptMessageHandler <NSObject>
- (void)userContentController:(WKUserContentController *)userContentController
      didReceiveScriptMessage:(WKScriptMessage *)message;
@end

@interface WKUserContentController : NSObject <NSSecureCoding>
@property (readonly, copy) NSArray<WKUserScript *> *userScripts;
- (void)addUserScript:(WKUserScript *)userScript;
- (void)removeAllUserScripts;
- (void)addScriptMessageHandler:(id<WKScriptMessageHandler>)scriptMessageHandler name:(NSString *)name;
- (void)addScriptMessageHandler:(id<WKScriptMessageHandler>)scriptMessageHandler
                   contentWorld:(WKContentWorld *)world
                           name:(NSString *)name;
- (void)removeScriptMessageHandlerForName:(NSString *)name;
- (void)removeScriptMessageHandlerForName:(NSString *)name contentWorld:(WKContentWorld *)contentWorld;
- (void)removeAllScriptMessageHandlers;
@end

/* Kinds of website data */
WK_EXTERN NSString *const WKWebsiteDataTypeDiskCache;
WK_EXTERN NSString *const WKWebsiteDataTypeMemoryCache;
WK_EXTERN NSString *const WKWebsiteDataTypeOfflineWebApplicationCache;
WK_EXTERN NSString *const WKWebsiteDataTypeCookies;
WK_EXTERN NSString *const WKWebsiteDataTypeSessionStorage;
WK_EXTERN NSString *const WKWebsiteDataTypeLocalStorage;
WK_EXTERN NSString *const WKWebsiteDataTypeWebSQLDatabases;
WK_EXTERN NSString *const WKWebsiteDataTypeIndexedDBDatabases;
WK_EXTERN NSString *const WKWebsiteDataTypeFetchCache;
WK_EXTERN NSString *const WKWebsiteDataTypeServiceWorkerRegistrations;

@interface WKWebsiteDataStore : NSObject <NSSecureCoding>
+ (WKWebsiteDataStore *)defaultDataStore;
+ (WKWebsiteDataStore *)nonPersistentDataStore;
@property (readonly, getter=isPersistent) BOOL persistent;
+ (NSSet<NSString *> *)allWebsiteDataTypes;
- (void)removeDataOfTypes:(NSSet<NSString *> *)dataTypes modifiedSince:(NSDate *)date
        completionHandler:(void (^)(void))completionHandler;
@end

@interface WKWebViewConfiguration : NSObject <NSSecureCoding, NSCopying>
@property (retain) WKProcessPool *processPool;
@property (retain) WKPreferences *preferences;
@property (retain) WKUserContentController *userContentController;
@property (retain) WKWebsiteDataStore *websiteDataStore;
@property (retain) WKWebpagePreferences *defaultWebpagePreferences;
@property (copy) NSString *applicationNameForUserAgent;
@property BOOL suppressesIncrementalRendering;
@property BOOL allowsAirPlayForMediaPlayback;
@property BOOL limitsNavigationsToAppBoundDomains;
@property BOOL upgradeKnownHostsToHTTPS;
@end

/* ---- what the delegates are told ---------------------------------------------------- */

@interface WKSecurityOrigin : NSObject
@property (readonly, copy) NSString *protocol;
@property (readonly, copy) NSString *host;
@property (readonly) NSInteger port;
@end

@interface WKFrameInfo : NSObject <NSCopying>
@property (readonly, getter=isMainFrame) BOOL mainFrame;
@property (readonly, copy) NSURLRequest *request;
@property (readonly) WKSecurityOrigin *securityOrigin;
@property (readonly, weak) WKWebView *webView;
@end

@interface WKNavigation : NSObject
@property (readonly) WKContentMode effectiveContentMode;
@end

typedef NS_ENUM(NSInteger, WKNavigationType) {
    WKNavigationTypeLinkActivated,
    WKNavigationTypeFormSubmitted,
    WKNavigationTypeBackForward,
    WKNavigationTypeReload,
    WKNavigationTypeFormResubmitted,
    WKNavigationTypeOther = -1,
};
@interface WKNavigationAction : NSObject
@property (readonly, copy) WKFrameInfo *sourceFrame;
@property (readonly, copy) WKFrameInfo *targetFrame;
@property (readonly) WKNavigationType navigationType;
@property (readonly, copy) NSURLRequest *request;
@property (readonly) NSEventModifierFlags modifierFlags;
@property (readonly) NSInteger buttonNumber;
@property (readonly) BOOL shouldPerformDownload;
@end

@interface WKNavigationResponse : NSObject
@property (readonly, getter=isForMainFrame) BOOL forMainFrame;
@property (readonly, copy) NSURLResponse *response;
@property (readonly) BOOL canShowMIMEType;
@end

@interface WKWindowFeatures : NSObject
@property (readonly) NSNumber *menuBarVisibility;
@property (readonly) NSNumber *statusBarVisibility;
@property (readonly) NSNumber *toolbarsVisibility;
@property (readonly) NSNumber *allowsResizing;
@property (readonly) NSNumber *x;
@property (readonly) NSNumber *y;
@property (readonly) NSNumber *width;
@property (readonly) NSNumber *height;
@end

@interface WKBackForwardListItem : NSObject
@property (readonly, copy) NSURL *URL;
@property (readonly, copy) NSString *title;
@property (readonly, copy) NSURL *initialURL;
@end

@interface WKBackForwardList : NSObject
@property (readonly) WKBackForwardListItem *currentItem;
@property (readonly) WKBackForwardListItem *backItem;
@property (readonly) WKBackForwardListItem *forwardItem;
- (WKBackForwardListItem *)itemAtIndex:(NSInteger)index;
@property (readonly, copy) NSArray<WKBackForwardListItem *> *backList;
@property (readonly, copy) NSArray<WKBackForwardListItem *> *forwardList;
@end

@interface WKSnapshotConfiguration : NSObject <NSCopying>
@property NSRect rect;
@property (copy) NSNumber *snapshotWidth;
@property BOOL afterScreenUpdates;
@end

typedef NS_ENUM(NSInteger, WKNavigationActionPolicy) {
    WKNavigationActionPolicyCancel,
    WKNavigationActionPolicyAllow,
    WKNavigationActionPolicyDownload,
};
typedef NS_ENUM(NSInteger, WKNavigationResponsePolicy) {
    WKNavigationResponsePolicyCancel,
    WKNavigationResponsePolicyAllow,
    WKNavigationResponsePolicyDownload,
};

@protocol WKNavigationDelegate <NSObject>
@optional
- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction
    decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler;
- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction
        preferences:(WKWebpagePreferences *)preferences
    decisionHandler:(void (^)(WKNavigationActionPolicy, WKWebpagePreferences *))decisionHandler;
- (void)webView:(WKWebView *)webView decidePolicyForNavigationResponse:(WKNavigationResponse *)navigationResponse
    decisionHandler:(void (^)(WKNavigationResponsePolicy))decisionHandler;
- (void)webView:(WKWebView *)webView didStartProvisionalNavigation:(WKNavigation *)navigation;
- (void)webView:(WKWebView *)webView didReceiveServerRedirectForProvisionalNavigation:(WKNavigation *)navigation;
- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(WKNavigation *)navigation
      withError:(NSError *)error;
- (void)webView:(WKWebView *)webView didCommitNavigation:(WKNavigation *)navigation;
- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation;
- (void)webView:(WKWebView *)webView didFailNavigation:(WKNavigation *)navigation withError:(NSError *)error;
- (void)webViewWebContentProcessDidTerminate:(WKWebView *)webView;
@end

@protocol WKUIDelegate <NSObject>
@optional
- (WKWebView *)webView:(WKWebView *)webView createWebViewWithConfiguration:(WKWebViewConfiguration *)configuration
    forNavigationAction:(WKNavigationAction *)navigationAction
         windowFeatures:(WKWindowFeatures *)windowFeatures;
- (void)webViewDidClose:(WKWebView *)webView;
- (void)webView:(WKWebView *)webView runJavaScriptAlertPanelWithMessage:(NSString *)message
    initiatedByFrame:(WKFrameInfo *)frame
    completionHandler:(void (^)(void))completionHandler;
- (void)webView:(WKWebView *)webView runJavaScriptConfirmPanelWithMessage:(NSString *)message
    initiatedByFrame:(WKFrameInfo *)frame
    completionHandler:(void (^)(BOOL result))completionHandler;
- (void)webView:(WKWebView *)webView runJavaScriptTextInputPanelWithPrompt:(NSString *)prompt
          defaultText:(NSString *)defaultText
     initiatedByFrame:(WKFrameInfo *)frame
    completionHandler:(void (^)(NSString *result))completionHandler;
@end

/* ---- the web view ------------------------------------------------------------------- */

@interface WKWebView : NSView
- (instancetype)initWithFrame:(NSRect)frame configuration:(WKWebViewConfiguration *)configuration;
@property (readonly, copy) WKWebViewConfiguration *configuration;
@property (weak) id<WKNavigationDelegate> navigationDelegate;
@property (weak) id<WKUIDelegate> UIDelegate;
@property (readonly, retain) WKBackForwardList *backForwardList;

- (WKNavigation *)loadRequest:(NSURLRequest *)request;
- (WKNavigation *)loadFileURL:(NSURL *)URL allowingReadAccessToURL:(NSURL *)readAccessURL;
- (WKNavigation *)loadHTMLString:(NSString *)string baseURL:(NSURL *)baseURL;
- (WKNavigation *)loadData:(NSData *)data MIMEType:(NSString *)MIMEType
      characterEncodingName:(NSString *)characterEncodingName baseURL:(NSURL *)baseURL;
- (WKNavigation *)goToBackForwardListItem:(WKBackForwardListItem *)item;

@property (readonly, copy) NSString *title;
@property (readonly, copy) NSURL *URL;
@property (readonly, getter=isLoading) BOOL loading;
@property (readonly) double estimatedProgress;
@property (readonly) BOOL hasOnlySecureContent;
@property (readonly) BOOL canGoBack;
@property (readonly) BOOL canGoForward;

- (WKNavigation *)goBack;
- (WKNavigation *)goForward;
- (WKNavigation *)reload;
- (WKNavigation *)reloadFromOrigin;
- (void)stopLoading;

- (void)evaluateJavaScript:(NSString *)javaScriptString completionHandler:(void (^)(id result, NSError *error))completionHandler;
- (void)evaluateJavaScript:(NSString *)javaScriptString inFrame:(WKFrameInfo *)frame
            inContentWorld:(WKContentWorld *)contentWorld
         completionHandler:(void (^)(id result, NSError *error))completionHandler;
- (void)takeSnapshotWithConfiguration:(WKSnapshotConfiguration *)snapshotConfiguration
                    completionHandler:(void (^)(NSImage *snapshotImage, NSError *error))completionHandler;

@property BOOL allowsBackForwardNavigationGestures;
@property (copy) NSString *customUserAgent;
@property BOOL allowsLinkPreview;
@property BOOL allowsMagnification;
@property CGFloat magnification;
- (void)setMagnification:(CGFloat)magnification centeredAtPoint:(CGPoint)point;
@property CGFloat pageZoom;
+ (BOOL)handlesURLScheme:(NSString *)urlScheme;

- (IBAction)goBack:(id)sender;
- (IBAction)goForward:(id)sender;
- (IBAction)reload:(id)sender;
- (IBAction)reloadFromOrigin:(id)sender;
- (IBAction)stopLoading:(id)sender;
@end

#endif
