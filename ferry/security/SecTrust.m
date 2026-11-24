/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's Security framework: certificates, policies and trust. Our own
 * code, written from Apple's public API documentation of Security
 * (SecCertificate.h, SecPolicy.h, SecTrust.h and "Evaluating a Trust and
 * Parsing the Result").
 *
 * A trust is checked by this system's OpenSSL against this system's
 * certificate authorities (OpenSSL's default places, the ones every
 * program here trusts), or against the anchors a program gives: the chain
 * is built from the certificates given, the dates checked (now, or the
 * verify date), and for an SSL policy the host name or IP address and the
 * certificate's purpose. What a Mac adds on top (its own trust settings,
 * revocation, certificate transparency, its rules for certificate
 * lifetimes) is not done.
 *
 * NSURLSession's server-trust object (the challenge's
 * protectionSpace.serverTrust) is a trust here too: the first time it is
 * asked about, Ferry connects to the server itself, directly and never
 * through a proxy, and reads the certificates it presents
 * (ferry_server_certificates, in src/servercerts.c). */
#include "SInternal.h"
#include <string.h>
#include <time.h>

/* ---- libcrypto, from OpenSSL's published API documentation -------------------------- */

typedef void X509, X509_STORE, X509_STORE_CTX, X509_VERIFY_PARAM, OPENSSL_STACK, X509_NAME, X509_NAME_ENTRY,
    ASN1_STRING;
enum {
    NID_commonName = 13,
    NID_organizationName = 17,
    X509_PURPOSE_SSL_CLIENT = 1,
    X509_PURPOSE_SSL_SERVER = 2,
    X509_V_ERR_CERT_NOT_YET_VALID = 9,
    X509_V_ERR_CERT_HAS_EXPIRED = 10,
    X509_V_ERR_HOSTNAME_MISMATCH = 62,
    X509_V_ERR_IP_ADDRESS_MISMATCH = 64,
};
#define X509_V_FLAG_PARTIAL_CHAIN 0x80000UL

static struct {
    X509 *(*d2i_X509)(X509 **, const unsigned char **, long);
    int (*i2d_X509)(X509 *, unsigned char **);
    void (*X509_free)(X509 *);
    X509_NAME *(*X509_get_subject_name)(const X509 *);
    int (*X509_NAME_get_index_by_NID)(X509_NAME *, int, int);
    X509_NAME_ENTRY *(*X509_NAME_get_entry)(const X509_NAME *, int);
    ASN1_STRING *(*X509_NAME_ENTRY_get_data)(const X509_NAME_ENTRY *);
    int (*ASN1_STRING_to_UTF8)(unsigned char **, const ASN1_STRING *);
    void (*CRYPTO_free)(void *, const char *, int);
    X509_STORE *(*X509_STORE_new)(void);
    void (*X509_STORE_free)(X509_STORE *);
    int (*X509_STORE_set_default_paths)(X509_STORE *);
    int (*X509_STORE_add_cert)(X509_STORE *, X509 *);
    X509_STORE_CTX *(*X509_STORE_CTX_new)(void);
    void (*X509_STORE_CTX_free)(X509_STORE_CTX *);
    int (*X509_STORE_CTX_init)(X509_STORE_CTX *, X509_STORE *, X509 *, OPENSSL_STACK *);
    X509_VERIFY_PARAM *(*X509_STORE_CTX_get0_param)(X509_STORE_CTX *);
    int (*X509_VERIFY_PARAM_set_flags)(X509_VERIFY_PARAM *, unsigned long);
    void (*X509_VERIFY_PARAM_set_time)(X509_VERIFY_PARAM *, time_t);
    int (*X509_VERIFY_PARAM_set1_host)(X509_VERIFY_PARAM *, const char *, size_t);
    int (*X509_VERIFY_PARAM_set1_ip_asc)(X509_VERIFY_PARAM *, const char *);
    int (*X509_VERIFY_PARAM_set_purpose)(X509_VERIFY_PARAM *, int);
    int (*X509_verify_cert)(X509_STORE_CTX *);
    int (*X509_STORE_CTX_get_error)(X509_STORE_CTX *);
    const char *(*X509_verify_cert_error_string)(long);
    OPENSSL_STACK *(*X509_STORE_CTX_get1_chain)(X509_STORE_CTX *);
    OPENSSL_STACK *(*OPENSSL_sk_new_null)(void);
    int (*OPENSSL_sk_push)(OPENSSL_STACK *, const void *);
    int (*OPENSSL_sk_num)(const OPENSSL_STACK *);
    void *(*OPENSSL_sk_value)(const OPENSSL_STACK *, int);
    void (*OPENSSL_sk_free)(OPENSSL_STACK *);
} X;

