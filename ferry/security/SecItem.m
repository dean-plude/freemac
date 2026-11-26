/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's Security framework: keychain items. Our own code, written from
 * Apple's public API documentation of Security (SecItem.h, SecKeychain.h,
 * SecKeychainItem.h and the "Keychain Services" guide).
 *
 * Generic passwords (kSecClassGenericPassword) and internet passwords
 * (kSecClassInternetPassword) are kept for the user in
 * $XDG_DATA_HOME/ferry/keychain (~/.local/share/ferry/keychain), a folder
 * only the user can open (mode 0700) holding:
 *
 *   key          64 random bytes (mode 0600), made the first time an item is added;
 *   items.plist  the items (mode 0600): their attributes in the clear, and
 *                each secret as IV, AES-256-CBC ciphertext (PKCS#7) and an
 *                HMAC-SHA256 over the item's id, the IV and the ciphertext,
 *                with keys from the file above;
 *   lock         locked (flock) while a call reads or writes the items, so
 *                two programs don't lose each other's changes.
 *
 * The encryption keeps a secret from being read by accident (in a backup
 * listing, a grep or a glance at the file); it does not protect it from
 * anyone who can read the user's files, programs the user runs included,
 * because the key is in the same folder. A Mac's keychain is unlocked with
 * the user's login and asks before another app reads an item; Ferry does
 * neither: every program the user runs can read and change every item.
 * Access groups are kept and matched as plain attributes. Nothing is ever
 * synchronized: kSecAttrSynchronizable is kept and matched, no more.
 *
 * Keys and attribute names: an attribute that the older keychain calls
 * also name (account, service, server...) is stored under that call's
 * four-letter tag ("acct", "svce", "srvr"...), so both sets of calls see
 * the same items; every other key's value is its own name. */
#include "SInternal.h"
#include <dispatch/dispatch.h>
#include <errno.h>
#include <fcntl.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

int flock(int fd, int operation); /* the same call and values on a Mac and on Linux */
#define LOCK_EX 2
#define LOCK_UN 8

#define K(name, value) S_EXPORT const CFStringRef name = (CFStringRef)@value;
K(kSecClass, "kSecClass")
K(kSecClassGenericPassword, "genp")
K(kSecClassInternetPassword, "inet")
K(kSecClassCertificate, "cert")
K(kSecClassKey, "keys")
K(kSecClassIdentity, "idnt")
K(kSecAttrAccessible, "pdmn")
K(kSecAttrAccessGroup, "agrp")
K(kSecAttrSynchronizable, "sync")
K(kSecAttrSynchronizableAny, "kSecAttrSynchronizableAny")
K(kSecAttrCreationDate, "cdat")
K(kSecAttrModificationDate, "mdat")
K(kSecAttrDescription, "desc")
K(kSecAttrComment, "icmt")
K(kSecAttrCreator, "crtr")
K(kSecAttrType, "type")
K(kSecAttrLabel, "labl")
K(kSecAttrIsInvisible, "invi")
K(kSecAttrIsNegative, "nega")
K(kSecAttrAccount, "acct")
K(kSecAttrService, "svce")
K(kSecAttrGeneric, "gena")
K(kSecAttrSecurityDomain, "sdmn")
K(kSecAttrServer, "srvr")
K(kSecAttrProtocol, "ptcl")
K(kSecAttrAuthenticationType, "atyp")
K(kSecAttrPort, "port")
K(kSecAttrPath, "path")
K(kSecAttrAccessibleWhenUnlocked, "kSecAttrAccessibleWhenUnlocked")
K(kSecAttrAccessibleAfterFirstUnlock, "kSecAttrAccessibleAfterFirstUnlock")
K(kSecAttrAccessibleWhenUnlockedThisDeviceOnly, "kSecAttrAccessibleWhenUnlockedThisDeviceOnly")
K(kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly, "kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly")
K(kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly, "kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly")
/* the protocols and authentication types are the older calls' four-letter codes */
K(kSecAttrProtocolFTP, "ftp ")
K(kSecAttrProtocolFTPAccount, "ftpa")
K(kSecAttrProtocolFTPS, "ftps")
K(kSecAttrProtocolFTPProxy, "ftpx")
K(kSecAttrProtocolHTTP, "http")
K(kSecAttrProtocolHTTPS, "htps")
K(kSecAttrProtocolHTTPProxy, "htpx")
K(kSecAttrProtocolHTTPSProxy, "htsx")
K(kSecAttrProtocolSSH, "ssh ")
K(kSecAttrProtocolSMTP, "smtp")
K(kSecAttrProtocolIMAP, "imap")
K(kSecAttrProtocolIMAPS, "imps")
K(kSecAttrProtocolPOP3, "pop3")
K(kSecAttrProtocolLDAP, "ldap")
K(kSecAttrProtocolSOCKS, "sox ")
K(kSecAttrProtocolAFP, "afp ")
K(kSecAttrProtocolSMB, "smb ")
K(kSecAttrAuthenticationTypeDefault, "dflt")
K(kSecAttrAuthenticationTypeHTTPBasic, "http")
K(kSecAttrAuthenticationTypeHTTPDigest, "httd")
K(kSecAttrAuthenticationTypeHTMLForm, "form")
K(kSecAttrAuthenticationTypeNTLM, "ntlm")
K(kSecMatchLimit, "kSecMatchLimit")
K(kSecMatchLimitOne, "kSecMatchLimitOne")
K(kSecMatchLimitAll, "kSecMatchLimitAll")
K(kSecMatchCaseInsensitive, "kSecMatchCaseInsensitive")
K(kSecReturnData, "kSecReturnData")
K(kSecReturnAttributes, "kSecReturnAttributes")
K(kSecReturnRef, "kSecReturnRef")
K(kSecReturnPersistentRef, "kSecReturnPersistentRef")
K(kSecValueData, "kSecValueData")
K(kSecValueRef, "kSecValueRef")
K(kSecValuePersistentRef, "kSecValuePersistentRef")
K(kSecUseDataProtectionKeychain, "kSecUseDataProtectionKeychain")
K(kSecUseKeychain, "kSecUseKeychain")
K(kSecUseAuthenticationUI, "kSecUseAuthenticationUI")
K(kSecUseOperationPrompt, "kSecUseOperationPrompt")
#undef K

/* ---- the attributes ------------------------------------------------------------------- */

enum { A_STRING, A_NUMBER, A_BOOL, A_DATA, A_DATE };
enum { C_GENP = 1, C_INET = 2, C_BOTH = 3 };
static const struct attr {
    const char *tag;
    int type, classes, primary; /* primary: part of what makes an item unique in its classes */
} attrs[] = {
    {"acct", A_STRING, C_BOTH, C_BOTH},
    {"svce", A_STRING, C_GENP, C_GENP},
    {"gena", A_DATA, C_GENP, 0},
    {"sdmn", A_STRING, C_INET, C_INET},
    {"srvr", A_STRING, C_INET, C_INET},
    {"ptcl", A_STRING, C_INET, C_INET},
    {"atyp", A_STRING, C_INET, C_INET},
    {"port", A_NUMBER, C_INET, C_INET},
    {"path", A_STRING, C_INET, C_INET},
    {"agrp", A_STRING, C_BOTH, C_BOTH},
    {"labl", A_STRING, C_BOTH, 0},
    {"icmt", A_STRING, C_BOTH, 0},
    {"desc", A_STRING, C_BOTH, 0},
    {"pdmn", A_STRING, C_BOTH, 0},
    {"crtr", A_NUMBER, C_BOTH, 0},
    {"type", A_NUMBER, C_BOTH, 0},
    {"invi", A_BOOL, C_BOTH, 0},
    {"nega", A_BOOL, C_BOTH, 0},
    {"cdat", A_DATE, C_BOTH, 0},
    {"mdat", A_DATE, C_BOTH, 0},
};

static const struct attr *find_attr(NSString *key)
{
    if (![key isKindOfClass:[NSString class]])
        return NULL;
    const char *k = [key UTF8String];
    for (size_t i = 0; i < sizeof attrs / sizeof attrs[0]; i++)
        if (!strcmp(attrs[i].tag, k))
            return &attrs[i];
    return NULL;
}

static BOOL value_fits(const struct attr *a, id v)
{
    switch (a->type) {
    case A_STRING: return [v isKindOfClass:[NSString class]];
    case A_NUMBER:
    case A_BOOL: return [v isKindOfClass:[NSNumber class]];
    case A_DATA: return [v isKindOfClass:[NSData class]];
    case A_DATE: return [v isKindOfClass:[NSDate class]];
    }
    return NO;
}

static int class_bit(NSString *cls)
{
    if ([cls isEqual:(id)kSecClassGenericPassword])
        return C_GENP;
    if ([cls isEqual:(id)kSecClassInternetPassword])
        return C_INET;
    return 0;
}

/* The keys a query, an item to add or the changes to make may hold besides attributes. */
static BOOL known_other_key(id key)
{
    static NSSet *keys;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
      keys = [[NSSet setWithObjects:(id)kSecClass, (id)kSecAttrSynchronizable, (id)kSecMatchLimit,
                                              (id)kSecMatchCaseInsensitive, (id)kSecReturnData,
                                              (id)kSecReturnAttributes, (id)kSecReturnRef,
                                              (id)kSecReturnPersistentRef, (id)kSecValueData, (id)kSecValueRef,
                                              (id)kSecValuePersistentRef, (id)kSecUseDataProtectionKeychain,
                                              (id)kSecUseKeychain, (id)kSecUseAuthenticationUI,
                                              (id)kSecUseOperationPrompt, nil] retain];
    });
    return [keys containsObject:key];
}

