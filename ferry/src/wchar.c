/* SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Wide characters, multibyte conversions and per-thread locales (<wchar.h>,
 * <wctype.h>, <xlocale.h>), and the C++ ABI's __cxa_atexit, as a Mac's
 * libSystem offers them. C++ programs use these through their libc++
 * headers; C programs may too.
 *
 * wchar_t and wint_t are 32-bit on both systems and mean the same, so the
 * wide string calls are this system's own. What differs:
 *
 *   - mbstate_t is 128 bytes on a Mac and 8 here. A Mac program's state is
 *     the larger, so this system's calls fit in it; a zeroed one is the
 *     initial state on both.
 *   - locale_t: a Mac passes NULL for the "C" locale (Linux has no such
 *     shorthand) and (locale_t)-1 for the global one, as Linux does. Mac
 *     category masks are numbered differently.
 *   - wctype_t and wctrans_t are small numbers on a Mac and pointers into
 *     tables here, so Ferry gives out its own.
 *   - Many of the Mac's *_l calls have no Linux twin; they switch the
 *     thread's locale around the plain call.
 *
 * Written from Apple's public documentation (the xlocale(3), wctype(3) and
 * related manual pages) and POSIX.
 */
#define _GNU_SOURCE
#include <ctype.h>
#include <inttypes.h>
#include <langinfo.h>
#include <locale.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <wchar.h>
#include <wctype.h>

#include "ferry.h"

/* ---- locales --------------------------------------------------------------------- */

static locale_t c_locale;

static locale_t to_linux(locale_t loc)
{
    if (loc)
        return loc;
    if (!c_locale)
        c_locale = newlocale(LC_ALL_MASK, "C", (locale_t)0);
    return c_locale;
}

/* Mac masks: collate 1, ctype 2, messages 4, monetary 8, numeric 16, time 32 */
static int mask_to_linux(int mask)
{
    int m = 0;
    if (mask & 1) m |= LC_COLLATE_MASK;
    if (mask & 2) m |= LC_CTYPE_MASK;
    if (mask & 4) m |= LC_MESSAGES_MASK;
    if (mask & 8) m |= LC_MONETARY_MASK;
    if (mask & 16) m |= LC_NUMERIC_MASK;
    if (mask & 32) m |= LC_TIME_MASK;
    return m;
}

static locale_t mac_newlocale(int mask, const char *name, locale_t base)
{
    if (base == LC_GLOBAL_LOCALE)
        base = duplocale(LC_GLOBAL_LOCALE);
    else if (!base)
        base = (locale_t)0;
    else
        base = duplocale(base);
    locale_t l = newlocale(mask_to_linux(mask), name ? name : "C", base);
    if (!l && base)
        freelocale(base);
    return l;
}

static locale_t mac_duplocale(locale_t loc) { return duplocale(to_linux(loc)); }

static int mac_freelocale(locale_t loc)
{
    if (loc && loc != LC_GLOBAL_LOCALE && loc != c_locale)
        freelocale(loc);
    return 0;
}

static locale_t mac_uselocale(locale_t loc)
{
    locale_t old = uselocale(loc);
    return old;
}

/* Runs the plain call under loc, on this thread. */
#define UNDER(loc, expr)                                                                                       \
    do {                                                                                                       \
        locale_t old_ = uselocale(to_linux(loc));                                                              \
        __typeof__(expr) r_ = (expr);                                                                          \
        uselocale(old_);                                                                                       \
        return r_;                                                                                             \
    } while (0)

static int mac_mb_cur_max(void) { return (int)MB_CUR_MAX; }
static int mac_mb_cur_max_l(locale_t loc) { UNDER(loc, (int)MB_CUR_MAX); }

/* A Mac's struct lconv: the same as this system's but for the order of
 * the last four international money fields, kept per thread as
 * localeconv's answer is. */
struct mac_lconv {
    char *strings[10];
    char int_frac_digits, frac_digits, p_cs_precedes, p_sep_by_space, n_cs_precedes, n_sep_by_space, p_sign_posn,
        n_sign_posn, int_p_cs_precedes, int_n_cs_precedes, int_p_sep_by_space, int_n_sep_by_space, int_p_sign_posn,
        int_n_sign_posn;
};
static __thread struct mac_lconv mac_lconv_answer;

