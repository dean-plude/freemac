/* SPDX-License-Identifier: GPL-3.0-or-later
 * The Apple Event Manager's descriptors and Launch Services' application
 * lookups, written for freemac from Apple's public "Apple Event Manager
 * Reference" and "Launch Services Reference". Served from Foundation's
 * file, as CoreServices is.
 *
 * A descriptor's data handle points to a node of Ferry's own: plain bytes,
 * or a list or record of descriptors that it owns (an Apple event is a
 * record with attributes as well). Descriptors put into a list or record
 * are copied, and disposing of the outer one disposes of everything inside,
 * as on a Mac. AECoerceDesc converts between the number types, Booleans,
 * the text types (typeChar is read and written as UTF-8 here), the
 * four-character code types, file URLs and FSRefs, and gives a record
 * another record type.
 *
 * No other program on freemac receives Apple events. An event sent to the
 * app itself (by its process serial number, kCurrentProcess, its process
 * id or its bundle identifier) goes to the handler it installed, at once;
 * an event sent anywhere else answers procNotFound with an empty reply.
 *
 * Launch Services: freemac keeps no register of Mac applications, so
 * finding one by creator, bundle identifier or URL scheme finds none, and
 * LSOpenCFURLRef opens a URL or file with the desktop's own launcher (gio
 * open or xdg-open, never a Mac app), as NSWorkspace does. */
#import "FInternal.h"
#include <CoreServices/CoreServices.h>
#include <HIServices/Processes.h>
#include <pthread.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

enum { NODE_PLAIN, NODE_LIST, NODE_RECORD };

struct item {
    AEKeyword key;
    AEDesc desc;
};

struct node {
    uint32_t mark;
    int kind;
    Size size;
    unsigned char *bytes;
    long count, cap;
    struct item *items;
    long nattrs, attrcap;
    struct item *attrs;
};

#define NODE_MARK 0x41454e44u /* "AEND" */

static struct node *node_of(const AEDesc *d)
{
    struct node *n = d ? (struct node *)d->dataHandle : NULL;
    return n && n->mark == NODE_MARK ? n : NULL;
}

static struct node *new_node(int kind)
{
    struct node *n = calloc(1, sizeof *n);
    n->mark = NODE_MARK;
    n->kind = kind;
    return n;
}

static void null_desc(AEDesc *d)
{
    d->descriptorType = typeNull;
    d->dataHandle = NULL;
}

void AEInitializeDesc(AEDesc *desc)
{
    if (desc)
        null_desc(desc);
}

static void free_items(struct item *items, long count)
{
    for (long i = 0; i < count; i++)
        AEDisposeDesc(&items[i].desc);
    free(items);
}

OSErr AEDisposeDesc(AEDesc *d)
{
    if (!d)
        return paramErr;
    struct node *n = node_of(d);
    if (n) {
        free(n->bytes);
        free_items(n->items, n->count);
        free_items(n->attrs, n->nattrs);
        n->mark = 0;
        free(n);
    }
    null_desc(d);
    return noErr;
}

static OSErr make_plain(DescType type, const void *data, Size size, AEDesc *result)
{
    if (!result)
        return paramErr;
    if (size < 0 || (size && !data)) {
        null_desc(result);
        return paramErr;
    }
    if (type == typeNull) {
        null_desc(result);
        return noErr;
    }
    struct node *n = new_node(NODE_PLAIN);
    n->size = size;
    if (size) {
        n->bytes = malloc((size_t)size);
        memcpy(n->bytes, data, (size_t)size);
    }
    result->descriptorType = type;
    result->dataHandle = (AEDataStorage)n;
    return noErr;
}

OSErr AECreateDesc(DescType type, const void *data, Size size, AEDesc *result)
{
    return make_plain(type, data, size, result);
}

static void copy_items(const struct item *from, long count, struct item **to, long *tocount, long *tocap)
{
    *to = count ? calloc((size_t)count, sizeof **to) : NULL;
    *tocount = *tocap = count;
    for (long i = 0; i < count; i++) {
        (*to)[i].key = from[i].key;
        AEDuplicateDesc(&from[i].desc, &(*to)[i].desc);
    }
}

OSErr AEDuplicateDesc(const AEDesc *d, AEDesc *result)
{
    if (!d || !result)
        return paramErr;
    struct node *n = node_of(d);
    if (!n) {
        result->descriptorType = d->descriptorType;
        result->dataHandle = NULL;
        return noErr;
    }
    struct node *c = new_node(n->kind);
    c->size = n->size;
    if (n->size) {
        c->bytes = malloc((size_t)n->size);
        memcpy(c->bytes, n->bytes, (size_t)n->size);
    }
    copy_items(n->items, n->count, &c->items, &c->count, &c->cap);
    copy_items(n->attrs, n->nattrs, &c->attrs, &c->nattrs, &c->attrcap);
    result->descriptorType = d->descriptorType;
    result->dataHandle = (AEDataStorage)c;
    return noErr;
}

Size AEGetDescDataSize(const AEDesc *d)
{
    struct node *n = node_of(d);
    return n && n->kind == NODE_PLAIN ? n->size : 0;
}

OSErr AEGetDescData(const AEDesc *d, void *data, Size max)
{
    if (!d || (max && !data))
        return paramErr;
    struct node *n = node_of(d);
    if (!n)
        return d->descriptorType == typeNull ? noErr : errAENotAEDesc;
    if (n->kind != NODE_PLAIN)
        return errAEWrongDataType;
    Size k = n->size < max ? n->size : max;
    if (k > 0)
        memcpy(data, n->bytes, (size_t)k);
    return noErr;
}