/* YES once libcrypto's calls are found; NO when this system has no libcrypto. */
static BOOL crypto(void)
{
    static int state; /* 0 not tried, 1 found, -1 missing */
    @synchronized([SCertificate class]) {
        if (!state) {
            state = 1;
#define CALL(name) if (!(*(void **)&X.name = ferry_crypto_symbol(#name))) state = -1;
            CALL(d2i_X509) CALL(i2d_X509) CALL(X509_free) CALL(X509_get_subject_name)
            CALL(X509_NAME_get_index_by_NID) CALL(X509_NAME_get_entry) CALL(X509_NAME_ENTRY_get_data)
            CALL(ASN1_STRING_to_UTF8) CALL(CRYPTO_free) CALL(X509_STORE_new) CALL(X509_STORE_free)
            CALL(X509_STORE_set_default_paths) CALL(X509_STORE_add_cert) CALL(X509_STORE_CTX_new)
            CALL(X509_STORE_CTX_free) CALL(X509_STORE_CTX_init) CALL(X509_STORE_CTX_get0_param)
            CALL(X509_VERIFY_PARAM_set_flags) CALL(X509_VERIFY_PARAM_set_time) CALL(X509_VERIFY_PARAM_set1_host)
            CALL(X509_VERIFY_PARAM_set1_ip_asc) CALL(X509_VERIFY_PARAM_set_purpose) CALL(X509_verify_cert)
            CALL(X509_STORE_CTX_get_error) CALL(X509_verify_cert_error_string) CALL(X509_STORE_CTX_get1_chain)
            CALL(OPENSSL_sk_new_null) CALL(OPENSSL_sk_push) CALL(OPENSSL_sk_num) CALL(OPENSSL_sk_value)
            CALL(OPENSSL_sk_free)
#undef CALL
            if (state < 0)
                SVerboseOnce(@"this system's OpenSSL (libcrypto) was not found: certificates can't be read");
        }
    }
    return state > 0;
}

static X509 *parse_der(NSData *der)
{
    const unsigned char *p = [der bytes];
    X509 *x = X.d2i_X509(NULL, &p, (long)[der length]);
    if (x && p != (const unsigned char *)[der bytes] + [der length]) { /* something after it */
        X.X509_free(x);
        return NULL;
    }
    return x;
}

static NSData *der_of(X509 *x)
{
    int n = X.i2d_X509(x, NULL);
    if (n <= 0)
        return nil;
    NSMutableData *d = [NSMutableData dataWithLength:(NSUInteger)n];
    unsigned char *p = [d mutableBytes];
    return X.i2d_X509(x, &p) == n ? d : nil;
}

/* ---- certificates --------------------------------------------------------------------- */

@implementation SCertificate
- (void)dealloc
{
    [der release];
    [super dealloc];
}
- (BOOL)isEqual:(id)other { return [other isKindOfClass:[SCertificate class]] && [((SCertificate *)other)->der isEqual:der]; }
- (NSUInteger)hash { return [der hash]; }
- (NSString *)description
{
    NSString *s = [(id)SecCertificateCopySubjectSummary((SecCertificateRef)self) autorelease];
    return [NSString stringWithFormat:@"<SecCertificate %p %@>", self, s ?: @"?"];
}
@end

static SCertificate *new_certificate(NSData *der)
{
    SCertificate *c = [[SCertificate alloc] init];
    c->der = [der copy];
    return c;
}

/* DER only, as on a Mac; NULL for anything else, or when this system has no libcrypto. */
S_EXPORT SecCertificateRef SecCertificateCreateWithData(CFAllocatorRef allocator, CFDataRef data)
{
    NSData *d = (NSData *)data;
    if (![d isKindOfClass:[NSData class]] || ![d length] || !crypto())
        return NULL;
    X509 *x = parse_der(d);
    if (!x)
        return NULL;
    X.X509_free(x);
    return (SecCertificateRef)new_certificate(d);
}