enum { Q_ADD, Q_FIND, Q_UPDATE, Q_DELETE };
struct query {
    int cls;                   /* C_GENP, C_INET, or 0 for a class Ferry doesn't keep */
    NSMutableDictionary *attrs;
    int sync;                  /* 0: only items that aren't synchronizable, 1: only those that are, 2: any */
    BOOL returnData, returnAttrs, returnRef, returnPersistent, caseInsensitive;
    NSInteger limit;
    NSData *data;
    NSString *uuid;            /* kSecValueRef or kSecValuePersistentRef */
};

static NSData *persistent_ref(NSString *uuid)
{
    return [[@"ferry-keychain:" stringByAppendingString:uuid] dataUsingEncoding:NSUTF8StringEncoding];
}

static NSString *uuid_of_persistent_ref(id v)
{
    if (![v isKindOfClass:[NSData class]])
        return nil;
    NSString *s = [[[NSString alloc] initWithData:v encoding:NSUTF8StringEncoding] autorelease];
    return [s hasPrefix:@"ferry-keychain:"] ? [s substringFromIndex:15] : nil;
}

/* Reads a dictionary from a caller: errSecParam for a value of the wrong
 * type, errSecNoSuchAttr for another class's attribute. */
static OSStatus parse(NSDictionary *d, int purpose, struct query *q)
{
    memset(q, 0, sizeof *q);
    q->attrs = [NSMutableDictionary dictionary];
    q->limit = 1;
    if (![d isKindOfClass:[NSDictionary class]])
        return errSecParam;
    if (purpose != Q_UPDATE) {
        id cls = [d objectForKey:(id)kSecClass];
        if (![cls isKindOfClass:[NSString class]])
            return errSecParam;
        q->cls = class_bit(cls);
        if (!q->cls && ![cls isEqual:(id)kSecClassCertificate] && ![cls isEqual:(id)kSecClassKey] &&
            ![cls isEqual:(id)kSecClassIdentity])
            return errSecParam;
    } else if ([d objectForKey:(id)kSecClass]) {
        return errSecParam;
    }
    for (id key in d) {
        id v = [d objectForKey:key];
        const struct attr *a = find_attr(key);
        if (a) {
            if (!value_fits(a, v))
                return errSecParam;
            if (q->cls && !(a->classes & q->cls))
                return errSecNoSuchAttr;
            [q->attrs setObject:v forKey:key];
        } else if ([key isEqual:(id)kSecAttrSynchronizable]) {
            if ([v isEqual:(id)kSecAttrSynchronizableAny] && purpose != Q_ADD)
                q->sync = 2;
            else if ([v isKindOfClass:[NSNumber class]])
                q->sync = [v boolValue];
            else
                return errSecParam;
        } else if ([key isEqual:(id)kSecMatchLimit]) {
            if (purpose == Q_ADD || purpose == Q_UPDATE)
                return errSecParam;
            if ([v isEqual:(id)kSecMatchLimitAll])
                q->limit = NSIntegerMax;
            else if ([v isEqual:(id)kSecMatchLimitOne])
                q->limit = 1;
            else if ([v isKindOfClass:[NSNumber class]] && [v integerValue] > 0)
                q->limit = [v integerValue];
            else
                return errSecParam;
        } else if ([key isEqual:(id)kSecMatchCaseInsensitive]) {
            q->caseInsensitive = SIsTrue(v);
        } else if ([key isEqual:(id)kSecReturnData] || [key isEqual:(id)kSecReturnAttributes] ||
                   [key isEqual:(id)kSecReturnRef] || [key isEqual:(id)kSecReturnPersistentRef]) {
            if (purpose == Q_UPDATE || purpose == Q_DELETE)
                return errSecParam;
            BOOL on = SIsTrue(v);
            if ([key isEqual:(id)kSecReturnData])
                q->returnData = on;
            else if ([key isEqual:(id)kSecReturnAttributes])
                q->returnAttrs = on;
            else if ([key isEqual:(id)kSecReturnRef])
                q->returnRef = on;
            else
                q->returnPersistent = on;
        } else if ([key isEqual:(id)kSecValueData]) {
            if (![v isKindOfClass:[NSData class]])
                return errSecParam;
            q->data = v;
        } else if ([key isEqual:(id)kSecValueRef]) {
            if (![v isKindOfClass:[SItem class]])
                return errSecParam;
            q->uuid = ((SItem *)v)->uuid;
        } else if ([key isEqual:(id)kSecValuePersistentRef]) {
            q->uuid = uuid_of_persistent_ref(v);
            if (!q->uuid)
                return errSecParam;
        } else if (!known_other_key(key)) {
            SVerboseOnce([NSString stringWithFormat:@"a keychain query's key %@ is not kept or matched", key]);
        }
    }
    if (purpose == Q_UPDATE && (q->uuid || q->sync == 2))
        return errSecParam;
    return errSecSuccess;
}