OSErr AEReplaceDescData(DescType type, const void *data, Size size, AEDesc *d)
{
    if (!d)
        return paramErr;
    AEDisposeDesc(d);
    return make_plain(type, data, size, d);
}

Boolean AECheckIsRecord(const AEDesc *d)
{
    struct node *n = node_of(d);
    return n && n->kind == NODE_RECORD;
}

/* ---- coercion ---------------------------------------------------------------------- */

static BOOL is_text(DescType t)
{
    return t == typeChar || t == typeUTF8Text || t == typeUnicodeText || t == typeUTF16ExternalRepresentation ||
           t == typeCString || t == typeIntlText || t == typeStyledText;
}

static BOOL is_number(DescType t)
{
    return t == typeSInt16 || t == typeUInt16 || t == typeSInt32 || t == typeUInt32 || t == typeSInt64 ||
           t == typeUInt64 || t == typeIEEE32BitFloatingPoint || t == typeIEEE64BitFloatingPoint;
}

static BOOL is_code(DescType t)
{
    return t == typeType || t == typeEnumerated || t == typeKeyword || t == typeProperty ||
           t == typeAbsoluteOrdinal || t == typeApplSignature;
}

static NSString *text_of(DescType t, const unsigned char *b, Size n)
{
    if (t == typeUnicodeText)
        return [[[NSString alloc] initWithCharacters:(const unichar *)b length:(NSUInteger)n / 2] autorelease];
    if (t == typeUTF16ExternalRepresentation) {
        NSString *s = [[NSString alloc] initWithBytes:b length:(NSUInteger)n encoding:NSUTF16StringEncoding];
        return [s autorelease];
    }
    if (t == typeCString && n && !b[n - 1])
        n--;
    NSString *s = [[NSString alloc] initWithBytes:b length:(NSUInteger)n encoding:NSUTF8StringEncoding];
    if (!s)
        s = [[NSString alloc] initWithBytes:b length:(NSUInteger)n encoding:NSISOLatin1StringEncoding];
    return [s autorelease];
}

static OSErr make_text(NSString *s, DescType to, AEDesc *result)
{
    if (to == typeUnicodeText) {
        NSUInteger len = [s length];
        unichar *buf = malloc((len ? len : 1) * sizeof(unichar));
        [s getCharacters:buf range:NSMakeRange(0, len)];
        OSErr e = make_plain(to, buf, (Size)(len * sizeof(unichar)), result);
        free(buf);
        return e;
    }
    if (to == typeUTF16ExternalRepresentation) {
        NSData *d = [s dataUsingEncoding:NSUTF16BigEndianStringEncoding];
        NSMutableData *m = [NSMutableData dataWithBytes:"\xfe\xff" length:2];
        [m appendData:d];
        return make_plain(to, [m bytes], (Size)[m length], result);
    }
    const char *u = [s UTF8String] ?: "";
    return make_plain(to, u, (Size)strlen(u) + (to == typeCString ? 1 : 0), result);
}

/* A number as a double and, exactly, as a 64-bit integer. */
static BOOL number_of(DescType t, const unsigned char *b, Size n, double *dv, int64_t *iv, BOOL *integral)
{
#define GET(type)                                                                                                     \
    if (n < (Size)sizeof(type))                                                                                       \
        return NO;                                                                                                    \
    type v;                                                                                                           \
    memcpy(&v, b, sizeof v);
    *integral = YES;
    switch (t) {
    case typeSInt16: { GET(int16_t) *iv = v; *dv = v; return YES; }
    case typeUInt16: { GET(uint16_t) *iv = v; *dv = v; return YES; }
    case typeSInt32: { GET(int32_t) *iv = v; *dv = v; return YES; }
    case typeUInt32: { GET(uint32_t) *iv = v; *dv = v; return YES; }
    case typeSInt64: { GET(int64_t) *iv = v; *dv = (double)v; return YES; }
    case typeUInt64: { GET(uint64_t) *iv = (int64_t)v; *dv = (double)v; return YES; }
    case typeIEEE32BitFloatingPoint: { GET(float) *dv = v; *iv = (int64_t)v; *integral = v == (float)*iv; return YES; }
    case typeIEEE64BitFloatingPoint: { GET(double) *dv = v; *iv = (int64_t)v; *integral = v == (double)*iv; return YES; }
    }
#undef GET
    return NO;
}

static OSErr make_number(double dv, int64_t iv, BOOL integral, DescType to, AEDesc *result)
{
#define PUT(type, value)                                                                                              \
    {                                                                                                                 \
        type v = (type)(value);                                                                                       \
        return make_plain(to, &v, sizeof v, result);                                                                  \
    }
    switch (to) {
    case typeIEEE32BitFloatingPoint: PUT(float, dv)
    case typeIEEE64BitFloatingPoint: PUT(double, dv)
    }
    if (!integral)
        return errAECoercionFail;
    switch (to) {
    case typeSInt16:
        if (iv < INT16_MIN || iv > INT16_MAX)
            return errAECoercionFail;
        PUT(int16_t, iv)
    case typeUInt16:
        if (iv < 0 || iv > UINT16_MAX)
            return errAECoercionFail;
        PUT(uint16_t, iv)
    case typeSInt32:
        if (iv < INT32_MIN || iv > INT32_MAX)
            return errAECoercionFail;
        PUT(int32_t, iv)
    case typeUInt32:
        if (iv < 0 || iv > UINT32_MAX)
            return errAECoercionFail;
        PUT(uint32_t, iv)
    case typeSInt64: PUT(int64_t, iv)
    case typeUInt64:
        if (iv < 0)
            return errAECoercionFail;
        PUT(uint64_t, iv)
    }
#undef PUT
    return errAECoercionFail;
}