S_EXPORT CFDataRef SecCertificateCopyData(SecCertificateRef certificate)
{
    SCertificate *c = (SCertificate *)certificate;
    return [c isKindOfClass:[SCertificate class]] ? (CFDataRef)[c->der copy] : NULL;
}

static NSString *name_entry(SCertificate *c, int nid)
{
    if (![c isKindOfClass:[SCertificate class]] || !crypto())
        return nil;
    X509 *x = parse_der(c->der);
    if (!x)
        return nil;
    NSString *s = nil;
    X509_NAME *name = X.X509_get_subject_name(x);
    int i = name ? X.X509_NAME_get_index_by_NID(name, nid, -1) : -1;
    unsigned char *utf8 = NULL;
    int n = i >= 0 ? X.ASN1_STRING_to_UTF8(&utf8, X.X509_NAME_ENTRY_get_data(X.X509_NAME_get_entry(name, i))) : -1;
    if (n >= 0) {
        s = [[NSString alloc] initWithBytes:utf8 length:(NSUInteger)n encoding:NSUTF8StringEncoding];
        X.CRYPTO_free(utf8, "", 0);
    }
    X.X509_free(x);
    return s; /* retained */
}

/* The subject's common name, or else its organization. */
S_EXPORT CFStringRef SecCertificateCopySubjectSummary(SecCertificateRef certificate)
{
    NSString *s = name_entry((SCertificate *)certificate, NID_commonName);
    return (CFStringRef)(s ?: name_entry((SCertificate *)certificate, NID_organizationName));
}

S_EXPORT OSStatus SecCertificateCopyCommonName(SecCertificateRef certificate, CFStringRef *commonName)
{
    if (!commonName || ![(id)certificate isKindOfClass:[SCertificate class]])
        return errSecParam;
    *commonName = (CFStringRef)name_entry((SCertificate *)certificate, NID_commonName);
    return *commonName ? errSecSuccess : errSecNoSuchAttr;
}

/* ---- policies ----------------------------------------------------------------------------- */

@implementation SPolicy
- (void)dealloc
{
    [host release];
    [super dealloc];
}
- (NSString *)description
{
    return ssl ? [NSString stringWithFormat:@"<SecPolicy %p SSL %@ %@>", self, server ? @"server" : @"client", host ?: @""]
               : [NSString stringWithFormat:@"<SecPolicy %p basic X.509>", self];
}
@end

S_EXPORT SecPolicyRef SecPolicyCreateBasicX509(void)
{
    return (SecPolicyRef)[[SPolicy alloc] init];
}

S_EXPORT SecPolicyRef SecPolicyCreateSSL(Boolean server, CFStringRef hostname)
{
    SPolicy *p = [[SPolicy alloc] init];
    p->ssl = YES;
    p->server = server != 0;
    p->host = [[(NSString *)hostname description] copy];
    return (SecPolicyRef)p;
}

/* ---- trust -------------------------------------------------------------------------------- */

@implementation STrust
- (void)dealloc
{
    [certificates release];
    [policies release];
    [anchors release];
    [verifyDate release];
    [fetchHost release];
    [chain release];
    [error release];
    [super dealloc];
}
- (void)invalidate
{
    evaluated = trusted = NO;
    result = kSecTrustResultInvalid;
    [chain release];
    chain = nil;
    [error release];
    error = nil;
}
- (NSString *)description
{
    return [NSString stringWithFormat:@"<SecTrust %p %lu certificates>", self, (unsigned long)[certificates count]];
}
@end

/* One of these, or an array of them; nil for anything else. */
static NSArray *array_of(id value, Class cls)
{
    NSArray *a = [value isKindOfClass:[NSArray class]] ? value : value ? [NSArray arrayWithObject:value] : nil;
    for (id o in a)
        if (![o isKindOfClass:cls])
            return nil;
    return a;
}