static struct mac_lconv *mac_lconv_of(const struct lconv *l)
{
    struct mac_lconv *m = &mac_lconv_answer;
    char *strings[10] = {l->decimal_point,     l->thousands_sep,     l->grouping,     l->int_curr_symbol,
                         l->currency_symbol,   l->mon_decimal_point, l->mon_thousands_sep, l->mon_grouping,
                         l->positive_sign,     l->negative_sign};
    memcpy(m->strings, strings, sizeof strings);
    m->int_frac_digits = l->int_frac_digits;
    m->frac_digits = l->frac_digits;
    m->p_cs_precedes = l->p_cs_precedes;
    m->p_sep_by_space = l->p_sep_by_space;
    m->n_cs_precedes = l->n_cs_precedes;
    m->n_sep_by_space = l->n_sep_by_space;
    m->p_sign_posn = l->p_sign_posn;
    m->n_sign_posn = l->n_sign_posn;
    m->int_p_cs_precedes = l->int_p_cs_precedes;
    m->int_n_cs_precedes = l->int_n_cs_precedes;
    m->int_p_sep_by_space = l->int_p_sep_by_space;
    m->int_n_sep_by_space = l->int_n_sep_by_space;
    m->int_p_sign_posn = l->int_p_sign_posn;
    m->int_n_sign_posn = l->int_n_sign_posn;
    return m;
}
static struct mac_lconv *mac_localeconv(void) { return mac_lconv_of(localeconv()); }
static struct mac_lconv *mac_localeconv_l(locale_t loc) { UNDER(loc, mac_lconv_of(localeconv())); }

static const char *mac_querylocale(int mask, locale_t loc)
{
    static const struct { int mac, category; } cats[] = {
        {1, LC_COLLATE}, {2, LC_CTYPE}, {4, LC_MESSAGES}, {8, LC_MONETARY}, {16, LC_NUMERIC}, {32, LC_TIME},
    };
    locale_t l = loc == LC_GLOBAL_LOCALE ? uselocale((locale_t)0) : to_linux(loc);
    for (size_t i = 0; i < sizeof cats / sizeof cats[0]; i++)
        if (mask & cats[i].mac)
            return nl_langinfo_l(_NL_ITEM(cats[i].category, _NL_ITEM_INDEX(-1)), l);
    return "C";
}

/* ---- character classes under a locale -------------------------------------------- */

#define CLASS_L2(name, wname)                                                                                  \
    static int mac_##name##_l(int c, locale_t loc) { return name##_l(c, to_linux(loc)); }                      \
    static int mac_##wname##_l(wint_t c, locale_t loc) { return wname##_l(c, to_linux(loc)); }
CLASS_L2(isalnum, iswalnum)
CLASS_L2(isalpha, iswalpha)
CLASS_L2(isblank, iswblank)
CLASS_L2(iscntrl, iswcntrl)
CLASS_L2(isdigit, iswdigit)
CLASS_L2(isgraph, iswgraph)
CLASS_L2(islower, iswlower)
CLASS_L2(isprint, iswprint)
CLASS_L2(ispunct, iswpunct)
CLASS_L2(isspace, iswspace)
CLASS_L2(isupper, iswupper)
CLASS_L2(isxdigit, iswxdigit)
static int mac_tolower_l(int c, locale_t loc) { return tolower_l(c, to_linux(loc)); }
static int mac_toupper_l(int c, locale_t loc) { return toupper_l(c, to_linux(loc)); }
static wint_t mac_towlower_l(wint_t c, locale_t loc) { return towlower_l(c, to_linux(loc)); }
static wint_t mac_towupper_l(wint_t c, locale_t loc) { return towupper_l(c, to_linux(loc)); }

/* wctype_t: the Mac's class bits (<ctype.h>'s _CTYPE_*) */
static const struct { const char *name; uint32_t bits; int (*test)(wint_t); } wclasses[] = {
    {"alnum", 0x100 | 0x400, iswalnum}, {"alpha", 0x100, iswalpha}, {"blank", 0x20000, iswblank},
    {"cntrl", 0x200, iswcntrl},         {"digit", 0x400, iswdigit}, {"graph", 0x800, iswgraph},
    {"lower", 0x1000, iswlower},        {"print", 0x40000, iswprint}, {"punct", 0x2000, iswpunct},
    {"space", 0x4000, iswspace},        {"upper", 0x8000, iswupper}, {"xdigit", 0x10000, iswxdigit},
};