/* ---- the store ------------------------------------------------------------------------ */

@implementation SItem
- (void)dealloc
{
    [uuid release];
    [itemClass release];
    [super dealloc];
}
- (BOOL)isEqual:(id)other
{
    return [other isKindOfClass:[SItem class]] && [uuid isEqual:((SItem *)other)->uuid];
}
- (NSUInteger)hash { return [uuid hash]; }
- (NSString *)description { return [NSString stringWithFormat:@"<SecKeychainItem %p %@>", self, itemClass]; }
@end

struct store {
    int lock;
    NSString *dir;
    NSData *key;                /* 32 bytes for AES, then 32 for HMAC */
    NSMutableArray *items;      /* of NSMutableDictionary: id, class, attributes, secret */
};

static NSString *keychain_dir(void)
{
    NSArray *a = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES);
    if (![a count])
        return nil;
    return [[[a objectAtIndex:0] stringByAppendingPathComponent:@"ferry"] stringByAppendingPathComponent:@"keychain"];
}

static BOOL write_file(NSString *path, NSData *data, BOOL exclusive)
{
    int fd = open([path fileSystemRepresentation], O_WRONLY | O_CREAT | O_CLOEXEC | (exclusive ? O_EXCL : O_TRUNC), 0600);
    if (fd < 0)
        return NO;
    fchmod(fd, 0600);
    const char *p = [data bytes];
    size_t left = [data length];
    while (left) {
        ssize_t n = write(fd, p, left);
        if (n < 0 && errno == EINTR)
            continue;
        if (n <= 0) {
            close(fd);
            return NO;
        }
        p += n, left -= (size_t)n;
    }
    BOOL ok = fsync(fd) == 0;
    return close(fd) == 0 && ok;
}

static void store_close(struct store *s)
{
    if (s->lock >= 0) {
        flock(s->lock, LOCK_UN);
        close(s->lock);
    }
    s->lock = -1;
    [s->items release];
    s->items = nil;
    [s->key release];
    s->key = nil;
}

/* Locks the store and reads it. With create, makes the folder and the key
 * if need be; without, a missing folder is an empty store. */
static OSStatus store_open(struct store *s, BOOL create)
{
    s->lock = -1;
    s->key = nil;
    s->items = [[NSMutableArray alloc] init];
    s->dir = keychain_dir();
    if (!s->dir)
        return errSecNotAvailable;
    const char *dir = [s->dir fileSystemRepresentation];
    if (create) {
        [[NSFileManager defaultManager] createDirectoryAtPath:[s->dir stringByDeletingLastPathComponent]
                                  withIntermediateDirectories:YES attributes:nil error:NULL];
        if (mkdir(dir, 0700) != 0 && errno != EEXIST)
            return errSecNotAvailable;
        chmod(dir, 0700);
    }
    s->lock = open([[s->dir stringByAppendingPathComponent:@"lock"] fileSystemRepresentation],
                   O_RDWR | O_CREAT | O_CLOEXEC, 0600);
    if (s->lock < 0)
        return create ? errSecNotAvailable : errSecSuccess;
    while (flock(s->lock, LOCK_EX) != 0)
        if (errno != EINTR)
            return errSecIO;

    NSString *keyPath = [s->dir stringByAppendingPathComponent:@"key"];
    s->key = [[NSData alloc] initWithContentsOfFile:keyPath];
    if (!s->key && create) {
        uint8_t k[64];
        if (CCRandomGenerateBytes(k, sizeof k) != kCCSuccess)
            return errSecInternalComponent;
        NSData *d = [NSData dataWithBytes:k length:sizeof k];
        memset(k, 0, sizeof k);
        if (!write_file(keyPath, d, YES))
            return errSecIO;
        s->key = [d retain];
    }
    if (s->key && [s->key length] != 64)
        return errSecInvalidKeychain;

    NSData *file = [NSData dataWithContentsOfFile:[s->dir stringByAppendingPathComponent:@"items.plist"]];
    if (file) {
        id plist = [NSPropertyListSerialization propertyListWithData:file options:NSPropertyListMutableContainers
                                                              format:NULL error:NULL];
        NSArray *items = [plist isKindOfClass:[NSDictionary class]] ? [plist objectForKey:@"Items"] : nil;
        if (![items isKindOfClass:[NSArray class]])
            return errSecInvalidKeychain;
        for (id item in items)
            if ([item isKindOfClass:[NSDictionary class]] &&
                [[item objectForKey:@"attributes"] isKindOfClass:[NSDictionary class]])
                [s->items addObject:[[item mutableCopy] autorelease]];
    }
    return errSecSuccess;
}

static OSStatus store_save(struct store *s)
{
    NSDictionary *plist = [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:1], @"Version",
                                                                      s->items, @"Items", nil];
    NSData *d = [NSPropertyListSerialization dataWithPropertyList:plist format:NSPropertyListXMLFormat_v1_0
                                                          options:0 error:NULL];
    if (!d)
        return errSecInternalComponent;
    NSString *path = [s->dir stringByAppendingPathComponent:@"items.plist"];
    NSString *tmp = [path stringByAppendingString:@".new"];
    unlink([tmp fileSystemRepresentation]);
    if (!write_file(tmp, d, YES) || rename([tmp fileSystemRepresentation], [path fileSystemRepresentation]) != 0) {
        unlink([tmp fileSystemRepresentation]);
        return errSecIO;
    }
    return errSecSuccess;
}