static int bool_of(DescType t, const unsigned char *b, Size n)
{
    if (t == typeTrue)
        return 1;
    if (t == typeFalse)
        return 0;
    if (t == typeBoolean)
        return n >= 1 ? b[0] != 0 : -1;
    return -1;
}

static OSErr coerce_bytes(DescType from, const unsigned char *b, Size n, DescType to, AEDesc *result)
{
    if (from == to || to == typeWildCard)
        return make_plain(from, b, n, result);
    @autoreleasepool {
        double dv = 0;
        int64_t iv = 0;
        BOOL integral = YES;
        int bv = bool_of(from, b, n);
        if (bv >= 0) {
            if (to == typeBoolean) {
                unsigned char v = (unsigned char)bv;
                return make_plain(to, &v, 1, result);
            }
            if (to == typeTrue || to == typeFalse)
                return (to == typeTrue) == (bv == 1) ? make_plain(to, NULL, 0, result) : errAECoercionFail;
            if (is_number(to))
                return make_number(bv, bv, YES, to, result);
            if (is_text(to))
                return make_text(bv ? @"true" : @"false", to, result);
            return errAECoercionFail;
        }
        if (is_number(from) && number_of(from, b, n, &dv, &iv, &integral)) {
            if (is_number(to))
                return make_number(dv, iv, integral, to, result);
            if (to == typeBoolean) {
                unsigned char v = dv != 0;
                return make_plain(to, &v, 1, result);
            }
            if (is_text(to))
                return make_text(integral ? [NSString stringWithFormat:@"%lld", (long long)iv]
                                          : [NSString stringWithFormat:@"%.15g", dv],
                                 to, result);
            return errAECoercionFail;
        }
        if (is_text(from)) {
            NSString *s = text_of(from, b, n);
            if (!s)
                return errAECoercionFail;
            if (is_text(to))
                return make_text(s, to, result);
            if (is_number(to)) {
                NSScanner *sc = [NSScanner scannerWithString:s];
                double d;
                if (![sc scanDouble:&d] || ![sc isAtEnd])
                    return errAECoercionFail;
                return make_number(d, (int64_t)d, d == (double)(int64_t)d, to, result);
            }
            if (to == typeBoolean) {
                NSString *l = [s lowercaseString];
                if (![l isEqual:@"true"] && ![l isEqual:@"false"])
                    return errAECoercionFail;
                unsigned char v = [l isEqual:@"true"];
                return make_plain(to, &v, 1, result);
            }
            if (is_code(to) && n == 4 && (from == typeChar || from == typeUTF8Text)) {
                OSType c = ((OSType)b[0] << 24) | ((OSType)b[1] << 16) | ((OSType)b[2] << 8) | b[3];
                return make_plain(to, &c, 4, result);
            }
            if (to == typeFileURL && [s hasPrefix:@"/"]) {
                const char *u = [[[NSURL fileURLWithPath:s] absoluteString] UTF8String];
                return make_plain(to, u, (Size)strlen(u), result);
            }
            return errAECoercionFail;
        }
        if (is_code(from) && is_code(to) && n == 4)
            return make_plain(to, b, n, result);
        if (from == typeFileURL && to == typeFSRef) {
            NSString *u = text_of(typeUTF8Text, b, n);
            NSURL *url = [NSURL URLWithString:u];
            FSRef ref;
            if (![url isFileURL] || !CFURLGetFSRef((CFURLRef)url, &ref))
                return errAECoercionFail;
            return make_plain(to, &ref, sizeof ref, result);
        }
        if (from == typeFSRef && (to == typeFileURL || is_text(to)) && n == (Size)sizeof(FSRef)) {
            CFURLRef url = CFURLCreateFromFSRef(NULL, (const FSRef *)b);
            if (!url)
                return errAECoercionFail;
            NSString *s = to == typeFileURL ? [(NSURL *)url absoluteString] : [(NSURL *)url path];
            CFRelease(url);
            if (to == typeFileURL) {
                const char *u = [s UTF8String];
                return make_plain(to, u, (Size)strlen(u), result);
            }
            return make_text(s, to, result);
        }
        if (from == typeFileURL && is_text(to)) {
            NSURL *url = [NSURL URLWithString:text_of(typeUTF8Text, b, n)];
            return [url isFileURL] ? make_text([url path], to, result) : errAECoercionFail;
        }
    }
    return errAECoercionFail;
}

OSErr AECoercePtr(DescType type, const void *data, Size size, DescType to, AEDesc *result)
{
    if (!result)
        return paramErr;
    null_desc(result);
    return coerce_bytes(type, data, size, to, result);
}

OSErr AECoerceDesc(const AEDesc *d, DescType to, AEDesc *result)
{
    if (!d || !result)
        return paramErr;
    null_desc(result);
    struct node *n = node_of(d);
    if (d->descriptorType == to || to == typeWildCard)
        return AEDuplicateDesc(d, result);
    if (n && n->kind == NODE_RECORD) {
        /* a record takes any record type, as object specifiers do */
        if (to == typeAEList)
            return errAECoercionFail;
        OSErr e = AEDuplicateDesc(d, result);
        if (e == noErr)
            result->descriptorType = to;
        return e;
    }
    if (n && n->kind == NODE_LIST)
        return errAECoercionFail;
    if (!n)
        return d->descriptorType == typeNull ? errAECoercionFail : errAENotAEDesc;
    return coerce_bytes(d->descriptorType, n->bytes, n->size, to, result);
}