static uint32_t mac_wctype(const char *name)
{
    for (size_t i = 0; i < sizeof wclasses / sizeof wclasses[0]; i++)
        if (name && !strcmp(name, wclasses[i].name))
            return wclasses[i].bits;
    return 0;
}

static int mac_iswctype(wint_t c, uint32_t t)
{
    if (!t)
        return 0;
    if (t == (0x100 | 0x400))
        return iswalnum(c);
    for (size_t i = 0; i < sizeof wclasses / sizeof wclasses[0]; i++)
        if (wclasses[i].bits == t)
            return wclasses[i].test(c);
    /* several bits: any of them, as the Mac's table lookup answers */
    for (size_t i = 0; i < sizeof wclasses / sizeof wclasses[0]; i++)
        if ((wclasses[i].bits & t) == wclasses[i].bits && wclasses[i].test(c))
            return 1;
    return 0;
}
static int mac_iswctype_l(wint_t c, uint32_t t, locale_t loc) { UNDER(loc, mac_iswctype(c, t)); }
static uint32_t mac_wctype_l(const char *name, locale_t loc) { return mac_wctype(name); }

/* wctrans_t: 1 lower, 2 upper */
static int mac_wctrans(const char *name)
{
    return !name ? 0 : !strcmp(name, "tolower") ? 1 : !strcmp(name, "toupper") ? 2 : 0;
}
static wint_t mac_towctrans(wint_t c, int t) { return t == 1 ? towlower(c) : t == 2 ? towupper(c) : c; }

/* ---- numbers and text under a locale ---------------------------------------------- */

static long mac_strtol_l(const char *s, char **end, int base, locale_t loc) { return strtol_l(s, end, base, to_linux(loc)); }
static unsigned long mac_strtoul_l(const char *s, char **end, int base, locale_t loc)
{
    return strtoul_l(s, end, base, to_linux(loc));
}
static long long mac_strtoll_l(const char *s, char **end, int base, locale_t loc)
{
    return strtoll_l(s, end, base, to_linux(loc));
}
static unsigned long long mac_strtoull_l(const char *s, char **end, int base, locale_t loc)
{
    return strtoull_l(s, end, base, to_linux(loc));
}
static double mac_strtod_l(const char *s, char **end, locale_t loc) { return strtod_l(s, end, to_linux(loc)); }
static float mac_strtof_l(const char *s, char **end, locale_t loc) { return strtof_l(s, end, to_linux(loc)); }
static long double mac_strtold_l(const char *s, char **end, locale_t loc) { return strtold_l(s, end, to_linux(loc)); }
static int mac_strcoll_l(const char *a, const char *b, locale_t loc) { return strcoll_l(a, b, to_linux(loc)); }
static size_t mac_strxfrm_l(char *d, const char *s, size_t n, locale_t loc) { return strxfrm_l(d, s, n, to_linux(loc)); }
static int mac_wcscoll_l(const wchar_t *a, const wchar_t *b, locale_t loc) { return wcscoll_l(a, b, to_linux(loc)); }
static size_t mac_wcsxfrm_l(wchar_t *d, const wchar_t *s, size_t n, locale_t loc)
{
    return wcsxfrm_l(d, s, n, to_linux(loc));
}
/* strptime_l (freemac 1.225, Ferry 0.49.0; TransformerKit's date transformers) */
static char *mac_strptime_l(const char *s, const char *f, struct tm *tm, locale_t loc)
{
    return strptime_l(s, f, tm, to_linux(loc));
}
static size_t mac_strftime_l(char *s, size_t n, const char *f, const struct tm *tm, locale_t loc)
{
    return strftime_l(s, n, f, tm, to_linux(loc));
}