/* ---- secrets ---------------------------------------------------------------------------- */

static void mac_of(struct store *s, NSString *uuid, const uint8_t *iv, const uint8_t *ct, size_t len, uint8_t out[32])
{
    CCHmacContext h;
    const char *u = [uuid UTF8String];
    CCHmacInit(&h, kCCHmacAlgSHA256, (const uint8_t *)[s->key bytes] + 32, 32);
    CCHmacUpdate(&h, u, strlen(u));
    CCHmacUpdate(&h, iv, 16);
    CCHmacUpdate(&h, ct, len);
    CCHmacFinal(&h, out);
}

static NSData *seal(struct store *s, NSString *uuid, NSData *plain)
{
    size_t room = [plain length] + 16, moved = 0;
    uint8_t *out = malloc(16 + room + 32);
    if (!out || CCRandomGenerateBytes(out, 16) != kCCSuccess ||
        CCCrypt(kCCEncrypt, kCCAlgorithmAES, kCCOptionPKCS7Padding, [s->key bytes], kCCKeySizeAES256, out,
                [plain bytes], [plain length], out + 16, room, &moved) != kCCSuccess) {
        free(out);
        return nil;
    }
    mac_of(s, uuid, out, out + 16, moved, out + 16 + moved);
    return [NSData dataWithBytesNoCopy:out length:16 + moved + 32 freeWhenDone:YES];
}

static NSData *open_secret(struct store *s, NSDictionary *item)
{
    NSData *sealed = [item objectForKey:@"secret"];
    NSString *uuid = [item objectForKey:@"id"];
    if (![sealed isKindOfClass:[NSData class]] || ![uuid isKindOfClass:[NSString class]] || !s->key)
        return nil;
    const uint8_t *b = [sealed bytes];
    size_t n = [sealed length];
    if (n < 16 + 16 + 32 || (n - 48) % 16)
        return nil;
    uint8_t mac[32];
    mac_of(s, uuid, b, b + 16, n - 48, mac);
    uint8_t diff = 0;
    for (int i = 0; i < 32; i++)
        diff |= mac[i] ^ b[n - 32 + i];
    if (diff)
        return nil;
    size_t moved = 0;
    uint8_t *out = malloc(n - 48);
    if (!out || CCCrypt(kCCDecrypt, kCCAlgorithmAES, kCCOptionPKCS7Padding, [s->key bytes], kCCKeySizeAES256, b,
                        b + 16, n - 48, out, n - 48, &moved) != kCCSuccess) {
        free(out);
        return nil;
    }
    return [NSData dataWithBytesNoCopy:out length:moved freeWhenDone:YES];
}

/* ---- matching --------------------------------------------------------------------------- */

static int item_class(NSDictionary *item) { return class_bit([item objectForKey:@"class"]); }

/* An attribute's value, or what a missing one counts as when items are compared. */
static id value_or_default(NSDictionary *attributes, const struct attr *a)
{
    id v = [attributes objectForKey:[NSString stringWithUTF8String:a->tag]];
    if (v || !a->primary)
        return v;
    return a->type == A_NUMBER ? (id)[NSNumber numberWithInt:0] : (id)@"";
}

static BOOL same(id a, id b, BOOL caseInsensitive)
{
    if (caseInsensitive && [a isKindOfClass:[NSString class]] && [b isKindOfClass:[NSString class]])
        return [a caseInsensitiveCompare:b] == NSOrderedSame;
    return [a isEqual:b];
}

static BOOL matches(NSDictionary *item, const struct query *q, int cls)
{
    if (item_class(item) != cls)
        return NO;
    if (q->uuid && ![q->uuid isEqual:[item objectForKey:@"id"]])
        return NO;
    NSDictionary *at = [item objectForKey:@"attributes"];
    BOOL synced = SIsTrue([at objectForKey:@"sync"]);
    if (q->sync != 2 && synced != (q->sync == 1))
        return NO;
    for (NSString *key in q->attrs) {
        id have = value_or_default(at, find_attr(key));
        if (!have || !same(have, [q->attrs objectForKey:key], q->caseInsensitive))
            return NO;
    }
    return YES;
}

/* Whether two items of a class would be the same item. */
static BOOL same_primary_key(NSDictionary *a, NSDictionary *b, int cls)
{
    for (size_t i = 0; i < sizeof attrs / sizeof attrs[0]; i++)
        if (attrs[i].primary & cls) {
            id x = value_or_default(a, &attrs[i]), y = value_or_default(b, &attrs[i]);
            if (![x isEqual:y])
                return NO;
        }
    return SIsTrue([a objectForKey:@"sync"]) == SIsTrue([b objectForKey:@"sync"]);
}

static BOOL has_duplicate(struct store *s, NSDictionary *attributes, int cls, NSDictionary *except)
{
    for (NSDictionary *item in s->items)
        if (item != except && item_class(item) == cls &&
            same_primary_key([item objectForKey:@"attributes"], attributes, cls))
            return YES;
    return NO;
}

/* ---- answers ----------------------------------------------------------------------------- */

static id answer_for(struct store *s, NSDictionary *item, const struct query *q, OSStatus *status)
{
    int kinds = q->returnData + q->returnAttrs + q->returnRef + q->returnPersistent;
    NSMutableDictionary *all = [NSMutableDictionary dictionary];
    if (q->returnAttrs) {
        [all addEntriesFromDictionary:[item objectForKey:@"attributes"]];
        [all setObject:[item objectForKey:@"class"] forKey:(id)kSecClass];
        if (![all objectForKey:@"sync"])
            [all setObject:[NSNumber numberWithBool:NO] forKey:(id)kSecAttrSynchronizable];
        if (kinds == 1)
            return all;
    }
    if (q->returnData) {
        NSData *d = open_secret(s, item);
        if (!d) {
            *status = errSecDecode;
            return nil;
        }
        if (kinds == 1)
            return d;
        [all setObject:d forKey:(id)kSecValueData];
    }
    if (q->returnRef) {
        SItem *ref = [[[SItem alloc] init] autorelease];
        ref->uuid = [[item objectForKey:@"id"] copy];
        ref->itemClass = [[item objectForKey:@"class"] copy];
        if (kinds == 1)
            return ref;
        [all setObject:ref forKey:(id)kSecValueRef];
    }
    if (q->returnPersistent) {
        NSData *p = persistent_ref([item objectForKey:@"id"]);
        if (kinds == 1)
            return p;
        [all setObject:p forKey:(id)kSecValuePersistentRef];
    }
    return all;
}

