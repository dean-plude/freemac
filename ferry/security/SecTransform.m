/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's Security framework: importing public keys and the transforms
 * that check a signature (freemac 1.223, Ferry 0.47.0). Our own code,
 * written from Apple's public API documentation of SecImportExport.h,
 * SecTransform.h, SecReadTransform.h, SecDigestTransform.h and
 * SecSignVerifyTransform.h, and from OpenSSL's published API documentation
 * for the calls into this system's libcrypto.
 *
 * A key is kept as its SubjectPublicKeyInfo in DER, which libcrypto reads
 * when a signature is checked. A transform is an object with its
 * attributes and the transform its input comes from; a group remembers its
 * members, and executing it runs the one whose output goes nowhere,
 * pulling each input in turn: a read transform reads its stream whole, a
 * digest transform hashes its input (CommonCrypto), and a verify transform
 * checks its signature against the input, a digest when the input is one
 * (kSecInputIsDigest, or connected from a digest transform) and otherwise
 * the data, hashed with SHA-1 first as a Mac does by default. A Mac runs a
 * group's transforms concurrently and streams the data through them; here
 * they run in turn on the whole data, which gives the same answer. Signing
 * isn't done: SecSignTransformCreate answers NULL with an error. */
#include "SInternal.h"
#include <string.h>

/* ---- libcrypto, from OpenSSL's published API documentation -------------------------- */

typedef void BIO, EVP_PKEY, EVP_PKEY_CTX, EVP_MD;
static struct {
    BIO *(*BIO_new_mem_buf)(const void *, int);
    int (*BIO_free)(BIO *);
    EVP_PKEY *(*PEM_read_bio_PUBKEY)(BIO *, EVP_PKEY **, void *, void *);
    EVP_PKEY *(*d2i_PUBKEY)(EVP_PKEY **, const unsigned char **, long);
    int (*i2d_PUBKEY)(EVP_PKEY *, unsigned char **);
    void (*EVP_PKEY_free)(EVP_PKEY *);
    EVP_PKEY_CTX *(*EVP_PKEY_CTX_new)(EVP_PKEY *, void *);
    void (*EVP_PKEY_CTX_free)(EVP_PKEY_CTX *);
    int (*EVP_PKEY_verify_init)(EVP_PKEY_CTX *);
    int (*EVP_PKEY_verify)(EVP_PKEY_CTX *, const unsigned char *, size_t, const unsigned char *, size_t);
    int (*EVP_PKEY_CTX_ctrl)(EVP_PKEY_CTX *, int, int, int, int, void *);
    int (*EVP_PKEY_CTX_set_signature_md)(EVP_PKEY_CTX *, const EVP_MD *); /* OpenSSL 3 */
    const EVP_MD *(*EVP_md5)(void);
    const EVP_MD *(*EVP_sha1)(void);
    const EVP_MD *(*EVP_sha224)(void);
    const EVP_MD *(*EVP_sha256)(void);
    const EVP_MD *(*EVP_sha384)(void);
    const EVP_MD *(*EVP_sha512)(void);
} X;
/* OpenSSL 1.1's EVP_PKEY_CTX_set_signature_md is this control */
#define EVP_PKEY_OP_TYPE_SIG 0xf8
#define EVP_PKEY_CTRL_MD 1

static BOOL crypto(void)
{
    static int state; /* 0 not tried, 1 found, -1 missing */
    @synchronized([NSObject class]) {
        if (!state) {
            state = 1;
#define CALL(name) if (!(*(void **)&X.name = ferry_crypto_symbol(#name))) state = -1;
            CALL(BIO_new_mem_buf) CALL(BIO_free) CALL(PEM_read_bio_PUBKEY) CALL(d2i_PUBKEY) CALL(i2d_PUBKEY)
            CALL(EVP_PKEY_free) CALL(EVP_PKEY_CTX_new) CALL(EVP_PKEY_CTX_free) CALL(EVP_PKEY_verify_init)
            CALL(EVP_PKEY_verify) CALL(EVP_PKEY_CTX_ctrl) CALL(EVP_md5) CALL(EVP_sha1) CALL(EVP_sha224)
            CALL(EVP_sha256) CALL(EVP_sha384) CALL(EVP_sha512)
#undef CALL
            *(void **)&X.EVP_PKEY_CTX_set_signature_md = ferry_crypto_symbol("EVP_PKEY_CTX_set_signature_md");
            if (state < 0)
                SVerboseOnce(@"this system's OpenSSL (libcrypto) was not found: keys can't be read");
        }
    }
    return state > 0;
}

