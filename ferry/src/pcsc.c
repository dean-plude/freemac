/* SPDX-License-Identifier: GPL-3.0-or-later
 *
 * PCSC.framework: smart cards and security keys through PC/SC, the PC/SC
 * Workgroup's standard interface (freemac, KeePassXC's YubiKey support).
 * Linux has the same interface in pcsc-lite (libpcsclite.so.1, served by
 * the pcscd daemon), with the same calls, error codes, protocols and card
 * states. Only the sizes differ: a Mac's DWORD and LONG, its contexts and
 * card handles are 32 bits, pcsc-lite's are a C long (64 bits); so every
 * call is passed across here with its numbers widened or narrowed, and the
 * protocol headers (SCARD_IO_REQUEST, two DWORDs) are rebuilt.
 *
 * pcsc-lite is opened the first time a program makes a context, so a
 * program that never asks doesn't load it. Without it (or without pcscd
 * running) a context can't be made and the calls answer
 * SCARD_E_NO_SERVICE, as a system with no smart card service does.
 * FERRY_PCSC names another library to open in its place (the tests use it
 * to stand for a system without pcsc-lite). */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <pthread.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include "ferry.h"

#define NO_SERVICE ((int32_t)0x8010001D)    /* SCARD_E_NO_SERVICE */
#define INVALID_PARAMETER ((int32_t)0x80100004)
#define NO_MEMORY ((int32_t)0x80100006)
#define INSUFFICIENT_BUFFER ((int32_t)0x80100008)
#define MAC_AUTOALLOCATE 0xFFFFFFFFu      /* (DWORD)-1 */
#define HOST_AUTOALLOCATE ((unsigned long)-1)

struct mac_io_request { uint32_t protocol, length; };
struct host_io_request { unsigned long protocol, length; };

/* The protocol headers a Mac program names by their address. */
const struct mac_io_request ferry_pcsc_t0 = {1, sizeof(struct mac_io_request)};
const struct mac_io_request ferry_pcsc_t1 = {2, sizeof(struct mac_io_request)};
const struct mac_io_request ferry_pcsc_raw = {4, sizeof(struct mac_io_request)};

static void *lib;
static void open_pcsc(void)
{
    const char *other = getenv("FERRY_PCSC");
    lib = dlopen(other && *other ? other : "libpcsclite.so.1", RTLD_NOW | RTLD_LOCAL);
}
static void *call(const char *name)
{
    static pthread_once_t once = PTHREAD_ONCE_INIT;
    pthread_once(&once, open_pcsc);
    return lib ? dlsym(lib, name) : NULL;
}

static int32_t narrow(long rv) { return (int32_t)(uint32_t)(unsigned long)rv; }

static int32_t mac_SCardEstablishContext(uint32_t scope, const void *r1, const void *r2, int32_t *context)
{
    long (*f)(unsigned long, const void *, const void *, long *) = call("SCardEstablishContext");
    if (!context)
        return INVALID_PARAMETER;
    if (!f)
        return NO_SERVICE;
    long c = 0;
    long rv = f(scope, r1, r2, &c);
    *context = (int32_t)c;
    return narrow(rv);
}

#define ONE_HANDLE(mac, host)                                                                                      \
    static int32_t mac(int32_t h)                                                                                  \
    {                                                                                                              \
        long (*f)(long) = call(host);                                                                              \
        return f ? narrow(f(h)) : NO_SERVICE;                                                                      \
    }
ONE_HANDLE(mac_SCardReleaseContext, "SCardReleaseContext")
ONE_HANDLE(mac_SCardIsValidContext, "SCardIsValidContext")
ONE_HANDLE(mac_SCardCancel, "SCardCancel")
ONE_HANDLE(mac_SCardBeginTransaction, "SCardBeginTransaction")

#define HANDLE_AND_DISPOSITION(mac, host)                                                                          \
    static int32_t mac(int32_t h, uint32_t disposition)                                                            \
    {                                                                                                              \
        long (*f)(long, unsigned long) = call(host);                                                               \
        return f ? narrow(f(h, disposition)) : NO_SERVICE;                                                         \
    }
HANDLE_AND_DISPOSITION(mac_SCardEndTransaction, "SCardEndTransaction")
HANDLE_AND_DISPOSITION(mac_SCardDisconnect, "SCardDisconnect")

/* A list of names (multi-strings) or bytes into the program's buffer: as
 * asked, sized only, or allocated here when it asks SCARD_AUTOALLOCATE (the
 * program frees it with SCardFreeMemory). */