static int mac_snprintf_l(char *s, size_t n, locale_t loc, const char *f, ...)
{
    va_list ap;
    va_start(ap, f);
    locale_t old = uselocale(to_linux(loc));
    int r = vsnprintf(s, n, f, ap);
    uselocale(old);
    va_end(ap);
    return r;
}
static int mac_asprintf_l(char **s, locale_t loc, const char *f, ...)
{
    va_list ap;
    va_start(ap, f);
    locale_t old = uselocale(to_linux(loc));
    int r = vasprintf(s, f, ap);
    uselocale(old);
    va_end(ap);
    return r;
}
/* The va_list forms, and sprintf's (darktable, through GLib's printf) */
static int mac_vsnprintf_l(char *s, size_t n, locale_t loc, const char *f, va_list ap)
{
    locale_t old = uselocale(to_linux(loc));
    int r = vsnprintf(s, n, f, ap);
    uselocale(old);
    return r;
}
static int mac_vasprintf_l(char **s, locale_t loc, const char *f, va_list ap)
{
    locale_t old = uselocale(to_linux(loc));
    int r = vasprintf(s, f, ap);
    uselocale(old);
    return r;
}
static int mac_vsprintf_l(char *s, locale_t loc, const char *f, va_list ap)
{
    locale_t old = uselocale(to_linux(loc));
    int r = vsprintf(s, f, ap);
    uselocale(old);
    return r;
}
static int mac_sprintf_l(char *s, locale_t loc, const char *f, ...)
{
    va_list ap;
    va_start(ap, f);
    int r = mac_vsprintf_l(s, loc, f, ap);
    va_end(ap);
    return r;
}
static int mac_vsscanf_l(const char *s, locale_t loc, const char *f, va_list ap)
{
    locale_t old = uselocale(to_linux(loc));
    int r = vsscanf(s, f, ap);
    uselocale(old);
    return r;
}
static int mac_sscanf_l(const char *s, locale_t loc, const char *f, ...)
{
    va_list ap;
    va_start(ap, f);
    locale_t old = uselocale(to_linux(loc));
    int r = vsscanf(s, f, ap);
    uselocale(old);
    va_end(ap);
    return r;
}

/* ---- multibyte conversions under a locale ----------------------------------------- */

static wint_t mac_btowc_l(int c, locale_t loc) { UNDER(loc, btowc(c)); }
static int mac_wctob_l(wint_t c, locale_t loc) { UNDER(loc, wctob(c)); }
static size_t mac_mbrtowc_l(wchar_t *w, const char *s, size_t n, mbstate_t *st, locale_t loc)
{
    UNDER(loc, mbrtowc(w, s, n, st));
}
static size_t mac_wcrtomb_l(char *s, wchar_t w, mbstate_t *st, locale_t loc) { UNDER(loc, wcrtomb(s, w, st)); }
static size_t mac_mbrlen_l(const char *s, size_t n, mbstate_t *st, locale_t loc) { UNDER(loc, mbrlen(s, n, st)); }
static int mac_mbtowc_l(wchar_t *w, const char *s, size_t n, locale_t loc) { UNDER(loc, mbtowc(w, s, n)); }
static int mac_wctomb_l(char *s, wchar_t w, locale_t loc) { UNDER(loc, wctomb(s, w)); }
static size_t mac_mbsrtowcs_l(wchar_t *d, const char **s, size_t n, mbstate_t *st, locale_t loc)
{
    UNDER(loc, mbsrtowcs(d, s, n, st));
}
static size_t mac_wcsrtombs_l(char *d, const wchar_t **s, size_t n, mbstate_t *st, locale_t loc)
{
    UNDER(loc, wcsrtombs(d, s, n, st));
}
static size_t mac_mbsnrtowcs_l(wchar_t *d, const char **s, size_t nms, size_t n, mbstate_t *st, locale_t loc)
{
    UNDER(loc, mbsnrtowcs(d, s, nms, n, st));
}
static size_t mac_wcsnrtombs_l(char *d, const wchar_t **s, size_t nwc, size_t n, mbstate_t *st, locale_t loc)
{
    UNDER(loc, wcsnrtombs(d, s, nwc, n, st));
}
static size_t mac_mbstowcs_l(wchar_t *d, const char *s, size_t n, locale_t loc) { UNDER(loc, mbstowcs(d, s, n)); }
static size_t mac_wcstombs_l(char *d, const wchar_t *s, size_t n, locale_t loc) { UNDER(loc, wcstombs(d, s, n)); }
static int mac_mblen_l(const char *s, size_t n, locale_t loc) { UNDER(loc, mblen(s, n)); }

/* ---- the table ------------------------------------------------------------------------ */