/* ---- keys ------------------------------------------------------------------------------ */

#define FERRY_TYPE_SECKEY 0x46520041
#define FERRY_TYPE_SECTRANSFORM 0x46520042

@interface SKey : NSObject {
@public
    NSData *spki; /* SubjectPublicKeyInfo, DER */
}
@end
@implementation SKey
- (void)dealloc
{
    [spki release];
    [super dealloc];
}
- (CFTypeID)_ferryCFTypeID { return FERRY_TYPE_SECKEY; }
- (BOOL)isEqual:(id)other { return [other isKindOfClass:[SKey class]] && [((SKey *)other)->spki isEqual:spki]; }
- (NSUInteger)hash { return [spki hash]; }
- (NSString *)description { return [NSString stringWithFormat:@"<SecKey %p public>", self]; }
@end

S_EXPORT CFTypeID SecKeyGetTypeID(void) { return FERRY_TYPE_SECKEY; }

static void set_error(CFErrorRef *out, CFIndex code, NSString *message)
{
    if (out && !*out)
        *out = (CFErrorRef)[[NSError alloc] initWithDomain:(NSString *)kSecTransformErrorDomain code:code
                                                  userInfo:@{NSLocalizedDescriptionKey : message}];
}

/* The key in data (PEM or DER), as an EVP_PKEY, or NULL. */
static EVP_PKEY *read_key(NSData *data)
{
    const unsigned char *bytes = [data bytes];
    size_t n = [data length];
    if (n > 10 && memmem(bytes, n, "-----BEGIN", 10)) {
        BIO *b = X.BIO_new_mem_buf(bytes, (int)n);
        EVP_PKEY *k = b ? X.PEM_read_bio_PUBKEY(b, NULL, NULL, NULL) : NULL;
        if (b)
            X.BIO_free(b);
        return k;
    }
    const unsigned char *p = bytes;
    EVP_PKEY *k = X.d2i_PUBKEY(NULL, &p, (long)n);
    if (k && p != bytes + n) {
        X.EVP_PKEY_free(k);
        return NULL;
    }
    return k;
}

S_EXPORT OSStatus SecItemImport(CFDataRef importedData, CFStringRef fileNameOrExtension, SecExternalFormat *inputFormat,
                                SecExternalItemType *itemType, SecItemImportExportFlags flags,
                                const SecItemImportExportKeyParameters *keyParams, SecKeychainRef importKeychain,
                                CFArrayRef *outItems)
{
    if (outItems)
        *outItems = NULL;
    NSData *data = (NSData *)importedData;
    if (![data isKindOfClass:[NSData class]] || ![data length])
        return errSecParam;
    SecExternalFormat format = inputFormat ? *inputFormat : kSecFormatUnknown;
    SecExternalItemType type = itemType ? *itemType : kSecItemTypeUnknown;
    if ((format != kSecFormatUnknown && format != kSecFormatOpenSSL && format != kSecFormatPEMSequence &&
         format != kSecFormatBSAFE) ||
        (type != kSecItemTypeUnknown && type != kSecItemTypePublicKey))
        return errSecUnsupportedFormat;
    if (!crypto())
        return errSecUnimplemented;
    EVP_PKEY *k = read_key(data);
    if (!k)
        return errSecUnknownFormat;
    int n = X.i2d_PUBKEY(k, NULL);
    NSMutableData *der = n > 0 ? [NSMutableData dataWithLength:(NSUInteger)n] : nil;
    unsigned char *p = [der mutableBytes];
    BOOL ok = der && X.i2d_PUBKEY(k, &p) == n;
    X.EVP_PKEY_free(k);
    if (!ok)
        return errSecDecode;
    SKey *key = [[SKey alloc] init];
    key->spki = [der copy];
    if (inputFormat)
        *inputFormat = kSecFormatOpenSSL;
    if (itemType)
        *itemType = kSecItemTypePublicKey;
    if (outItems)
        *outItems = (CFArrayRef)[[NSArray alloc] initWithObjects:key, nil];
    [key release];
    return errSecSuccess;
}

