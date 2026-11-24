// SPDX-License-Identifier: GPL-3.0-or-later
// Certificates and trust, checked by this system's OpenSSL: the test
// server's own certificate (made by run.sh, for 127.0.0.1, which this
// system doesn't trust) is refused against the system's authorities,
// accepted as an anchor, refused for another host name and outside its
// dates; and NSURLSession's server-trust object can be read, evaluated and
// given that anchor in a delegate's challenge. Built without ARC.
#import <Foundation/Foundation.h>
#include <Security/Security.h>
#include <stdio.h>
#include <stdlib.h>

static SecCertificateRef cert;

static void evaluate(const char *what, SecTrustRef trust)
{
    CFErrorRef error = NULL;
    bool ok = SecTrustEvaluateWithError(trust, &error);
    SecTrustResultType result = 0;
    SecTrustGetTrustResult(trust, &result);
    printf("  %s: %s, result %u", what, ok ? "trusted" : "not trusted", (unsigned)result);
    if (error)
        printf(", %s %ld", [[(NSError *)error domain] isEqual:NSOSStatusErrorDomain] ? "OSStatus" : "?",
               (long)[(NSError *)error code]);
    printf(", %ld in the chain\n", (long)SecTrustGetCertificateCount(trust));
    if (error)
        CFRelease(error);
}

static SecTrustRef make(CFStringRef host, BOOL anchored)
{
    SecPolicyRef policy = host ? SecPolicyCreateSSL(true, host) : SecPolicyCreateBasicX509();
    SecTrustRef trust = NULL;
    SecTrustCreateWithCertificates(cert, policy, &trust);
    if (anchored)
        SecTrustSetAnchorCertificates(trust, (CFArrayRef)[NSArray arrayWithObject:(id)cert]);
    CFRelease(policy);
    return trust;
}

@interface Judge : NSObject <NSURLSessionDelegate>
@end
@implementation Judge
- (void)URLSession:(NSURLSession *)session didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge
    completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition, NSURLCredential *))completionHandler
{
    SecTrustRef trust = challenge.protectionSpace.serverTrust;
    printf("  challenge: %s\n", [challenge.protectionSpace.authenticationMethod UTF8String]);
    printf("  the server's certificates: %ld, the file's %s\n", (long)SecTrustGetCertificateCount(trust),
           CFEqual(SecTrustGetCertificateAtIndex(trust, 0), cert) ? "yes" : "no");
    evaluate("as received", trust);
    SecTrustSetAnchorCertificates(trust, (CFArrayRef)[NSArray arrayWithObject:(id)SecTrustGetCertificateAtIndex(trust, 0)]);
    evaluate("with its own certificate as the anchor", trust);
    completionHandler(NSURLSessionAuthChallengeUseCredential, [NSURLCredential credentialForTrust:trust]);
}
@end