static int32_t hand_back(long rv, char *got, unsigned long n, void *buf, uint32_t *len, int allocate,
                         void (*free_host)(long, const void *), long context)
{
    if (rv == 0 && allocate) {
        char *copy = malloc(n ? n : 1);
        if (!copy) {
            free_host(context, got);
            return NO_MEMORY;
        }
        memcpy(copy, got, n);
        free_host(context, got);
        *(char **)buf = copy;
    }
    *len = (uint32_t)n;
    return narrow(rv);
}

static int32_t mac_SCardListReaders(int32_t context, const char *groups, char *readers, uint32_t *len)
{
    long (*f)(long, const char *, char *, unsigned long *) = call("SCardListReaders");
    void (*free_host)(long, const void *) = call("SCardFreeMemory");
    if (!len)
        return INVALID_PARAMETER;
    if (!f || !free_host)
        return NO_SERVICE;
    int allocate = readers && *len == MAC_AUTOALLOCATE;
    unsigned long n = allocate ? HOST_AUTOALLOCATE : *len;
    char *got = NULL;
    long rv = f(context, groups, allocate ? (char *)&got : readers, &n);
    return hand_back(rv, got, n, readers, len, allocate, free_host, context);
}

static int32_t mac_SCardListReaderGroups(int32_t context, char *groups, uint32_t *len)
{
    long (*f)(long, char *, unsigned long *) = call("SCardListReaderGroups");
    void (*free_host)(long, const void *) = call("SCardFreeMemory");
    if (!len)
        return INVALID_PARAMETER;
    if (!f || !free_host)
        return NO_SERVICE;
    int allocate = groups && *len == MAC_AUTOALLOCATE;
    unsigned long n = allocate ? HOST_AUTOALLOCATE : *len;
    char *got = NULL;
    long rv = f(context, allocate ? (char *)&got : groups, &n);
    return hand_back(rv, got, n, groups, len, allocate, free_host, context);
}

static int32_t mac_SCardFreeMemory(int32_t context, const void *memory)
{
    (void)context;
    free((void *)memory);
    return 0;
}

static int32_t mac_SCardConnect(int32_t context, const char *reader, uint32_t share, uint32_t protocols,
                                int32_t *card, uint32_t *active)
{
    long (*f)(long, const char *, unsigned long, unsigned long, long *, unsigned long *) = call("SCardConnect");
    if (!f)
        return NO_SERVICE;
    long h = 0;
    unsigned long p = 0;
    long rv = f(context, reader, share, protocols, &h, &p);
    if (card)
        *card = (int32_t)h;
    if (active)
        *active = (uint32_t)p;
    return narrow(rv);
}

static int32_t mac_SCardReconnect(int32_t card, uint32_t share, uint32_t protocols, uint32_t init, uint32_t *active)
{
    long (*f)(long, unsigned long, unsigned long, unsigned long, unsigned long *) = call("SCardReconnect");
    if (!f)
        return NO_SERVICE;
    unsigned long p = 0;
    long rv = f(card, share, protocols, init, &p);
    if (active)
        *active = (uint32_t)p;
    return narrow(rv);
}

static int32_t mac_SCardStatus(int32_t card, char *names, uint32_t *names_len, uint32_t *state, uint32_t *protocol,
                               unsigned char *atr, uint32_t *atr_len)
{
    long (*f)(long, char *, unsigned long *, unsigned long *, unsigned long *, unsigned char *, unsigned long *) =
        call("SCardStatus");
    void (*free_host)(long, const void *) = call("SCardFreeMemory");
    if (!f || !free_host)
        return NO_SERVICE;
    int alloc_names = names && names_len && *names_len == MAC_AUTOALLOCATE;
    int alloc_atr = atr && atr_len && *atr_len == MAC_AUTOALLOCATE;
    unsigned long nn = names_len ? (alloc_names ? HOST_AUTOALLOCATE : *names_len) : 0;
    unsigned long na = atr_len ? (alloc_atr ? HOST_AUTOALLOCATE : *atr_len) : 0;
    unsigned long s = 0, p = 0;
    char *got_names = NULL;
    unsigned char *got_atr = NULL;
    long rv = f(card, alloc_names ? (char *)&got_names : names, names_len ? &nn : NULL, &s, &p,
                alloc_atr ? (unsigned char *)&got_atr : atr, atr_len ? &na : NULL);
    if (state)
        *state = (uint32_t)s;
    if (protocol)
        *protocol = (uint32_t)p;
    int32_t out = narrow(rv);
    /* SCardStatus's one context-free free: pcsc-lite takes the card's context
     * as 0 there too */
    if (names_len)
        out = hand_back(rv, got_names, nn, names, names_len, alloc_names, free_host, 0);
    if (atr_len) {
        int32_t a = hand_back(rv, (char *)got_atr, na, atr, atr_len, alloc_atr, free_host, 0);
        if (!out)
            out = a;
    }
    return out;
}