/* What a call returns for the items found: one answer, or an array of them. */
static OSStatus answer(struct store *s, NSArray *found, const struct query *q, CFTypeRef *result)
{
    if (!result)
        return errSecSuccess;
    *result = NULL;
    if (!(q->returnData || q->returnAttrs || q->returnRef || q->returnPersistent))
        return errSecSuccess;
    OSStatus status = errSecSuccess;
    if (q->limit == 1) {
        id one = answer_for(s, [found objectAtIndex:0], q, &status);
        if (one)
            *result = (CFTypeRef)[one retain];
        return status;
    }
    NSMutableArray *many = [NSMutableArray array];
    for (NSDictionary *item in found) {
        id one = answer_for(s, item, q, &status);
        if (!one)
            return status;
        [many addObject:one];
    }
    *result = (CFTypeRef)[many retain];
    return errSecSuccess;
}

static NSString *new_uuid(void)
{
    uint8_t b[16];
    CCRandomGenerateBytes(b, sizeof b);
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    return [NSString stringWithFormat:@"%02X%02X%02X%02X-%02X%02X-%02X%02X-%02X%02X-%02X%02X%02X%02X%02X%02X", b[0],
                                      b[1], b[2], b[3], b[4], b[5], b[6], b[7], b[8], b[9], b[10], b[11], b[12], b[13],
                                      b[14], b[15]];
}

/* ---- SecItem ------------------------------------------------------------------------------- */

static id store_guard(void)
{
    static id guard;
    @synchronized([SItem class]) {
        if (!guard)
            guard = [[NSObject alloc] init];
    }
    return guard;
}

static OSStatus add_locked(NSDictionary *attributes, CFTypeRef *result)
{
    struct query q;
    OSStatus status = parse(attributes, Q_ADD, &q);
    if (result)
        *result = NULL;
    if (status != errSecSuccess)
        return status;
    if (!q.cls)
        return errSecUnimplemented;
    if (q.uuid)
        return errSecParam;
    struct store s;
    status = store_open(&s, YES);
    if (status == errSecSuccess) {
        NSMutableDictionary *at = [[q.attrs mutableCopy] autorelease];
        NSDate *now = [NSDate date];
        [at setObject:now forKey:@"cdat"];
        [at setObject:now forKey:@"mdat"];
        if (q.sync)
            [at setObject:[NSNumber numberWithBool:YES] forKey:@"sync"];
        if (has_duplicate(&s, at, q.cls, nil)) {
            status = errSecDuplicateItem;
        } else {
            NSString *uuid = new_uuid();
            NSData *sealed = seal(&s, uuid, q.data ?: [NSData data]);
            if (!sealed) {
                status = errSecInternalComponent;
            } else {
                NSMutableDictionary *item = [NSMutableDictionary dictionaryWithObjectsAndKeys:uuid, @"id",
                    q.cls == C_GENP ? kSecClassGenericPassword : kSecClassInternetPassword, @"class",
                    at, @"attributes", sealed, @"secret", nil];
                [s.items addObject:item];
                status = store_save(&s);
                if (status == errSecSuccess)
                    status = answer(&s, [NSArray arrayWithObject:item], &q, result);
            }
        }
    }
    store_close(&s);
    return status;
}

S_EXPORT OSStatus SecItemAdd(CFDictionaryRef attributes, CFTypeRef *result)
{
    @synchronized(store_guard()) {
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        OSStatus status = add_locked((NSDictionary *)attributes, result);
        [pool drain];
        return status;
    }
}

static NSArray *find(struct store *s, const struct query *q, NSInteger limit)
{
    NSMutableArray *found = [NSMutableArray array];
    for (NSDictionary *item in s->items)
        if ([found count] < (NSUInteger)limit && matches(item, q, q->cls))
            [found addObject:item];
    return found;
}

static OSStatus copy_locked(NSDictionary *query, CFTypeRef *result)
{
    struct query q;
    OSStatus status = parse(query, Q_FIND, &q);
    if (result)
        *result = NULL;
    if (status != errSecSuccess)
        return status;
    if (!q.cls)
        return errSecItemNotFound;
    struct store s;
    status = store_open(&s, NO);
    if (status == errSecSuccess) {
        NSArray *found = find(&s, &q, q.limit);
        status = [found count] ? answer(&s, found, &q, result) : errSecItemNotFound;
    }
    store_close(&s);
    return status;
}

S_EXPORT OSStatus SecItemCopyMatching(CFDictionaryRef query, CFTypeRef *result)
{
    @synchronized(store_guard()) {
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        OSStatus status = copy_locked((NSDictionary *)query, result);
        [pool drain];
        return status;
    }
}

static OSStatus update_locked(NSDictionary *query, NSDictionary *changes)
{
    struct query q, c;
    OSStatus status = parse(query, Q_FIND, &q);
    if (status != errSecSuccess)
        return status;
    if (q.returnData || q.returnAttrs || q.returnRef || q.returnPersistent)
        return errSecParam;
    status = parse(changes, Q_UPDATE, &c);
    if (status != errSecSuccess)
        return status;
    if (!q.cls)
        return errSecItemNotFound;
    for (NSString *key in c.attrs)
        if (!(find_attr(key)->classes & q.cls))
            return errSecNoSuchAttr;
    struct store s;
    status = store_open(&s, NO);
    if (status == errSecSuccess) {
        NSArray *found = find(&s, &q, NSIntegerMax);
        if (![found count])
            status = errSecItemNotFound;
        NSDate *now = [NSDate date];
        /* every change is checked before any is made */
        NSMutableArray *changed = [NSMutableArray array];
        for (NSDictionary *item in found) {
            NSMutableDictionary *at = [[[item objectForKey:@"attributes"] mutableCopy] autorelease];
            [at addEntriesFromDictionary:c.attrs];
            [at setObject:now forKey:@"mdat"];
            if ([changes objectForKey:(id)kSecAttrSynchronizable])
                [at setObject:[NSNumber numberWithBool:c.sync == 1] forKey:@"sync"];
            [changed addObject:at];
        }
        for (NSUInteger i = 0; status == errSecSuccess && i < [found count]; i++) {
            for (NSUInteger j = 0; j < [found count]; j++)
                if (j != i && same_primary_key([changed objectAtIndex:i], [changed objectAtIndex:j], q.cls))
                    status = errSecDuplicateItem;
            for (NSDictionary *other in s.items)
                if (![found containsObject:other] && item_class(other) == q.cls &&
                    same_primary_key([other objectForKey:@"attributes"], [changed objectAtIndex:i], q.cls))
                    status = errSecDuplicateItem;
        }
        for (NSUInteger i = 0; status == errSecSuccess && i < [found count]; i++) {
            NSMutableDictionary *item = (NSMutableDictionary *)[found objectAtIndex:i];
            [item setObject:[changed objectAtIndex:i] forKey:@"attributes"];
            if (c.data) {
                NSData *sealed = seal(&s, [item objectForKey:@"id"], c.data);
                if (!sealed)
                    status = errSecInternalComponent;
                else
                    [item setObject:sealed forKey:@"secret"];
            }
        }
        if (status == errSecSuccess)
            status = store_save(&s);
    }
    store_close(&s);
    return status;
}

