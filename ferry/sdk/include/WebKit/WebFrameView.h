/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's WebKit: the view of a WebFrame in the older WebView, and the
 * document view inside it, written from Apple's public documentation
 * (freemac 1.217, Ferry 0.42.0). Imported by WebKit.h.
 *
 * The page itself is drawn by this system's WebKitGTK over the web view.
 * The frame view holds a scroll view whose document view is as large as
 * the page and whose clip view is scrolled where the page is, so a program
 * can read the page's size and scroll position, and scroll it, as it would
 * on a Mac. */
#ifndef _FERRY_WEBKIT_WEBFRAMEVIEW_H_
#define _FERRY_WEBKIT_WEBFRAMEVIEW_H_
#import <WebKit/WebView.h>

/* what a document view does for its frame */
@protocol WebDocumentView <NSObject>
- (void)setDataSource:(WebDataSource *)dataSource;
- (void)dataSourceUpdated:(WebDataSource *)dataSource;
- (void)setNeedsLayout:(BOOL)flag;
- (void)layout;
- (void)viewWillMoveToHostWindow:(NSWindow *)hostWindow;
- (void)viewDidMoveToHostWindow;
@end

/* the text of a document view */
@protocol WebDocumentText <NSObject>
- (BOOL)supportsTextEncoding;
- (NSString *)string;
- (NSAttributedString *)attributedString;
- (NSString *)selectedString;
- (NSAttributedString *)selectedAttributedString;
- (void)selectAll;
- (void)deselectAll;
@end

@interface WebFrameView : NSView
@property (readonly) WebFrame *webFrame;
@property (readonly, retain) NSView<WebDocumentView> *documentView;
@property BOOL allowsScrolling;
@property (readonly) BOOL canPrintHeadersAndFooters;
@property (readonly) BOOL documentViewShouldHandlePrint;
- (NSPrintOperation *)printOperationWithPrintInfo:(NSPrintInfo *)printInfo;
- (void)printDocumentView;
@end

#endif