/* ---- lists and records ------------------------------------------------------------ */

OSErr AECreateList(const void *factoring, Size factoredSize, Boolean isRecord, AEDescList *result)
{
    if (!result)
        return paramErr;
    struct node *n = new_node(isRecord ? NODE_RECORD : NODE_LIST);
    result->descriptorType = isRecord ? typeAERecord : typeAEList;
    result->dataHandle = (AEDataStorage)n;
    return noErr;
}

static struct node *container(const AEDesc *d)
{
    struct node *n = node_of(d);
    return n && n->kind != NODE_PLAIN ? n : NULL;
}

OSErr AECountItems(const AEDescList *list, long *count)
{
    struct node *n = container(list);
    if (!count)
        return paramErr;
    if (!n)
        return errAEWrongDataType;
    *count = n->count;
    return noErr;
}

static void grow(struct item **items, long count, long *cap)
{
    if (count < *cap)
        return;
    *cap = *cap ? *cap * 2 : 8;
    *items = realloc(*items, (size_t)*cap * sizeof **items);
}

OSErr AEPutDesc(AEDescList *list, long index, const AEDesc *d)
{
    struct node *n = container(list);
    if (!n || !d)
        return n ? paramErr : errAEWrongDataType;
    if (index == 0 || index > n->count)
        index = n->count + 1;
    if (index < 0)
        return errAEIllegalIndex;
    AEDesc copy;
    OSErr e = AEDuplicateDesc(d, &copy);
    if (e != noErr)
        return e;
    if (index <= n->count) {
        AEDisposeDesc(&n->items[index - 1].desc);
        n->items[index - 1].desc = copy;
        return noErr;
    }
    grow(&n->items, n->count, &n->cap);
    n->items[n->count].key = typeWildCard;
    n->items[n->count].desc = copy;
    n->count++;
    return noErr;
}

OSErr AEPutPtr(AEDescList *list, long index, DescType type, const void *data, Size size)
{
    AEDesc d;
    OSErr e = make_plain(type, data, size, &d);
    if (e != noErr)
        return e;
    e = AEPutDesc(list, index, &d);
    AEDisposeDesc(&d);
    return e;
}

/* A plain item's bytes after coercion: into the caller's buffer. */
static OSErr read_out(const AEDesc *d, DescType desired, DescType *typeCode, void *data, Size max, Size *actual)
{
    AEDesc c;
    OSErr e = AECoerceDesc(d, desired, &c);
    if (e != noErr)
        return e;
    struct node *n = node_of(&c);
    Size size = n && n->kind == NODE_PLAIN ? n->size : 0;
    if (typeCode)
        *typeCode = c.descriptorType;
    if (actual)
        *actual = size;
    if (data && max > 0 && n)
        memcpy(data, n->bytes, (size_t)(size < max ? size : max));
    AEDisposeDesc(&c);
    return noErr;
}

OSErr AEGetNthDesc(const AEDescList *list, long index, DescType desired, AEKeyword *key, AEDesc *result)
{
    struct node *n = container(list);
    if (!result)
        return paramErr;
    null_desc(result);
    if (!n)
        return errAEWrongDataType;
    if (index < 1 || index > n->count)
        return errAEIllegalIndex;
    if (key)
        *key = n->items[index - 1].key;
    return AECoerceDesc(&n->items[index - 1].desc, desired, result);
}

OSErr AEGetNthPtr(const AEDescList *list, long index, DescType desired, AEKeyword *key, DescType *typeCode, void *data,
                  Size max, Size *actual)
{
    struct node *n = container(list);
    if (!n)
        return errAEWrongDataType;
    if (index < 1 || index > n->count)
        return errAEIllegalIndex;
    if (key)
        *key = n->items[index - 1].key;
    return read_out(&n->items[index - 1].desc, desired, typeCode, data, max, actual);
}

OSErr AESizeOfNthItem(const AEDescList *list, long index, DescType *typeCode, Size *size)
{
    struct node *n = container(list);
    if (!n)
        return errAEWrongDataType;
    if (index < 1 || index > n->count)
        return errAEIllegalIndex;
    if (typeCode)
        *typeCode = n->items[index - 1].desc.descriptorType;
    if (size)
        *size = AEGetDescDataSize(&n->items[index - 1].desc);
    return noErr;
}

OSErr AEDeleteItem(AEDescList *list, long index)
{
    struct node *n = container(list);
    if (!n)
        return errAEWrongDataType;
    if (index < 1 || index > n->count)
        return errAEIllegalIndex;
    AEDisposeDesc(&n->items[index - 1].desc);
    memmove(&n->items[index - 1], &n->items[index], (size_t)(n->count - index) * sizeof *n->items);
    n->count--;
    return noErr;
}

static long find_key(struct item *items, long count, AEKeyword key)
{
    for (long i = 0; i < count; i++)
        if (items[i].key == key)
            return i;
    return -1;
}

static OSErr put_keyed(struct item **items, long *count, long *cap, AEKeyword key, const AEDesc *d)
{
    AEDesc copy;
    OSErr e = AEDuplicateDesc(d, &copy);
    if (e != noErr)
        return e;
    long i = find_key(*items, *count, key);
    if (i >= 0) {
        AEDisposeDesc(&(*items)[i].desc);
        (*items)[i].desc = copy;
        return noErr;
    }
    grow(items, *count, cap);
    (*items)[*count].key = key;
    (*items)[*count].desc = copy;
    (*count)++;
    return noErr;
}