/* The trust behind a SecTrustRef: our own, or the one behind NSURLSession's server trust. */
static STrust *trust_of(SecTrustRef ref)
{
    id o = (id)ref;
    if ([o isKindOfClass:[STrust class]])
        return o;
    if (![o respondsToSelector:@selector(_ferrySecurityTrust)])
        return nil;
    @synchronized(o) {
        STrust *t = [o _ferrySecurityTrust];
        if (!t) {
            t = [[STrust alloc] init];
            t->fetchHost = [[o _ferryTrustHost] copy];
            t->fetchPort = [o _ferryTrustPort] ?: 443;
            t->certificates = [[NSArray alloc] init];
            t->anchorsOnly = YES;
            SPolicy *p = (SPolicy *)SecPolicyCreateSSL(YES, (CFStringRef)t->fetchHost);
            t->policies = [[NSArray alloc] initWithObjects:p, nil];
            [p release];
            [o _setFerrySecurityTrust:t];
            [t release];
        }
        return t;
    }
}

S_EXPORT OSStatus SecTrustCreateWithCertificates(CFTypeRef certificates, CFTypeRef policies, SecTrustRef *trust)
{
    if (!trust)
        return errSecParam;
    *trust = NULL;
    NSArray *certs = array_of((id)certificates, [SCertificate class]);
    NSArray *pols = policies ? array_of((id)policies, [SPolicy class]) : [NSArray array];
    if (![certs count] || !pols)
        return errSecParam;
    STrust *t = [[STrust alloc] init];
    t->certificates = [certs copy];
    t->policies = [pols copy];
    t->anchorsOnly = YES;
    *trust = (SecTrustRef)t;
    return errSecSuccess;
}

S_EXPORT OSStatus SecTrustSetPolicies(SecTrustRef trust, CFTypeRef policies)
{
    STrust *t = trust_of(trust);
    NSArray *pols = array_of((id)policies, [SPolicy class]);
    if (!t || !pols)
        return errSecParam;
    @synchronized(t) {
        [t->policies release];
        t->policies = [pols copy];
        [t invalidate];
    }
    return errSecSuccess;
}

S_EXPORT OSStatus SecTrustCopyPolicies(SecTrustRef trust, CFArrayRef *policies)
{
    STrust *t = trust_of(trust);
    if (!t || !policies)
        return errSecParam;
    @synchronized(t) {
        *policies = (CFArrayRef)[t->policies copy];
    }
    return errSecSuccess;
}

/* Only these from then on; NULL goes back to the system's. */
S_EXPORT OSStatus SecTrustSetAnchorCertificates(SecTrustRef trust, CFArrayRef anchorCertificates)
{
    STrust *t = trust_of(trust);
    NSArray *a = anchorCertificates ? array_of((id)anchorCertificates, [SCertificate class]) : nil;
    if (!t || (anchorCertificates && !a))
        return errSecParam;
    @synchronized(t) {
        [t->anchors release];
        t->anchors = [a copy];
        t->anchorsOnly = YES;
        [t invalidate];
    }
    return errSecSuccess;
}

S_EXPORT OSStatus SecTrustSetAnchorCertificatesOnly(SecTrustRef trust, Boolean anchorCertificatesOnly)
{
    STrust *t = trust_of(trust);
    if (!t)
        return errSecParam;
    @synchronized(t) {
        t->anchorsOnly = anchorCertificatesOnly != 0;
        [t invalidate];
    }
    return errSecSuccess;
}

S_EXPORT OSStatus SecTrustSetVerifyDate(SecTrustRef trust, CFDateRef verifyDate)
{
    STrust *t = trust_of(trust);
    if (!t || ![(id)verifyDate isKindOfClass:[NSDate class]])
        return errSecParam;
    @synchronized(t) {
        [t->verifyDate release];
        t->verifyDate = [(NSDate *)verifyDate retain];
        [t invalidate];
    }
    return errSecSuccess;
}

static void collect(void *ctx, const unsigned char *der, size_t len)
{
    SCertificate *c = new_certificate([NSData dataWithBytes:der length:len]);
    [(NSMutableArray *)ctx addObject:c];
    [c release];
}

/* An IPv6 address, or four numbers with dots: checked as an address, not a name. */
static BOOL is_ip_address(NSString *host)
{
    if ([host rangeOfString:@":"].location != NSNotFound)
        return YES;
    NSArray *parts = [host componentsSeparatedByString:@"."];
    if ([parts count] != 4)
        return NO;
    for (NSString *part in parts) {
        if (![part length] || [part length] > 3)
            return NO;
        for (NSUInteger i = 0; i < [part length]; i++)
            if ([part characterAtIndex:i] < '0' || [part characterAtIndex:i] > '9')
                return NO;
    }
    return YES;
}