S_EXPORT OSStatus SecItemUpdate(CFDictionaryRef query, CFDictionaryRef attributesToUpdate)
{
    @synchronized(store_guard()) {
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        OSStatus status = update_locked((NSDictionary *)query, (NSDictionary *)attributesToUpdate);
        [pool drain];
        return status;
    }
}

static OSStatus delete_locked(NSDictionary *query)
{
    struct query q;
    OSStatus status = parse(query, Q_DELETE, &q);
    if (status != errSecSuccess)
        return status;
    if (!q.cls)
        return errSecItemNotFound;
    struct store s;
    status = store_open(&s, NO);
    if (status == errSecSuccess) {
        NSArray *found = find(&s, &q, NSIntegerMax);
        if (![found count]) {
            status = errSecItemNotFound;
        } else {
            [s.items removeObjectsInArray:found];
            status = store_save(&s);
        }
    }
    store_close(&s);
    return status;
}

S_EXPORT OSStatus SecItemDelete(CFDictionaryRef query)
{
    @synchronized(store_guard()) {
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        OSStatus status = delete_locked((NSDictionary *)query);
        [pool drain];
        return status;
    }
}

/* ---- the older keychain calls ------------------------------------------------------------- */

@interface SKeychain : NSObject
@end
@implementation SKeychain
- (NSString *)description { return [NSString stringWithFormat:@"<SecKeychain %p login>", self]; }
@end

static Boolean interactionAllowed = 1;

S_EXPORT OSStatus SecKeychainCopyDefault(SecKeychainRef *keychain)
{
    static SKeychain *only;
    if (!keychain)
        return errSecParam;
    @synchronized(store_guard()) {
        if (!only)
            only = [[SKeychain alloc] init];
    }
    *keychain = (SecKeychainRef)[only retain];
    return errSecSuccess;
}

/* Remembered and answered back; Ferry never asks the user anything here. */
S_EXPORT OSStatus SecKeychainSetUserInteractionAllowed(Boolean state)
{
    interactionAllowed = state;
    return errSecSuccess;
}

S_EXPORT OSStatus SecKeychainGetUserInteractionAllowed(Boolean *state)
{
    if (!state)
        return errSecParam;
    *state = interactionAllowed;
    return errSecSuccess;
}

static NSString *text(UInt32 len, const char *s)
{
    if (!s || !len)
        return nil;
    return [[[NSString alloc] initWithBytes:s length:len encoding:NSUTF8StringEncoding] autorelease];
}

static NSString *four_cc(FourCharCode c)
{
    char s[5] = {(char)(c >> 24), (char)(c >> 16), (char)(c >> 8), (char)c, 0};
    return [NSString stringWithUTF8String:s];
}

/* Finds a query's item; its password into *data (malloc'd) and a reference into *item. */
static OSStatus legacy_find(NSDictionary *query, UInt32 *length, void **data, SecKeychainItemRef *itemRef)
{
    NSMutableDictionary *q = [[query mutableCopy] autorelease];
    if (length || data)
        [q setObject:(id)kCFBooleanTrue forKey:(id)kSecReturnData];
    [q setObject:(id)kCFBooleanTrue forKey:(id)kSecReturnAttributes]; /* so the answer is a dictionary */
    [q setObject:(id)kCFBooleanTrue forKey:(id)kSecReturnRef];
    CFTypeRef result = NULL;
    OSStatus status = SecItemCopyMatching((CFDictionaryRef)q, &result);
    if (status != errSecSuccess)
        return status;
    NSDictionary *r = [(id)result autorelease];
    NSData *password = [r objectForKey:(id)kSecValueData];
    if (length)
        *length = (UInt32)[password length];
    if (data) {
        *data = malloc([password length] ? [password length] : 1);
        if (!*data)
            return errSecAllocate;
        memcpy(*data, [password bytes], [password length]);
    }
    if (itemRef)
        *itemRef = (SecKeychainItemRef)[[r objectForKey:(id)kSecValueRef] retain];
    return errSecSuccess;
}

static OSStatus legacy_add(NSMutableDictionary *attributes, UInt32 length, const void *data, SecKeychainItemRef *itemRef)
{
    if (length && !data)
        return errSecParam;
    [attributes setObject:[NSData dataWithBytes:data length:length] forKey:(id)kSecValueData];
    if (itemRef)
        [attributes setObject:(id)kCFBooleanTrue forKey:(id)kSecReturnRef];
    CFTypeRef result = NULL;
    OSStatus status = SecItemAdd((CFDictionaryRef)attributes, itemRef ? &result : NULL);
    if (itemRef)
        *itemRef = (SecKeychainItemRef)result;
    return status;
}

S_EXPORT OSStatus SecKeychainAddGenericPassword(SecKeychainRef keychain, UInt32 serviceNameLength,
                                                const char *serviceName, UInt32 accountNameLength,
                                                const char *accountName, UInt32 passwordLength,
                                                const void *passwordData, SecKeychainItemRef *itemRef)
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    NSMutableDictionary *a = [NSMutableDictionary dictionaryWithObject:(id)kSecClassGenericPassword forKey:(id)kSecClass];
    NSString *service = text(serviceNameLength, serviceName), *account = text(accountNameLength, accountName);
    [a setObject:service ?: @"" forKey:(id)kSecAttrService];
    [a setObject:service ?: @"" forKey:(id)kSecAttrLabel];
    [a setObject:account ?: @"" forKey:(id)kSecAttrAccount];
    OSStatus status = legacy_add(a, passwordLength, passwordData, itemRef);
    [pool drain];
    return status;
}

S_EXPORT OSStatus SecKeychainFindGenericPassword(CFTypeRef keychainOrArray, UInt32 serviceNameLength,
                                                 const char *serviceName, UInt32 accountNameLength,
                                                 const char *accountName, UInt32 *passwordLength,
                                                 void **passwordData, SecKeychainItemRef *itemRef)
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    NSMutableDictionary *q = [NSMutableDictionary dictionaryWithObject:(id)kSecClassGenericPassword forKey:(id)kSecClass];
    NSString *service = text(serviceNameLength, serviceName), *account = text(accountNameLength, accountName);
    if (service)
        [q setObject:service forKey:(id)kSecAttrService];
    if (account)
        [q setObject:account forKey:(id)kSecAttrAccount];
    OSStatus status = legacy_find(q, passwordLength, passwordData, itemRef);
    [pool drain];
    return status;
}