extern int __cxa_atexit(void (*fn)(void *), void *arg, void *dso);
extern void __cxa_finalize(void *dso);

#define SAME(name) {#name, (void *)name}
#define MAC(name) {#name, (void *)mac_##name}


/* ---- nl_langinfo: a Mac's item numbers ------------------------------------------- */

static nl_item langinfo_to_linux(int mac)
{
    static const nl_item first[] = {CODESET, D_T_FMT, D_FMT, T_FMT, T_FMT_AMPM, AM_STR, PM_STR};
    if (mac >= 0 && mac <= 6)
        return first[mac];
    if (mac >= 7 && mac <= 13)
        return DAY_1 + (mac - 7);
    if (mac >= 14 && mac <= 20)
        return ABDAY_1 + (mac - 14);
    if (mac >= 21 && mac <= 32)
        return MON_1 + (mac - 21);
    if (mac >= 33 && mac <= 44)
        return ABMON_1 + (mac - 33);
    static const nl_item rest[] = {ERA,     ERA_D_FMT, ERA_D_T_FMT, ERA_T_FMT, ALT_DIGITS, RADIXCHAR,
                                   THOUSEP, YESEXPR,   NOEXPR,      YESSTR,    NOSTR,      CRNCYSTR};
    if (mac >= 45 && mac <= 56)
        return rest[mac - 45];
    return -1;
}

/* D_MD_ORDER, a Mac's own: "md" where the day follows the month in D_FMT. */
static char *item_under(nl_item n, locale_t l)
{
    return l == LC_GLOBAL_LOCALE ? nl_langinfo(n) : nl_langinfo_l(n, l);
}

static char *md_order(locale_t l)
{
    const char *f = item_under(D_FMT, l);
    const char *m = strpbrk(f, "mbB"), *d = strpbrk(f, "de");
    return (char *)(d && m && d < m ? "dm" : "md");
}

static char *mac_nl_langinfo_l(int item, locale_t loc)
{
    /* the thread's own locale, which may be the global one */
    locale_t l = loc == LC_GLOBAL_LOCALE ? uselocale((locale_t)0) : to_linux(loc);
    if (item == 57)
        return md_order(l);
    nl_item n = langinfo_to_linux(item);
    if (n == -1)
        return (char *)"";
    char *v = item_under(n, l);
    /* a Mac names plain ASCII "US-ASCII" */
    return n == CODESET && !strcmp(v, "ANSI_X3.4-1968") ? (char *)"US-ASCII" : v;
}

static char *mac_nl_langinfo(int item) { return mac_nl_langinfo_l(item, LC_GLOBAL_LOCALE); }

/* number conversions under a locale (freemac 1.263) */
static long mac_wcstol_l(const wchar_t *s, wchar_t **e, int b, locale_t loc) { UNDER(loc, wcstol(s, e, b)); }
static unsigned long mac_wcstoul_l(const wchar_t *s, wchar_t **e, int b, locale_t loc) { UNDER(loc, wcstoul(s, e, b)); }
static long long mac_wcstoll_l(const wchar_t *s, wchar_t **e, int b, locale_t loc) { UNDER(loc, wcstoll(s, e, b)); }
static unsigned long long mac_wcstoull_l(const wchar_t *s, wchar_t **e, int b, locale_t loc) { UNDER(loc, wcstoull(s, e, b)); }
static double mac_wcstod_l(const wchar_t *s, wchar_t **e, locale_t loc) { UNDER(loc, wcstod(s, e)); }
static float mac_wcstof_l(const wchar_t *s, wchar_t **e, locale_t loc) { UNDER(loc, wcstof(s, e)); }