static void fail(STrust *t, OSStatus status, NSString *why)
{
    t->trusted = NO;
    t->result = kSecTrustResultRecoverableTrustFailure;
    t->error = SCopyError(status, why);
}

/* Builds and checks the chain once; called with the trust locked. */
static void evaluate(STrust *t)
{
    if (t->evaluated)
        return;
    t->evaluated = YES;
    if (t->fetchHost && !t->fetched) {
        t->fetched = YES;
        NSMutableArray *got = [NSMutableArray array];
        if (ferry_server_certificates([t->fetchHost UTF8String], (int)t->fetchPort, 10000, collect, got) > 0) {
            [t->certificates release];
            t->certificates = [got copy];
        }
    }
    if (![t->certificates count]) {
        t->chain = [[NSArray alloc] init];
        fail(t, errSecNotTrusted,
             [NSString stringWithFormat:@"No certificates were received from %@.", t->fetchHost ?: @"the server"]);
        return;
    }
    if (!crypto()) {
        t->chain = [t->certificates copy];
        fail(t, errSecInternalComponent, @"This system's OpenSSL (libcrypto) is needed to check certificates.");
        return;
    }

    X509_STORE *store = X.X509_STORE_new();
    X509_STORE_CTX *ctx = X.X509_STORE_CTX_new();
    OPENSSL_STACK *others = X.OPENSSL_sk_new_null();
    NSMutableArray *parsed = [NSMutableArray array];   /* to free */
    X509 *leaf = NULL;
    BOOL ok = store && ctx && others;
    for (SCertificate *c in t->certificates) {
        X509 *x = ok ? parse_der(c->der) : NULL;
        if (!x) {
            ok = NO;
            break;
        }
        [parsed addObject:[NSValue valueWithPointer:x]];
        if (!leaf)
            leaf = x;
        else
            X.OPENSSL_sk_push(others, x);
    }
    if (ok && (!t->anchors || !t->anchorsOnly))
        X.X509_STORE_set_default_paths(store);
    for (SCertificate *c in t->anchors) {
        X509 *x = ok ? parse_der(c->der) : NULL;
        if (x) {
            X.X509_STORE_add_cert(store, x);
            X.X509_free(x); /* the store keeps its own reference */
        }
    }
    int err = 0;
    if (ok && X.X509_STORE_CTX_init(ctx, store, leaf, others) == 1) {
        X509_VERIFY_PARAM *param = X.X509_STORE_CTX_get0_param(ctx);
        if (t->anchors)
            X.X509_VERIFY_PARAM_set_flags(param, X509_V_FLAG_PARTIAL_CHAIN);
        if (t->verifyDate)
            X.X509_VERIFY_PARAM_set_time(param, (time_t)[t->verifyDate timeIntervalSince1970]);
        for (SPolicy *p in t->policies) {
            if (!p->ssl)
                continue;
            X.X509_VERIFY_PARAM_set_purpose(param, p->server ? X509_PURPOSE_SSL_SERVER : X509_PURPOSE_SSL_CLIENT);
            if ([p->host length]) {
                if (is_ip_address(p->host))
                    X.X509_VERIFY_PARAM_set1_ip_asc(param, [p->host UTF8String]);
                else
                    X.X509_VERIFY_PARAM_set1_host(param, [p->host UTF8String], 0);
            }
        }
        t->trusted = X.X509_verify_cert(ctx) == 1;
        err = X.X509_STORE_CTX_get_error(ctx);
        OPENSSL_STACK *built = X.X509_STORE_CTX_get1_chain(ctx);
        if (built) {
            NSMutableArray *c = [NSMutableArray array];
            for (int i = 0; i < X.OPENSSL_sk_num(built); i++) {
                X509 *x = X.OPENSSL_sk_value(built, i);
                NSData *d = der_of(x);
                if (d) {
                    SCertificate *sc = new_certificate(d);
                    [c addObject:sc];
                    [sc release];
                }
                X.X509_free(x);
            }
            X.OPENSSL_sk_free(built);
            if ([c count])
                t->chain = [c copy];
        }
    } else {
        ok = NO;
    }
    if (!t->chain)
        t->chain = [t->certificates copy];
    NSString *name = [(id)SecCertificateCopySubjectSummary((SecCertificateRef)[t->certificates objectAtIndex:0]) autorelease];
    if (!ok) {
        fail(t, errSecDecode, @"A certificate could not be read.");
    } else if (t->trusted) {
        t->result = kSecTrustResultUnspecified;
    } else {
        NSString *why = [NSString stringWithFormat:@"The certificate for “%@” is not trusted: %s.", name ?: @"?",
                                                   X.X509_verify_cert_error_string(err)];
        if (err == X509_V_ERR_CERT_NOT_YET_VALID)
            fail(t, errSecCertificateNotValidYet, why);
        else if (err == X509_V_ERR_CERT_HAS_EXPIRED)
            fail(t, errSecCertificateExpired, why);
        else if (err == X509_V_ERR_HOSTNAME_MISMATCH || err == X509_V_ERR_IP_ADDRESS_MISMATCH)
            fail(t, errSecHostNameMismatch, why);
        else
            fail(t, errSecNotTrusted, why);
    }
    if (others)
        X.OPENSSL_sk_free(others);
    for (NSValue *v in parsed)
        X.X509_free([v pointerValue]);
    if (ctx)
        X.X509_STORE_CTX_free(ctx);
    if (store)
        X.X509_STORE_free(store);
}