static struct node *record(const AEDesc *d)
{
    struct node *n = node_of(d);
    return n && n->kind == NODE_RECORD ? n : NULL;
}

OSErr AEPutKeyDesc(AERecord *rec, AEKeyword key, const AEDesc *d)
{
    struct node *n = record(rec);
    if (!n || !d)
        return n ? paramErr : errAEWrongDataType;
    return put_keyed(&n->items, &n->count, &n->cap, key, d);
}

OSErr AEPutKeyPtr(AERecord *rec, AEKeyword key, DescType type, const void *data, Size size)
{
    AEDesc d;
    OSErr e = make_plain(type, data, size, &d);
    if (e != noErr)
        return e;
    e = AEPutKeyDesc(rec, key, &d);
    AEDisposeDesc(&d);
    return e;
}

OSErr AEGetKeyDesc(const AERecord *rec, AEKeyword key, DescType desired, AEDesc *result)
{
    struct node *n = record(rec);
    if (!result)
        return paramErr;
    null_desc(result);
    if (!n)
        return errAEWrongDataType;
    long i = find_key(n->items, n->count, key);
    if (i < 0)
        return errAEDescNotFound;
    return AECoerceDesc(&n->items[i].desc, desired, result);
}

OSErr AEGetKeyPtr(const AERecord *rec, AEKeyword key, DescType desired, DescType *typeCode, void *data, Size max,
                  Size *actual)
{
    struct node *n = record(rec);
    if (!n)
        return errAEWrongDataType;
    long i = find_key(n->items, n->count, key);
    if (i < 0)
        return errAEDescNotFound;
    return read_out(&n->items[i].desc, desired, typeCode, data, max, actual);
}

OSErr AESizeOfKeyDesc(const AERecord *rec, AEKeyword key, DescType *typeCode, Size *size)
{
    struct node *n = record(rec);
    if (!n)
        return errAEWrongDataType;
    long i = find_key(n->items, n->count, key);
    if (i < 0)
        return errAEDescNotFound;
    if (typeCode)
        *typeCode = n->items[i].desc.descriptorType;
    if (size)
        *size = AEGetDescDataSize(&n->items[i].desc);
    return noErr;
}

OSErr AEDeleteKeyDesc(AERecord *rec, AEKeyword key)
{
    struct node *n = record(rec);
    if (!n)
        return errAEWrongDataType;
    long i = find_key(n->items, n->count, key);
    if (i < 0)
        return errAEDescNotFound;
    AEDisposeDesc(&n->items[i].desc);
    memmove(&n->items[i], &n->items[i + 1], (size_t)(n->count - i - 1) * sizeof *n->items);
    n->count--;
    return noErr;
}

/* ---- object specifiers (AEObjects.h) ----------------------------------------------------- */

/* A record of the given type holding the given keys; a missing container is
 * the null descriptor, as on a Mac. Each input is copied in. */
static OSErr keyed_record(DescType type, int n, const AEKeyword *keys, AEDesc *const *descs, AEDesc *result)
{
    if (!result)
        return paramErr;
    null_desc(result);
    AERecord rec;
    OSErr err = AECreateList(NULL, 0, true, &rec);
    for (int i = 0; !err && i < n; i++) {
        AEDesc none;
        null_desc(&none);
        err = AEPutKeyDesc(&rec, keys[i], descs[i] ? descs[i] : &none);
    }
    if (err) {
        AEDisposeDesc(&rec);
        return err;
    }
    rec.descriptorType = type;
    *result = rec;
    return noErr;
}
static void dispose_inputs(Boolean dispose, AEDesc *a, AEDesc *b)
{
    if (!dispose)
        return;
    if (a)
        AEDisposeDesc(a);
    if (b)
        AEDisposeDesc(b);
}

OSErr CreateObjSpecifier(DescType desiredClass, AEDesc *theContainer, DescType keyForm, AEDesc *keyData,
                         Boolean disposeInputs, AEDesc *objSpecifier)
{
    AEDesc cls, form;
    AECreateDesc(typeType, &desiredClass, sizeof desiredClass, &cls);
    AECreateDesc(typeEnumerated, &keyForm, sizeof keyForm, &form);
    AEKeyword keys[] = {keyAEDesiredClass, keyAEContainer, keyAEKeyForm, keyAEKeyData};
    AEDesc *descs[] = {&cls, theContainer, &form, keyData};
    OSErr err = keyed_record(typeObjectSpecifier, 4, keys, descs, objSpecifier);
    AEDisposeDesc(&cls);
    AEDisposeDesc(&form);
    dispose_inputs(disposeInputs, theContainer, keyData);
    return err;
}
OSErr CreateOffsetDescriptor(long theOffset, AEDesc *theDescriptor)
{
    SInt32 offset = (SInt32)theOffset;
    return AECreateDesc(typeSInt32, &offset, sizeof offset, theDescriptor);
}
OSErr CreateCompDescriptor(DescType op, AEDesc *operand1, AEDesc *operand2, Boolean disposeInputs, AEDesc *result)
{
    AEDesc opd;
    AECreateDesc(typeEnumerated, &op, sizeof op, &opd);
    AEKeyword keys[] = {keyAECompOperator, keyAEObject1, keyAEObject2};
    AEDesc *descs[] = {&opd, operand1, operand2};
    OSErr err = keyed_record(typeCompDescriptor, 3, keys, descs, result);
    AEDisposeDesc(&opd);
    dispose_inputs(disposeInputs, operand1, operand2);
    return err;
}
OSErr CreateLogicalDescriptor(AEDescList *terms, DescType op, Boolean disposeInputs, AEDesc *result)
{
    AEDesc opd;
    AECreateDesc(typeEnumerated, &op, sizeof op, &opd);
    AEKeyword keys[] = {keyAELogicalOperator, keyAELogicalTerms};
    AEDesc *descs[] = {&opd, terms};
    OSErr err = keyed_record(typeLogicalDescriptor, 2, keys, descs, result);
    AEDisposeDesc(&opd);
    dispose_inputs(disposeInputs, terms, NULL);
    return err;
}
OSErr CreateRangeDescriptor(AEDesc *rangeStart, AEDesc *rangeStop, Boolean disposeInputs, AEDesc *result)
{
    AEKeyword keys[] = {keyAERangeStart, keyAERangeStop};
    AEDesc *descs[] = {rangeStart, rangeStop};
    OSErr err = keyed_record(typeRangeDescriptor, 2, keys, descs, result);
    dispose_inputs(disposeInputs, rangeStart, rangeStop);
    return err;
}