S_EXPORT CFDataRef SecKeyCopyExternalRepresentation(SecKeyRef key, CFErrorRef *error)
{
    if (![(id)key isKindOfClass:[SKey class]]) {
        set_error(error, kSecTransformInvalidArgument, @"Not a key.");
        return NULL;
    }
    return (CFDataRef)[((SKey *)key)->spki copy];
}

/* ---- transforms ------------------------------------------------------------------------- */

#define K(name, value) S_EXPORT const CFStringRef name = (CFStringRef)@value;
K(kSecTransformErrorDomain, "com.apple.security.transforms.error")
K(kSecTransformInputAttributeName, "INPUT")
K(kSecTransformOutputAttributeName, "OUTPUT")
K(kSecTransformDebugAttributeName, "DEBUG")
K(kSecTransformTransformName, "NAME")
K(kSecTransformAbortAttributeName, "ABORT")
K(kSecDigestMD5, "MD5")
K(kSecDigestSHA1, "SHA1")
K(kSecDigestSHA2, "SHA2")
K(kSecDigestTypeAttribute, "DigestType")
K(kSecDigestLengthAttribute, "DigestLength")
K(kSecDigestHMACKeyAttribute, "HMACKey")
K(kSecKeyAttributeName, "KEY")
K(kSecSignatureAttributeName, "Signature")
K(kSecInputIsAttributeName, "InputIs")
K(kSecInputIsPlainText, "PlainText")
K(kSecInputIsDigest, "Digest")
K(kSecInputIsRaw, "Raw")
#undef K

typedef enum { T_GROUP, T_READ, T_DIGEST, T_VERIFY } TKind;

@interface STransform : NSObject {
@public
    TKind kind;
    NSMutableDictionary *attributes;
    STransform *input;        /* the transform whose output is our input, not retained (the group holds it) */
    NSMutableArray *members;  /* a group's */
    BOOL consumed;            /* its output goes to another transform */
}
@end
@implementation STransform
- (instancetype)init
{
    if ((self = [super init]))
        attributes = [[NSMutableDictionary alloc] init];
    return self;
}
- (void)dealloc
{
    [attributes release];
    [members release];
    [super dealloc];
}
- (CFTypeID)_ferryCFTypeID { return FERRY_TYPE_SECTRANSFORM; }
- (NSString *)description
{
    static const char *names[] = {"group", "read", "digest", "verify"};
    return [NSString stringWithFormat:@"<SecTransform %p %s>", self, names[kind]];
}
@end

S_EXPORT CFTypeID SecTransformGetTypeID(void) { return FERRY_TYPE_SECTRANSFORM; }

static STransform *new_transform(TKind kind)
{
    STransform *t = [[STransform alloc] init];
    t->kind = kind;
    if (kind == T_GROUP)
        t->members = [[NSMutableArray alloc] init];
    return t;
}

static STransform *as_transform(CFTypeRef ref)
{
    return [(id)ref isKindOfClass:[STransform class]] ? (STransform *)ref : nil;
}

S_EXPORT SecGroupTransformRef SecTransformCreateGroupTransform(void) { return new_transform(T_GROUP); }

S_EXPORT SecTransformRef SecTransformCreateReadTransformWithReadStream(CFReadStreamRef inputStream)
{
    if (![(id)inputStream isKindOfClass:[NSInputStream class]])
        return NULL;
    STransform *t = new_transform(T_READ);
    t->attributes[@"stream"] = (id)inputStream;
    return t;
}