S_EXPORT bool SecTrustEvaluateWithError(SecTrustRef trust, CFErrorRef *error)
{
    STrust *t = trust_of(trust);
    if (error)
        *error = NULL;
    if (!t) {
        if (error)
            *error = (CFErrorRef)SCopyError(errSecParam, nil);
        return false;
    }
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    bool trusted;
    @synchronized(t) {
        evaluate(t);
        trusted = t->trusted;
        if (error && !trusted)
            *error = (CFErrorRef)[t->error retain];
    }
    [pool drain];
    return trusted;
}

S_EXPORT OSStatus SecTrustEvaluate(SecTrustRef trust, SecTrustResultType *result)
{
    STrust *t = trust_of(trust);
    if (!t)
        return errSecParam;
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    @synchronized(t) {
        evaluate(t);
        if (result)
            *result = t->result;
    }
    [pool drain];
    return errSecSuccess;
}

S_EXPORT OSStatus SecTrustEvaluateAsyncWithError(SecTrustRef trust, dispatch_queue_t queue,
                                                 void (^result)(SecTrustRef trust, bool trusted, CFErrorRef error))
{
    STrust *t = trust_of(trust);
    if (!t || !queue || !result)
        return errSecParam;
    id ref = (id)trust;
    dispatch_async(queue, ^{
      CFErrorRef error = NULL;
      bool trusted = SecTrustEvaluateWithError((SecTrustRef)ref, &error);
      result((SecTrustRef)ref, trusted, error);
      if (error)
          CFRelease(error);
    });
    return errSecSuccess;
}

S_EXPORT OSStatus SecTrustGetTrustResult(SecTrustRef trust, SecTrustResultType *result)
{
    STrust *t = trust_of(trust);
    if (!t || !result)
        return errSecParam;
    @synchronized(t) {
        *result = t->evaluated ? t->result : kSecTrustResultInvalid;
    }
    return errSecSuccess;
}

/* The chain, evaluated first if need be; the trust keeps it until it is changed. */
static NSArray *chain_of(SecTrustRef trust)
{
    STrust *t = trust_of(trust);
    if (!t)
        return nil;
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    NSArray *chain;
    @synchronized(t) {
        evaluate(t);
        chain = t->chain;
    }
    [pool drain];
    return chain;
}

S_EXPORT CFIndex SecTrustGetCertificateCount(SecTrustRef trust)
{
    return (CFIndex)[chain_of(trust) count];
}

S_EXPORT SecCertificateRef SecTrustGetCertificateAtIndex(SecTrustRef trust, CFIndex ix)
{
    NSArray *chain = chain_of(trust);
    return ix >= 0 && (NSUInteger)ix < [chain count] ? (SecCertificateRef)[chain objectAtIndex:(NSUInteger)ix] : NULL;
}

S_EXPORT CFArrayRef SecTrustCopyCertificateChain(SecTrustRef trust)
{
    NSArray *chain = chain_of(trust);
    return chain ? (CFArrayRef)[chain copy] : NULL;
}