/* ---- Apple events ------------------------------------------------------------------ */

static struct node *event(const AEDesc *d)
{
    struct node *n = record(d);
    return n && d->descriptorType == typeAppleEvent ? n : NULL;
}

OSErr AEPutAttributeDesc(AppleEvent *ev, AEKeyword key, const AEDesc *d)
{
    struct node *n = event(ev);
    if (!n || !d)
        return n ? paramErr : errAENotAppleEvent;
    return put_keyed(&n->attrs, &n->nattrs, &n->attrcap, key, d);
}

OSErr AEPutAttributePtr(AppleEvent *ev, AEKeyword key, DescType type, const void *data, Size size)
{
    AEDesc d;
    OSErr e = make_plain(type, data, size, &d);
    if (e != noErr)
        return e;
    e = AEPutAttributeDesc(ev, key, &d);
    AEDisposeDesc(&d);
    return e;
}

static OSErr get_attr(const AppleEvent *ev, AEKeyword key, AEDesc **out)
{
    struct node *n = event(ev);
    if (!n)
        return errAENotAppleEvent;
    long i = find_key(n->attrs, n->nattrs, key);
    if (i < 0)
        return errAEDescNotFound;
    *out = &n->attrs[i].desc;
    return noErr;
}

OSErr AEGetAttributeDesc(const AppleEvent *ev, AEKeyword key, DescType desired, AEDesc *result)
{
    if (!result)
        return paramErr;
    null_desc(result);
    AEDesc *d;
    OSErr e = get_attr(ev, key, &d);
    return e == noErr ? AECoerceDesc(d, desired, result) : e;
}

OSErr AEGetAttributePtr(const AppleEvent *ev, AEKeyword key, DescType desired, DescType *typeCode, void *data,
                        Size max, Size *actual)
{
    AEDesc *d;
    OSErr e = get_attr(ev, key, &d);
    return e == noErr ? read_out(d, desired, typeCode, data, max, actual) : e;
}

OSErr AESizeOfAttribute(const AppleEvent *ev, AEKeyword key, DescType *typeCode, Size *size)
{
    AEDesc *d;
    OSErr e = get_attr(ev, key, &d);
    if (e != noErr)
        return e;
    if (typeCode)
        *typeCode = d->descriptorType;
    if (size)
        *size = AEGetDescDataSize(d);
    return noErr;
}

static int16_t next_return_id(void)
{
    static int16_t last;
    static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
    pthread_mutex_lock(&lock);
    if (++last <= 0)
        last = 1;
    int16_t v = last;
    pthread_mutex_unlock(&lock);
    return v;
}

OSErr AECreateAppleEvent(AEEventClass cls, AEEventID eid, const AEAddressDesc *target, AEReturnID returnID,
                         AETransactionID transactionID, AppleEvent *result)
{
    if (!result)
        return paramErr;
    struct node *n = new_node(NODE_RECORD);
    result->descriptorType = typeAppleEvent;
    result->dataHandle = (AEDataStorage)n;
    if (returnID == kAutoGenerateReturnID)
        returnID = next_return_id();
    AEPutAttributePtr(result, keyEventClassAttr, typeType, &cls, sizeof cls);
    AEPutAttributePtr(result, keyEventIDAttr, typeType, &eid, sizeof eid);
    AEPutAttributePtr(result, keyReturnIDAttr, typeSInt16, &returnID, sizeof returnID);
    AEPutAttributePtr(result, keyTransactionIDAttr, typeSInt32, &transactionID, sizeof transactionID);
    if (target && target->descriptorType != typeNull)
        AEPutAttributeDesc(result, keyAddressAttr, target);
    return noErr;
}

OSErr AEPutParamDesc(AppleEvent *ev, AEKeyword key, const AEDesc *d) { return AEPutKeyDesc(ev, key, d); }
OSErr AEPutParamPtr(AppleEvent *ev, AEKeyword key, DescType type, const void *data, Size size)
{
    return AEPutKeyPtr(ev, key, type, data, size);
}
OSErr AEGetParamDesc(const AppleEvent *ev, AEKeyword key, DescType desired, AEDesc *result)
{
    return AEGetKeyDesc(ev, key, desired, result);
}
OSErr AEGetParamPtr(const AppleEvent *ev, AEKeyword key, DescType desired, DescType *actualType, void *data,
                    Size max, Size *actual)
{
    return AEGetKeyPtr(ev, key, desired, actualType, data, max, actual);
}
OSErr AESizeOfParam(const AppleEvent *ev, AEKeyword key, DescType *typeCode, Size *size)
{
    return AESizeOfKeyDesc(ev, key, typeCode, size);
}
OSErr AEDeleteParam(AppleEvent *ev, AEKeyword key) { return AEDeleteKeyDesc(ev, key); }