S_EXPORT OSStatus SecKeychainAddInternetPassword(SecKeychainRef keychain, UInt32 serverNameLength,
                                                 const char *serverName, UInt32 securityDomainLength,
                                                 const char *securityDomain, UInt32 accountNameLength,
                                                 const char *accountName, UInt32 pathLength, const char *path,
                                                 UInt16 port, SecProtocolType protocol,
                                                 SecAuthenticationType authenticationType, UInt32 passwordLength,
                                                 const void *passwordData, SecKeychainItemRef *itemRef)
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    NSMutableDictionary *a = [NSMutableDictionary dictionaryWithObject:(id)kSecClassInternetPassword forKey:(id)kSecClass];
    NSString *server = text(serverNameLength, serverName);
    [a setObject:server ?: @"" forKey:(id)kSecAttrServer];
    [a setObject:server ?: @"" forKey:(id)kSecAttrLabel];
    [a setObject:text(securityDomainLength, securityDomain) ?: @"" forKey:(id)kSecAttrSecurityDomain];
    [a setObject:text(accountNameLength, accountName) ?: @"" forKey:(id)kSecAttrAccount];
    [a setObject:text(pathLength, path) ?: @"" forKey:(id)kSecAttrPath];
    [a setObject:[NSNumber numberWithInt:port] forKey:(id)kSecAttrPort];
    if (protocol)
        [a setObject:four_cc(protocol) forKey:(id)kSecAttrProtocol];
    if (authenticationType)
        [a setObject:four_cc(authenticationType) forKey:(id)kSecAttrAuthenticationType];
    OSStatus status = legacy_add(a, passwordLength, passwordData, itemRef);
    [pool drain];
    return status;
}

S_EXPORT OSStatus SecKeychainFindInternetPassword(CFTypeRef keychainOrArray, UInt32 serverNameLength,
                                                  const char *serverName, UInt32 securityDomainLength,
                                                  const char *securityDomain, UInt32 accountNameLength,
                                                  const char *accountName, UInt32 pathLength, const char *path,
                                                  UInt16 port, SecProtocolType protocol,
                                                  SecAuthenticationType authenticationType, UInt32 *passwordLength,
                                                  void **passwordData, SecKeychainItemRef *itemRef)
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    NSMutableDictionary *q = [NSMutableDictionary dictionaryWithObject:(id)kSecClassInternetPassword forKey:(id)kSecClass];
    NSString *s;
    if ((s = text(serverNameLength, serverName)))
        [q setObject:s forKey:(id)kSecAttrServer];
    if ((s = text(securityDomainLength, securityDomain)))
        [q setObject:s forKey:(id)kSecAttrSecurityDomain];
    if ((s = text(accountNameLength, accountName)))
        [q setObject:s forKey:(id)kSecAttrAccount];
    if ((s = text(pathLength, path)))
        [q setObject:s forKey:(id)kSecAttrPath];
    if (port)
        [q setObject:[NSNumber numberWithInt:port] forKey:(id)kSecAttrPort];
    if (protocol)
        [q setObject:four_cc(protocol) forKey:(id)kSecAttrProtocol];
    if (authenticationType)
        [q setObject:four_cc(authenticationType) forKey:(id)kSecAttrAuthenticationType];
    OSStatus status = legacy_find(q, passwordLength, passwordData, itemRef);
    [pool drain];
    return status;
}

static NSDictionary *item_query(SecKeychainItemRef itemRef)
{
    SItem *item = (SItem *)itemRef;
    if (![item isKindOfClass:[SItem class]])
        return nil;
    return [NSDictionary dictionaryWithObjectsAndKeys:item->itemClass, (id)kSecClass, item, (id)kSecValueRef,
                                                      (id)kSecAttrSynchronizableAny, (id)kSecAttrSynchronizable, nil];
}

/* An attribute list's values, by their tags, into d: the tags are the
 * attributes' own keys; text is UTF-8 and numbers 32 bits. */
static OSStatus attributes_from_list(const SecKeychainAttributeList *attrList, NSMutableDictionary *d)
{
    for (UInt32 i = 0; attrList && i < attrList->count; i++) {
        const SecKeychainAttribute *at = &attrList->attr[i];
        NSString *tag = four_cc(at->tag);
        const struct attr *a = find_attr(tag);
        if (!a || a->type == A_DATE)
            return errSecNoSuchAttr;
        if (a->type == A_NUMBER || a->type == A_BOOL || at->tag == 'ptcl' || at->tag == 'atyp') {
            UInt32 n;
            if (at->length != 4 || !at->data)
                return errSecParam;
            memcpy(&n, at->data, 4);
            [d setObject:(a->type == A_STRING ? (id)four_cc(n) : (id)[NSNumber numberWithUnsignedInt:n]) forKey:tag];
        } else if (a->type == A_DATA) {
            [d setObject:[NSData dataWithBytes:at->data length:at->length] forKey:tag];
        } else {
            [d setObject:text(at->length, at->data) ?: @"" forKey:tag];
        }
    }
    return errSecSuccess;
}

S_EXPORT OSStatus SecKeychainItemModifyAttributesAndData(SecKeychainItemRef itemRef,
                                                         const SecKeychainAttributeList *attrList, UInt32 length,
                                                         const void *data)
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    NSDictionary *q = item_query(itemRef);
    NSMutableDictionary *changes = [NSMutableDictionary dictionary];
    OSStatus status = q ? attributes_from_list(attrList, changes) : errSecInvalidItemRef;
    if (status == errSecSuccess && data)
        [changes setObject:[NSData dataWithBytes:data length:length] forKey:(id)kSecValueData];
    if (status == errSecSuccess) {
        status = SecItemUpdate((CFDictionaryRef)q, (CFDictionaryRef)changes);
        if (status == errSecItemNotFound)
            status = errSecInvalidItemRef;
    }
    [pool drain];
    return status;
}

/* ---- items made from attribute lists, searches and access lists ----------------------------
 * (freemac 1.226, Ferry 0.50.0) */

static id class_key(SecItemClass itemClass)
{
    if (itemClass == kSecGenericPasswordItemClass)
        return (id)kSecClassGenericPassword;
    if (itemClass == kSecInternetPasswordItemClass)
        return (id)kSecClassInternetPassword;
    return nil;
}

/* The item gets the attributes the list gives; a generic password's
 * service and account, and an internet password's server and account, are
 * empty when the list leaves them out, as SecKeychainAddGenericPassword
 * makes them, and its label is the service's or server's name. The access
 * list is not kept: Ferry's keychain asks no one. */