static int digest_bits(NSString *type, CFIndex length)
{
    if ([type isEqual:(id)kSecDigestMD5])
        return length == 0 || length == 128 ? 128 : -1;
    if ([type isEqual:(id)kSecDigestSHA1])
        return length == 0 || length == 160 ? 160 : -1;
    if ([type isEqual:(id)kSecDigestSHA2]) {
        if (length == 0)
            return 512;
        return length == 224 || length == 256 || length == 384 || length == 512 ? (int)length : -1;
    }
    return -1;
}

S_EXPORT SecTransformRef SecDigestTransformCreate(CFTypeRef digestType, CFIndex digestLength, CFErrorRef *error)
{
    NSString *type = digestType ? (NSString *)digestType : (NSString *)kSecDigestSHA2;
    int bits = [type isKindOfClass:[NSString class]] ? digest_bits(type, digestLength) : -1;
    if (bits < 0) {
        set_error(error, kSecTransformErrorInvalidAlgorithm,
                  [NSString stringWithFormat:@"%@ with a length of %ld is not a digest Ferry has.", type, (long)digestLength]);
        return NULL;
    }
    STransform *t = new_transform(T_DIGEST);
    t->attributes[(id)kSecDigestTypeAttribute] = type;
    t->attributes[(id)kSecDigestLengthAttribute] = @(bits);
    return t;
}

S_EXPORT SecTransformRef SecVerifyTransformCreate(SecKeyRef key, CFDataRef signature, CFErrorRef *error)
{
    if (![(id)key isKindOfClass:[SKey class]] || ![(id)signature isKindOfClass:[NSData class]]) {
        set_error(error, kSecTransformInvalidArgument, @"A verify transform needs a public key and a signature.");
        return NULL;
    }
    STransform *t = new_transform(T_VERIFY);
    t->attributes[(id)kSecKeyAttributeName] = (id)key;
    t->attributes[(id)kSecSignatureAttributeName] = (id)signature;
    t->attributes[(id)kSecInputIsAttributeName] = (id)kSecInputIsPlainText;
    return t;
}

S_EXPORT SecTransformRef SecSignTransformCreate(SecKeyRef key, CFErrorRef *error)
{
    set_error(error, kSecTransformErrorInvalidOperation, @"Ferry's Security doesn't sign.");
    return NULL;
}

S_EXPORT Boolean SecTransformSetAttribute(SecTransformRef transform, CFStringRef key, CFTypeRef value, CFErrorRef *error)
{
    STransform *t = as_transform(transform);
    if (!t || ![(id)key isKindOfClass:[NSString class]]) {
        set_error(error, kSecTransformInvalidArgument, @"Not a transform and an attribute name.");
        return false;
    }
    if (t->kind == T_GROUP) {
        set_error(error, kSecTransformOperationNotSupportedOnGroup, @"A group has no attributes of its own.");
        return false;
    }
    if (t->kind == T_DIGEST && [(id)key isEqual:(id)kSecDigestTypeAttribute]) {
        int bits = digest_bits((NSString *)value, 0);
        if (bits < 0) {
            set_error(error, kSecTransformErrorInvalidAlgorithm, @"Not a digest Ferry has.");
            return false;
        }
        t->attributes[(id)kSecDigestLengthAttribute] = @(bits);
    }
    if (value)
        t->attributes[(id)key] = (id)value;
    else
        [t->attributes removeObjectForKey:(id)key];
    return true;
}

S_EXPORT CFTypeRef SecTransformGetAttribute(SecTransformRef transform, CFStringRef key)
{
    STransform *t = as_transform(transform);
    return t ? (CFTypeRef)t->attributes[(id)key] : NULL;
}

S_EXPORT SecGroupTransformRef SecTransformConnectTransforms(SecTransformRef sourceTransform,
                                                            CFStringRef sourceAttributeName,
                                                            SecTransformRef destinationTransform,
                                                            CFStringRef destinationAttributeName,
                                                            SecGroupTransformRef group, CFErrorRef *error)
{
    STransform *from = as_transform(sourceTransform), *to = as_transform(destinationTransform);
    STransform *g = as_transform(group);
    if (!from || !to || !g || g->kind != T_GROUP || from == to) {
        set_error(error, kSecTransformErrorInvalidConnection, @"Transforms are connected within a group.");
        return NULL;
    }
    if (![(id)sourceAttributeName isEqual:(id)kSecTransformOutputAttributeName] ||
        ![(id)destinationAttributeName isEqual:(id)kSecTransformInputAttributeName]) {
        set_error(error, kSecTransformErrorUnsupportedAttribute,
                  @"Ferry connects a transform's output to another's input only.");
        return NULL;
    }
    to->input = from;
    from->consumed = YES;
    for (STransform *t in @[ from, to ])
        if (![g->members containsObject:t])
            [g->members addObject:t];
    return group;
}