/* ---- handlers and sending ------------------------------------------------------------ */

struct handler {
    AEEventClass cls;
    AEEventID eid;
    AEEventHandlerUPP proc;
    void *refcon;
};
static struct handler *handlers;
static long nhandlers, handlercap;
static pthread_mutex_t handler_lock = PTHREAD_MUTEX_INITIALIZER;
static __thread AppleEvent *current_event;

OSErr AEInstallEventHandler(AEEventClass cls, AEEventID eid, AEEventHandlerUPP proc, void *refcon, Boolean isSys)
{
    if (!proc)
        return paramErr;
    pthread_mutex_lock(&handler_lock);
    long i = 0;
    for (; i < nhandlers; i++)
        if (handlers[i].cls == cls && handlers[i].eid == eid)
            break;
    if (i == nhandlers) {
        if (nhandlers == handlercap) {
            handlercap = handlercap ? handlercap * 2 : 8;
            handlers = realloc(handlers, (size_t)handlercap * sizeof *handlers);
        }
        nhandlers++;
    }
    handlers[i] = (struct handler){cls, eid, proc, refcon};
    pthread_mutex_unlock(&handler_lock);
    return noErr;
}

OSErr AERemoveEventHandler(AEEventClass cls, AEEventID eid, AEEventHandlerUPP proc, Boolean isSys)
{
    OSErr e = errAEHandlerNotFound;
    pthread_mutex_lock(&handler_lock);
    for (long i = 0; i < nhandlers; i++)
        if (handlers[i].cls == cls && handlers[i].eid == eid && (!proc || handlers[i].proc == proc)) {
            memmove(&handlers[i], &handlers[i + 1], (size_t)(nhandlers - i - 1) * sizeof *handlers);
            nhandlers--;
            e = noErr;
            break;
        }
    pthread_mutex_unlock(&handler_lock);
    return e;
}

static BOOL find_handler(AEEventClass cls, AEEventID eid, struct handler *out)
{
    BOOL found = NO;
    pthread_mutex_lock(&handler_lock);
    for (int pass = 0; pass < 4 && !found; pass++)
        for (long i = 0; i < nhandlers && !found; i++) {
            AEEventClass c = pass & 2 ? typeWildCard : cls;
            AEEventID d = pass & 1 ? typeWildCard : eid;
            if (handlers[i].cls == c && handlers[i].eid == d) {
                *out = handlers[i];
                found = YES;
            }
        }
    pthread_mutex_unlock(&handler_lock);
    return found;
}

OSErr AEGetEventHandler(AEEventClass cls, AEEventID eid, AEEventHandlerUPP *proc, void **refcon, Boolean isSys)
{
    struct handler h;
    if (!find_handler(cls, eid, &h))
        return errAEHandlerNotFound;
    if (proc)
        *proc = h.proc;
    if (refcon)
        *refcon = h.refcon;
    return noErr;
}

OSErr AEGetTheCurrentEvent(AppleEvent *ev)
{
    if (!ev)
        return paramErr;
    if (current_event)
        *ev = *current_event;
    else
        null_desc(ev);
    return noErr;
}

/* Whether an address names the app itself. */
static BOOL addresses_self(const AEDesc *target)
{
    struct node *n = node_of(target);
    if (!n || n->kind != NODE_PLAIN)
        return NO;
    if (target->descriptorType == typeKernelProcessID && n->size == sizeof(pid_t)) {
        pid_t p;
        memcpy(&p, n->bytes, sizeof p);
        return p == getpid();
    }
    if (target->descriptorType == typeProcessSerialNumber && n->size == sizeof(ProcessSerialNumber)) {
        ProcessSerialNumber psn;
        memcpy(&psn, n->bytes, sizeof psn);
        return psn.highLongOfPSN == 0 && psn.lowLongOfPSN == kCurrentProcess;
    }
    if (target->descriptorType == typeApplicationBundleID) {
        NSString *mine = [[NSBundle mainBundle] bundleIdentifier];
        NSString *named = [[[NSString alloc] initWithBytes:n->bytes length:(NSUInteger)n->size
                                                  encoding:NSUTF8StringEncoding] autorelease];
        return mine && [named isEqual:mine];
    }
    return NO;
}

OSStatus AESendMessage(const AppleEvent *ev, AppleEvent *reply, AESendMode mode, long timeout)
{
    if (reply)
        null_desc(reply);
    if (!event(ev))
        return errAENotAppleEvent;
    AEDesc *target;
    if (get_attr(ev, keyAddressAttr, &target) != noErr || !addresses_self(target)) {
        FVerboseOnce(@"an Apple event to another program wasn't sent: nothing on freemac receives Apple events");
        return procNotFound;
    }
    AEEventClass cls = 0;
    AEEventID eid = 0;
    AEGetAttributePtr(ev, keyEventClassAttr, typeType, NULL, &cls, sizeof cls, NULL);
    AEGetAttributePtr(ev, keyEventIDAttr, typeType, NULL, &eid, sizeof eid, NULL);
    struct handler h;
    if (!find_handler(cls, eid, &h))
        return errAEEventNotHandled;
    AppleEvent answer;
    AECreateAppleEvent(kCoreEventClass, kAEAnswer, NULL, kAutoGenerateReturnID, kAnyTransactionID, &answer);
    AppleEvent *outer = current_event;
    current_event = (AppleEvent *)ev;
    OSErr e = h.proc(ev, &answer, h.refcon);
    current_event = outer;
    if (e != noErr && find_key(record(&answer)->items, record(&answer)->count, keyErrorNumber) < 0) {
        int32_t n = e;
        AEPutParamPtr(&answer, keyErrorNumber, typeSInt32, &n, sizeof n);
    }
    if (reply && (mode & kAEWaitReply) == kAEWaitReply)
        *reply = answer;
    else
        AEDisposeDesc(&answer);
    return e == errAEEventNotHandled ? e : noErr;
}