int main(void)
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    const char *file = getenv("FERRY_TEST_TLS_CERT"), *server = getenv("FERRY_TEST_HTTPS");
    NSData *der = [NSData dataWithContentsOfFile:[NSString stringWithUTF8String:file ?: ""]];

    printf("certificates\n");
    printf("  from garbage: %s\n",
           SecCertificateCreateWithData(NULL, (CFDataRef)[@"not a certificate" dataUsingEncoding:NSUTF8StringEncoding])
               ? "a certificate" : "NULL");
    cert = SecCertificateCreateWithData(NULL, (CFDataRef)der);
    if (!cert) {
        printf("  no certificate in %s\n", file ?: "(nothing)");
        return 1;
    }
    CFStringRef summary = SecCertificateCopySubjectSummary(cert), cn = NULL;
    OSStatus s = SecCertificateCopyCommonName(cert, &cn);
    printf("  summary %s, common name %d %s\n", [(NSString *)summary UTF8String], (int)s, [(NSString *)cn UTF8String]);
    CFDataRef back = SecCertificateCopyData(cert);
    SecCertificateRef twin = SecCertificateCreateWithData(NULL, back);
    printf("  its data back: %s, the same certificate again: %s\n", [(NSData *)back isEqual:der] ? "same" : "different",
           CFEqual(twin, cert) ? "equal" : "not equal");

    printf("trust\n");
    SecTrustRef t = make(CFSTR("127.0.0.1"), NO);
    SecTrustResultType before = 99;
    SecTrustGetTrustResult(t, &before);
    printf("  before evaluating: result %u\n", (unsigned)before);
    evaluate("against the system's authorities", t);
    SecTrustSetAnchorCertificatesOnly(t, false);
    evaluate("still, with no anchors of its own", t);
    CFRelease(t);
    t = make(CFSTR("127.0.0.1"), YES);
    evaluate("with it as the anchor", t);
    SecTrustResultType r = 0;
    printf("  SecTrustEvaluate: %d, result %u\n", (int)SecTrustEvaluate(t, &r), (unsigned)r);
    SecTrustSetAnchorCertificatesOnly(t, false);
    evaluate("with it and the system's", t);
    SecTrustSetVerifyDate(t, (CFDateRef)[NSDate dateWithTimeIntervalSince1970:946684800]); /* 2000 */
    evaluate("in 2000", t);
    SecTrustSetVerifyDate(t, (CFDateRef)[NSDate dateWithTimeIntervalSince1970:4102444800.0]); /* 2100 */
    evaluate("in 2100", t);
    CFRelease(t);
    t = make(CFSTR("localhost"), YES);
    evaluate("for localhost", t);
    CFRelease(t);
    t = make(NULL, YES);
    evaluate("basic X.509, anchored", t);
    CFArrayRef policies = NULL;
    SecTrustCopyPolicies(t, &policies);
    CFArrayRef chain = SecTrustCopyCertificateChain(t);
    printf("  policies %ld, chain %ld, its first the certificate %s\n", (long)CFArrayGetCount(policies),
           (long)CFArrayGetCount(chain), CFEqual(CFArrayGetValueAtIndex(chain, 0), cert) ? "yes" : "no");
    CFRelease(policies);
    CFRelease(chain);
    dispatch_queue_t q = dispatch_queue_create("trust", NULL);
    dispatch_semaphore_t answer = dispatch_semaphore_create(0);
    __block int answered = 0;
    s = SecTrustEvaluateAsyncWithError(t, q, ^(SecTrustRef trust, bool trusted, CFErrorRef error) {
      answered = trusted ? 1 : 2;
      dispatch_semaphore_signal(answer);
    });
    dispatch_semaphore_wait(answer, DISPATCH_TIME_FOREVER);
    dispatch_release(answer);
    dispatch_release(q);
    printf("  asynchronously: %d, %s\n", (int)s, answered == 1 ? "trusted" : answered ? "not trusted" : "no answer");
    CFRelease(t);
    printf("  no certificates: %d\n", (int)SecTrustCreateWithCertificates((CFArrayRef)[NSArray array], NULL, &t));

    printf("a server's trust, through NSURLSession\n");
    Judge *judge = [[Judge alloc] init];
    NSURLSession *session = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration ephemeralSessionConfiguration]
                                                          delegate:judge delegateQueue:nil];
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"https://%s/hello", server ?: "127.0.0.1:1"]];
    __block BOOL done = NO;
    [[session dataTaskWithURL:url
            completionHandler:^(NSData *d, NSURLResponse *resp, NSError *e) {
              if (e)
                  printf("  error %s %ld\n", [e.domain UTF8String], (long)e.code);
              else
                  printf("  status %ld: %s", (long)((NSHTTPURLResponse *)resp).statusCode,
                         [[[[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] autorelease] UTF8String]);
              done = YES;
            }] resume];
    while (!done)
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:1]];
    [session invalidateAndCancel];
    [judge release];
    CFRelease(cert);
    CFRelease(twin);
    CFRelease(back);
    CFRelease(summary);
    CFRelease(cn);
    [pool drain];
    return 0;
}