static NSData *read_all(NSInputStream *stream)
{
    NSMutableData *data = [NSMutableData data];
    if ([stream streamStatus] == NSStreamStatusNotOpen)
        [stream open];
    uint8_t buf[65536];
    for (;;) {
        NSInteger n = [stream read:buf maxLength:sizeof buf];
        if (n < 0)
            return nil;
        if (n == 0)
            break;
        [data appendBytes:buf length:(NSUInteger)n];
    }
    [stream close];
    return data;
}

static NSData *digest(NSData *data, NSString *type, int bits)
{
    NSMutableData *out = [NSMutableData dataWithLength:(NSUInteger)bits / 8];
    const void *b = [data bytes];
    CC_LONG n = (CC_LONG)[data length];
    unsigned char *o = [out mutableBytes];
    if ([type isEqual:(id)kSecDigestMD5])
        CC_MD5(b, n, o);
    else if ([type isEqual:(id)kSecDigestSHA1])
        CC_SHA1(b, n, o);
    else if (bits == 224)
        CC_SHA224(b, n, o);
    else if (bits == 256)
        CC_SHA256(b, n, o);
    else if (bits == 384)
        CC_SHA384(b, n, o);
    else
        CC_SHA512(b, n, o);
    return out;
}

static const EVP_MD *evp_md(NSString *type, int bits)
{
    if ([type isEqual:(id)kSecDigestMD5])
        return X.EVP_md5();
    if ([type isEqual:(id)kSecDigestSHA1])
        return X.EVP_sha1();
    return bits == 224 ? X.EVP_sha224() : bits == 256 ? X.EVP_sha256() : bits == 384 ? X.EVP_sha384() : X.EVP_sha512();
}

/* Whether the signature checks out over the digest, or -1 if it can't be checked. */
static int verify_digest(SKey *key, NSData *signature, NSData *hash, NSString *type, int bits)
{
    if (!crypto())
        return -1;
    const unsigned char *p = [key->spki bytes];
    EVP_PKEY *k = X.d2i_PUBKEY(NULL, &p, (long)[key->spki length]);
    if (!k)
        return -1;
    EVP_PKEY_CTX *ctx = X.EVP_PKEY_CTX_new(k, NULL);
    int result = -1;
    if (ctx && X.EVP_PKEY_verify_init(ctx) > 0) {
        const EVP_MD *md = evp_md(type, bits);
        if (X.EVP_PKEY_CTX_set_signature_md)
            X.EVP_PKEY_CTX_set_signature_md(ctx, md);
        else
            X.EVP_PKEY_CTX_ctrl(ctx, -1, EVP_PKEY_OP_TYPE_SIG, EVP_PKEY_CTRL_MD, 0, (void *)md);
        result = X.EVP_PKEY_verify(ctx, [signature bytes], [signature length], [hash bytes], [hash length]) == 1;
    }
    if (ctx)
        X.EVP_PKEY_CTX_free(ctx);
    X.EVP_PKEY_free(k);
    return result;
}