/* A Mac header and what follows it (the same bytes past the two numbers)
 * as pcsc-lite's: the program's own header, or the system's for T=0, T=1
 * and raw. */
static int host_request(const struct mac_io_request *mac, struct host_io_request *out)
{
    if (!mac)
        return 0;
    out->protocol = mac->protocol;
    out->length = sizeof *out;
    return 1;
}

static int32_t mac_SCardTransmit(int32_t card, const struct mac_io_request *send_pci, const unsigned char *send,
                                 uint32_t send_len, struct mac_io_request *recv_pci, unsigned char *recv,
                                 uint32_t *recv_len)
{
    long (*f)(long, const struct host_io_request *, const unsigned char *, unsigned long, struct host_io_request *,
              unsigned char *, unsigned long *) = call("SCardTransmit");
    if (!f)
        return NO_SERVICE;
    if (!recv_len)
        return INVALID_PARAMETER;
    struct host_io_request hs, hr;
    int have_send = host_request(send_pci, &hs), have_recv = host_request(recv_pci, &hr);
    unsigned long n = *recv_len;
    long rv = f(card, have_send ? &hs : NULL, send, send_len, have_recv ? &hr : NULL, recv, &n);
    if (have_recv) {
        recv_pci->protocol = (uint32_t)hr.protocol;
        recv_pci->length = sizeof *recv_pci;
    }
    *recv_len = (uint32_t)n;
    return narrow(rv);
}

static int32_t mac_SCardControl(int32_t card, uint32_t code, const void *send, uint32_t send_len, void *recv,
                                uint32_t recv_len, uint32_t *returned)
{
    long (*f)(long, unsigned long, const void *, unsigned long, void *, unsigned long, unsigned long *) =
        call("SCardControl");
    if (!f)
        return NO_SERVICE;
    unsigned long n = 0;
    long rv = f(card, code, send, send_len, recv, recv_len, &n);
    if (returned)
        *returned = (uint32_t)n;
    return narrow(rv);
}

static int32_t mac_SCardGetAttrib(int32_t card, uint32_t id, unsigned char *attr, uint32_t *len)
{
    long (*f)(long, unsigned long, unsigned char *, unsigned long *) = call("SCardGetAttrib");
    if (!f)
        return NO_SERVICE;
    if (!len)
        return INVALID_PARAMETER;
    if (attr && *len == MAC_AUTOALLOCATE)
        return INSUFFICIENT_BUFFER;   /* asked by size first, as programs do */
    unsigned long n = *len;
    long rv = f(card, id, attr, &n);
    *len = (uint32_t)n;
    return narrow(rv);
}

static const struct ferry_symbol pcsc_symbols[] = {
    {"SCardEstablishContext", mac_SCardEstablishContext},
    {"SCardReleaseContext", mac_SCardReleaseContext},
    {"SCardIsValidContext", mac_SCardIsValidContext},
    {"SCardCancel", mac_SCardCancel},
    {"SCardListReaders", mac_SCardListReaders},
    {"SCardListReaderGroups", mac_SCardListReaderGroups},
    {"SCardFreeMemory", mac_SCardFreeMemory},
    {"SCardConnect", mac_SCardConnect},
    {"SCardReconnect", mac_SCardReconnect},
    {"SCardDisconnect", mac_SCardDisconnect},
    {"SCardBeginTransaction", mac_SCardBeginTransaction},
    {"SCardEndTransaction", mac_SCardEndTransaction},
    {"SCardStatus", mac_SCardStatus},
    {"SCardTransmit", mac_SCardTransmit},
    {"SCardControl", mac_SCardControl},
    {"SCardControl132", mac_SCardControl},
    {"SCardGetAttrib", mac_SCardGetAttrib},
    {"g_rgSCardT0Pci", (void *)&ferry_pcsc_t0},
    {"g_rgSCardT1Pci", (void *)&ferry_pcsc_t1},
    {"g_rgSCardRawPci", (void *)&ferry_pcsc_raw},
    {NULL, NULL},
};

/* PCSC's own calls, never pcsc-lite's directly (their numbers are wider). */
void *ferry_pcsc_lookup(const char *name)
{
    for (const struct ferry_symbol *s = pcsc_symbols; s->name; s++)
        if (!strcmp(s->name, name))
            return s->addr;
    return NULL;
}
