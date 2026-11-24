/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's WebKit: the older WebView's resource load delegate, written from
 * Apple's public documentation (freemac 1.217, Ferry 0.42.0). Imported by
 * WebKit.h. It is told about each resource a page loads, the page itself
 * included: the identifier it gives the resource, the request sent, the
 * response, the data's length as it comes, and the end or failure. */
#ifndef _FERRY_WEBKIT_WEBRESOURCELOADDELEGATE_H_
#define _FERRY_WEBKIT_WEBRESOURCELOADDELEGATE_H_
#import <WebKit/WebView.h>

@protocol WebResourceLoadDelegate <NSObject>
@optional
- (id)webView:(WebView *)sender identifierForInitialRequest:(NSURLRequest *)request
    fromDataSource:(WebDataSource *)dataSource;
- (NSURLRequest *)webView:(WebView *)sender resource:(id)identifier
          willSendRequest:(NSURLRequest *)request
         redirectResponse:(NSURLResponse *)redirectResponse
           fromDataSource:(WebDataSource *)dataSource;
- (void)webView:(WebView *)sender resource:(id)identifier didReceiveResponse:(NSURLResponse *)response
    fromDataSource:(WebDataSource *)dataSource;
- (void)webView:(WebView *)sender resource:(id)identifier didReceiveContentLength:(NSInteger)length
    fromDataSource:(WebDataSource *)dataSource;
- (void)webView:(WebView *)sender resource:(id)identifier didFinishLoadingFromDataSource:(WebDataSource *)dataSource;
- (void)webView:(WebView *)sender resource:(id)identifier didFailLoadingWithError:(NSError *)error
    fromDataSource:(WebDataSource *)dataSource;
@end

#endif