/* A transform's output, or nil with *error set. */
static id run(STransform *t, CFErrorRef *error, int depth)
{
    if (depth > 64) {
        set_error(error, kSecTransformErrorInvalidConnection, @"The transforms are connected in a loop.");
        return nil;
    }
    id input = nil;
    if (t->kind != T_READ) {
        if (t->input) {
            input = run(t->input, error, depth + 1);
            if (!input)
                return nil;
        } else
            input = t->attributes[(id)kSecTransformInputAttributeName];
        if (![input isKindOfClass:[NSData class]]) {
            set_error(error, kSecTransformErrorMissingParameter, @"The transform has no data for its input.");
            return nil;
        }
    }
    switch (t->kind) {
    case T_READ: {
        NSData *d = read_all(t->attributes[@"stream"]);
        if (!d)
            set_error(error, kSecTransformErrorInvalidInput, @"The stream could not be read.");
        return d;
    }
    case T_DIGEST:
        return digest(input, t->attributes[(id)kSecDigestTypeAttribute],
                      [t->attributes[(id)kSecDigestLengthAttribute] intValue]);
    case T_VERIFY: {
        BOOL isDigest = [t->attributes[(id)kSecInputIsAttributeName] isEqual:(id)kSecInputIsDigest] ||
                        (t->input && t->input->kind == T_DIGEST);
        NSString *type = (NSString *)kSecDigestSHA1;
        int bits = 160;
        if (isDigest && t->input && t->input->kind == T_DIGEST) {
            type = t->input->attributes[(id)kSecDigestTypeAttribute];
            bits = [t->input->attributes[(id)kSecDigestLengthAttribute] intValue];
        } else if (t->attributes[(id)kSecDigestTypeAttribute]) {
            type = t->attributes[(id)kSecDigestTypeAttribute];
            bits = digest_bits(type, [t->attributes[(id)kSecDigestLengthAttribute] integerValue]);
            if (bits < 0) {
                set_error(error, kSecTransformErrorInvalidAlgorithm, @"Not a digest Ferry has.");
                return nil;
            }
        }
        if (isDigest && t->input == nil && !t->attributes[(id)kSecDigestTypeAttribute]) {
            /* a digest given as the input: its length says which */
            NSUInteger n = [input length] * 8;
            if (n == 128)
                type = (NSString *)kSecDigestMD5, bits = 128;
            else if (n != 160)
                type = (NSString *)kSecDigestSHA2, bits = (int)n;
        }
        NSData *hash = isDigest ? input : digest(input, type, bits);
        int ok = verify_digest(t->attributes[(id)kSecKeyAttributeName], t->attributes[(id)kSecSignatureAttributeName],
                               hash, type, bits);
        if (ok < 0) {
            set_error(error, kSecTransformErrorNotInitializedCorrectly,
                      @"The signature can't be checked: this system's OpenSSL (libcrypto) couldn't read the key.");
            return nil;
        }
        return ok ? (id)kCFBooleanTrue : (id)kCFBooleanFalse;
    }
    case T_GROUP:
        break;
    }
    return nil;
}

S_EXPORT CFTypeRef SecTransformExecute(SecTransformRef transform, CFErrorRef *errorRef)
{
    if (errorRef)
        *errorRef = NULL;
    STransform *t = as_transform(transform);
    if (!t) {
        set_error(errorRef, kSecTransformInvalidArgument, @"Not a transform.");
        return NULL;
    }
    if (t->kind == T_GROUP) {
        STransform *last = nil;
        for (STransform *m in t->members)
            if (!m->consumed) {
                if (last) {
                    set_error(errorRef, kSecTransformErrorMoreThanOneOutput, @"The group has more than one output.");
                    return NULL;
                }
                last = m;
            }
        if (!last) {
            set_error(errorRef, kSecTransformErrorNotInitializedCorrectly, @"The group has nothing to run.");
            return NULL;
        }
        t = last;
    }
    @autoreleasepool {
        id result = run(t, errorRef, 0);
        return result ? (CFTypeRef)[result retain] : NULL;
    }
}

S_EXPORT void SecTransformExecuteAsync(SecTransformRef transform, dispatch_queue_t deliveryQueue,
                                       SecMessageBlock deliveryBlock)
{
    CFRetain(transform);
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        CFErrorRef error = NULL;
        CFTypeRef result = SecTransformExecute(transform, &error);
        dispatch_async(deliveryQueue, ^{
            deliveryBlock(result, error, true);
            if (result)
                CFRelease(result);
            if (error)
                CFRelease(error);
            CFRelease(transform);
        });
    });
}