OSErr AESend(const AppleEvent *ev, AppleEvent *reply, AESendMode mode, AESendPriority priority, long timeout,
             void *idle, void *filter)
{
    return (OSErr)AESendMessage(ev, reply, mode, timeout);
}

/* No one is asked: an event to another program can't be sent anyway, and one
 * to the app itself needs no consent. */
OSStatus AEDeterminePermissionToAutomateTarget(const AEAddressDesc *target, AEEventClass cls, AEEventID eid,
                                               Boolean ask)
{
    return addresses_self(target) ? noErr : procNotFound;
}

/* ---- Launch Services ------------------------------------------------------------------ */

OSStatus LSFindApplicationForInfo(OSType creator, CFStringRef bundleID, CFStringRef name, FSRef *outRef,
                                  CFURLRef *outURL)
{
    if (outURL)
        *outURL = NULL;
    if (bundleID && [(NSString *)bundleID isEqual:[[NSBundle mainBundle] bundleIdentifier]]) {
        NSURL *url = [[NSBundle mainBundle] bundleURL];
        if (outRef)
            CFURLGetFSRef((CFURLRef)url, outRef);
        if (outURL)
            *outURL = (CFURLRef)[url retain];
        return noErr;
    }
    return kLSApplicationNotFoundErr;
}

OSStatus LSOpenApplication(const LSApplicationParameters *params, ProcessSerialNumber *outPSN)
{
    return kLSApplicationNotFoundErr;
}

/* The desktop's own launcher opens it, as NSWorkspace's openURL: does. */
OSStatus LSOpenCFURLRef(CFURLRef url, CFURLRef *launched)
{
    if (launched)
        *launched = NULL;
    if (!url)
        return paramErr;
    @autoreleasepool {
        NSString *what = [(NSURL *)url isFileURL] ? [(NSURL *)url path] : [(NSURL *)url absoluteString];
        for (NSString *tool in @[ @"/usr/bin/gio", @"/usr/bin/xdg-open" ]) {
            if (![[NSFileManager defaultManager] isExecutableFileAtPath:tool])
                continue;
            NSArray *args = [tool hasSuffix:@"gio"] ? @[ @"open", what ] : @[ what ];
            NSTask *t = [[[NSTask alloc] init] autorelease];
            [t setLaunchPath:tool];
            [t setArguments:args];
            @try {
                [t launch];
            } @catch (NSException *x) {
                continue;
            }
            return noErr;
        }
    }
    return kLSApplicationNotFoundErr;
}

OSStatus LSOpenFromURLSpec(const LSLaunchURLSpec *spec, CFURLRef *launched)
{
    if (launched)
        *launched = NULL;
    if (!spec)
        return paramErr;
    if (spec->appURL)
        return kLSApplicationNotFoundErr;
    OSStatus r = noErr;
    for (NSURL *u in (NSArray *)spec->itemURLs)
        if ((r = LSOpenCFURLRef((CFURLRef)u, NULL)) != noErr)
            break;
    return r;
}

CFArrayRef LSCopyApplicationURLsForBundleIdentifier(CFStringRef bundleID, CFErrorRef *error)
{
    if (bundleID && [(NSString *)bundleID isEqual:[[NSBundle mainBundle] bundleIdentifier]])
        return (CFArrayRef)[[NSArray alloc] initWithObjects:[[NSBundle mainBundle] bundleURL], nil];
    if (error)
        *error = (CFErrorRef)[[NSError alloc] initWithDomain:NSOSStatusErrorDomain code:kLSApplicationNotFoundErr
                                                    userInfo:nil];
    return NULL;
}

CFArrayRef LSCopyApplicationURLsForURL(CFURLRef url, LSRolesMask roles) { return NULL; }

CFURLRef LSCopyDefaultApplicationURLForURL(CFURLRef url, LSRolesMask roles, CFErrorRef *error)
{
    if (error)
        *error = (CFErrorRef)[[NSError alloc] initWithDomain:NSOSStatusErrorDomain code:kLSApplicationNotFoundErr
                                                    userInfo:nil];
    return NULL;
}

CFStringRef LSCopyDefaultHandlerForURLScheme(CFStringRef scheme) { return NULL; }
CFArrayRef LSCopyAllHandlersForURLScheme(CFStringRef scheme) { return NULL; }
OSStatus LSSetDefaultHandlerForURLScheme(CFStringRef scheme, CFStringRef bundleID) { return kLSCannotSetInfoErr; }
CFStringRef LSCopyDefaultRoleHandlerForContentType(CFStringRef type, LSRolesMask role) { return NULL; }
OSStatus LSSetDefaultRoleHandlerForContentType(CFStringRef type, LSRolesMask role, CFStringRef bundleID)
{
    return kLSCannotSetInfoErr;
}
OSStatus LSRegisterURL(CFURLRef url, Boolean update) { return noErr; }