const struct ferry_symbol ferry_wchar_symbols[] = {
    {"nl_langinfo", mac_nl_langinfo},
    {"nl_langinfo_l", mac_nl_langinfo_l},
    MAC(wcstol_l), MAC(wcstoul_l), MAC(wcstoll_l), MAC(wcstoull_l), MAC(wcstod_l), MAC(wcstof_l),
    /* wide strings: the same calls */
    SAME(wcslen), SAME(wcsnlen), SAME(wcscpy), SAME(wcsncpy), SAME(wcscat), SAME(wcsncat), SAME(wcscmp),
    SAME(wcsncmp), SAME(wcscoll), SAME(wcsxfrm), SAME(wcschr), SAME(wcsrchr), SAME(wcsstr), SAME(wcsspn),
    SAME(wcscspn), SAME(wcspbrk), SAME(wcstok), SAME(wcsdup), SAME(wcscasecmp), SAME(wcsncasecmp),
    SAME(wcpcpy), SAME(wcpncpy), SAME(wmemcpy), SAME(wmemmove), SAME(wmemset), SAME(wmemcmp), SAME(wmemchr),
    SAME(wcstol), SAME(wcstoul), SAME(wcstoll), SAME(wcstoull), SAME(wcstod), SAME(wcstof), SAME(wcstold),
    SAME(wcstoimax), SAME(wcstoumax), SAME(swprintf), SAME(vswprintf), SAME(swscanf), SAME(vswscanf),
    SAME(wcsftime), SAME(wcwidth), SAME(wcswidth),
    /* multibyte conversions */
    SAME(btowc), SAME(wctob), SAME(mbsinit), SAME(mbrlen), SAME(mbrtowc), SAME(wcrtomb), SAME(mbsrtowcs),
    SAME(wcsrtombs), SAME(mbsnrtowcs), SAME(wcsnrtombs), SAME(mblen), SAME(mbtowc), SAME(wctomb),
    SAME(mbstowcs), SAME(wcstombs),
    /* wide character classes */
    SAME(iswalnum), SAME(iswalpha), SAME(iswblank), SAME(iswcntrl), SAME(iswdigit), SAME(iswgraph),
    SAME(iswlower), SAME(iswprint), SAME(iswpunct), SAME(iswspace), SAME(iswupper), SAME(iswxdigit),
    SAME(towlower), SAME(towupper), MAC(wctype), MAC(iswctype), MAC(wctrans), MAC(towctrans),
    /* locales */
    MAC(newlocale), MAC(duplocale), MAC(freelocale), MAC(uselocale), MAC(querylocale), MAC(localeconv_l),
    MAC(localeconv), {"___mb_cur_max", (void *)mac_mb_cur_max}, {"___mb_cur_max_l", (void *)mac_mb_cur_max_l},
    MAC(isalnum_l), MAC(isalpha_l), MAC(isblank_l), MAC(iscntrl_l), MAC(isdigit_l), MAC(isgraph_l),
    MAC(islower_l), MAC(isprint_l), MAC(ispunct_l), MAC(isspace_l), MAC(isupper_l), MAC(isxdigit_l),
    MAC(tolower_l), MAC(toupper_l),
    MAC(iswalnum_l), MAC(iswalpha_l), MAC(iswblank_l), MAC(iswcntrl_l), MAC(iswdigit_l), MAC(iswgraph_l),
    MAC(iswlower_l), MAC(iswprint_l), MAC(iswpunct_l), MAC(iswspace_l), MAC(iswupper_l), MAC(iswxdigit_l),
    MAC(towlower_l), MAC(towupper_l), MAC(iswctype_l), MAC(wctype_l),
    MAC(strtol_l), MAC(strtoul_l), MAC(strtoll_l), MAC(strtoull_l), MAC(strtod_l), MAC(strtof_l),
    MAC(strtold_l), MAC(strcoll_l), MAC(strxfrm_l), MAC(wcscoll_l), MAC(wcsxfrm_l), MAC(strftime_l), MAC(strptime_l),
    MAC(snprintf_l), MAC(asprintf_l), MAC(sscanf_l), MAC(vsnprintf_l), MAC(vasprintf_l), MAC(vsprintf_l),
    MAC(sprintf_l), MAC(vsscanf_l),
    MAC(btowc_l), MAC(wctob_l), MAC(mbrtowc_l), MAC(wcrtomb_l), MAC(mbrlen_l), MAC(mbtowc_l), MAC(wctomb_l),
    MAC(mbsrtowcs_l), MAC(wcsrtombs_l), MAC(mbsnrtowcs_l), MAC(wcsnrtombs_l), MAC(mbstowcs_l),
    MAC(wcstombs_l), MAC(mblen_l),
    /* the C++ ABI's registration of static destructors, with this system's
     * C library (a Mac program's image header serves as its handle) */
    SAME(__cxa_atexit), SAME(__cxa_finalize),
    {NULL, NULL},
};