S_EXPORT OSStatus SecKeychainItemCreateFromContent(SecItemClass itemClass, SecKeychainAttributeList *attrList,
                                                   UInt32 length, const void *data, SecKeychainRef keychainRef,
                                                   SecAccessRef initialAccess, SecKeychainItemRef *itemRef)
{
    id cls = class_key(itemClass);
    if (!cls)
        return errSecNoSuchClass;
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    NSMutableDictionary *a = [NSMutableDictionary dictionaryWithObject:cls forKey:(id)kSecClass];
    OSStatus status = attributes_from_list(attrList, a);
    if (status == errSecSuccess) {
        id name = itemClass == kSecGenericPasswordItemClass ? (id)kSecAttrService : (id)kSecAttrServer;
        if (![a objectForKey:name])
            [a setObject:@"" forKey:name];
        if (![a objectForKey:(id)kSecAttrAccount])
            [a setObject:@"" forKey:(id)kSecAttrAccount];
        if (![a objectForKey:(id)kSecAttrLabel])
            [a setObject:[a objectForKey:name] forKey:(id)kSecAttrLabel];
        status = legacy_add(a, length, data, itemRef);
    }
    [pool drain];
    return status;
}

@interface SSearch : NSObject {
  @public
    NSArray *items;
    NSUInteger next;
}
@end
@implementation SSearch
- (void)dealloc
{
    [items release];
    [super dealloc];
}
- (NSString *)description { return [NSString stringWithFormat:@"<SecKeychainSearch %p>", self]; }
@end

/* The items whose attributes are the list's, found when the search is
 * made; a NULL list finds every item of the class. */
S_EXPORT OSStatus SecKeychainSearchCreateFromAttributes(CFTypeRef keychainOrArray, SecItemClass itemClass,
                                                        const SecKeychainAttributeList *attrList,
                                                        SecKeychainSearchRef *searchRef)
{
    id cls = class_key(itemClass);
    if (!searchRef)
        return errSecParam;
    if (!cls)
        return errSecNoSuchClass;
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    NSMutableDictionary *q = [NSMutableDictionary dictionaryWithObject:cls forKey:(id)kSecClass];
    OSStatus status = attributes_from_list(attrList, q);
    NSArray *found = [NSArray array];
    if (status == errSecSuccess) {
        [q setObject:(id)kSecMatchLimitAll forKey:(id)kSecMatchLimit];
        [q setObject:(id)kCFBooleanTrue forKey:(id)kSecReturnRef];
        CFTypeRef result = NULL;
        status = SecItemCopyMatching((CFDictionaryRef)q, &result);
        if (status == errSecSuccess)
            found = [(id)result autorelease];
        else if (status == errSecItemNotFound)
            status = errSecSuccess;
    }
    if (status == errSecSuccess) {
        SSearch *search = [[SSearch alloc] init];
        search->items = [found retain];
        *searchRef = (SecKeychainSearchRef)search;
    }
    [pool drain];
    return status;
}

S_EXPORT OSStatus SecKeychainSearchCopyNext(SecKeychainSearchRef searchRef, SecKeychainItemRef *itemRef)
{
    SSearch *search = (SSearch *)searchRef;
    if (![search isKindOfClass:[SSearch class]] || !itemRef)
        return errSecParam;
    if (search->next >= [search->items count])
        return errSecItemNotFound;
    *itemRef = (SecKeychainItemRef)[[search->items objectAtIndex:search->next++] retain];
    return errSecSuccess;
}

@interface STrustedApplication : NSObject {
  @public
    NSString *path;
}
@end
@implementation STrustedApplication
- (void)dealloc
{
    [path release];
    [super dealloc];
}
- (NSString *)description { return [NSString stringWithFormat:@"<SecTrustedApplication %p %@>", self, path]; }
@end

/* A NULL path is the running program's own. */
S_EXPORT OSStatus SecTrustedApplicationCreateFromPath(const char *path, SecTrustedApplicationRef *app)
{
    if (!app)
        return errSecParam;
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    NSString *p = path ? [NSString stringWithUTF8String:path] : [[NSBundle mainBundle] executablePath];
    OSStatus status = errSecSuccess;
    if (path && ![[NSFileManager defaultManager] fileExistsAtPath:p])
        status = errSecParam;
    if (status == errSecSuccess) {
        STrustedApplication *a = [[STrustedApplication alloc] init];
        a->path = [p ?: @"" copy];
        *app = (SecTrustedApplicationRef)a;
    }
    [pool drain];
    return status;
}

/* The application's path, as its data. */
S_EXPORT OSStatus SecTrustedApplicationCopyData(SecTrustedApplicationRef appRef, CFDataRef *data)
{
    STrustedApplication *a = (STrustedApplication *)appRef;
    if (![a isKindOfClass:[STrustedApplication class]] || !data)
        return errSecParam;
    const char *p = [a->path fileSystemRepresentation];
    *data = (CFDataRef)[[NSData alloc] initWithBytes:p length:strlen(p)];
    return errSecSuccess;
}

@interface SAccess : NSObject {
  @public
    NSString *descriptor;
    NSArray *trusted;
}
@end
@implementation SAccess
- (void)dealloc
{
    [descriptor release];
    [trusted release];
    [super dealloc];
}
- (NSString *)description
{
    return [NSString stringWithFormat:@"<SecAccess %p %@, %lu applications>", self, descriptor,
                                      (unsigned long)[trusted count]];
}
@end

S_EXPORT OSStatus SecAccessCreate(CFStringRef descriptor, CFArrayRef trustedlist, SecAccessRef *accessRef)
{
    if (!descriptor || !accessRef)
        return errSecParam;
    SAccess *a = [[SAccess alloc] init];
    a->descriptor = [(NSString *)descriptor copy];
    a->trusted = [(NSArray *)trustedlist copy];
    *accessRef = (SecAccessRef)a;
    return errSecSuccess;
}

S_EXPORT OSStatus SecKeychainItemDelete(SecKeychainItemRef itemRef)
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    NSDictionary *q = item_query(itemRef);
    OSStatus status = q ? SecItemDelete((CFDictionaryRef)q) : errSecInvalidItemRef;
    if (status == errSecItemNotFound)
        status = errSecInvalidItemRef;
    [pool drain];
    return status;
}

/* Frees a password that a Find call returned. Ferry returns no attribute
 * lists, so one passed here is left alone. */
S_EXPORT OSStatus SecKeychainItemFreeContent(SecKeychainAttributeList *attrList, void *data)
{
    free(data);
    return errSecSuccess;
}
